import Combine
import AppKit
import Foundation
import IOKit

@MainActor
final class ActivityMonitor: ObservableObject {
    static let minimumTargetSeconds: TimeInterval = 60
    static let defaultTargetSeconds: TimeInterval = 60 * 60
    static let defaultInactivityResetSeconds: TimeInterval = 5 * 60
    static let completionImageBookmarkKey = "completionImageBookmarkData"

    var onStandUpAlert: (() -> Void)?
    var onSessionReset: (() -> Void)?

    @Published var targetSeconds: TimeInterval {
        didSet {
            let clampedTargetSeconds = max(Self.minimumTargetSeconds, targetSeconds)
            if targetSeconds != clampedTargetSeconds {
                targetSeconds = clampedTargetSeconds
                return
            }

            UserDefaults.standard.set(clampedTargetSeconds, forKey: "targetSeconds")
        }
    }

    @Published var inactivityResetSeconds: TimeInterval {
        didSet {
            let clamped = max(60, inactivityResetSeconds)
            if inactivityResetSeconds != clamped {
                inactivityResetSeconds = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: "inactivityResetSeconds")
        }
    }

    @Published var completionImageBookmarkData: Data? {
        didSet {
            UserDefaults.standard.set(completionImageBookmarkData, forKey: Self.completionImageBookmarkKey)
        }
    }

    @Published private(set) var activeSeconds: TimeInterval = 0
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var isUserActive = false

    private var timer: Timer?
    private var hasAlertedForCurrentSession = false
    private let activeIdleThreshold: TimeInterval = 15

    init() {
        UserDefaults.standard.register(defaults: [
            "targetSeconds": Self.defaultTargetSeconds,
            "inactivityResetSeconds": Self.defaultInactivityResetSeconds
        ])
        let savedTarget = UserDefaults.standard.double(forKey: "targetSeconds")
        targetSeconds = savedTarget > 0 ? max(savedTarget, Self.minimumTargetSeconds) : Self.defaultTargetSeconds
        let savedReset = UserDefaults.standard.double(forKey: "inactivityResetSeconds")
        inactivityResetSeconds = savedReset > 0 ? max(savedReset, 60) : Self.defaultInactivityResetSeconds
        completionImageBookmarkData = UserDefaults.standard.data(forKey: Self.completionImageBookmarkKey)
        startTimer()
    }

    var progress: Double {
        guard targetSeconds > 0 else { return 0 }
        return min(activeSeconds / targetSeconds, 1)
    }

    var remainingSeconds: TimeInterval {
        max(targetSeconds - activeSeconds, 0)
    }

    var hasExceededTarget: Bool {
        activeSeconds >= targetSeconds
    }

    func menuBarSystemImage(blinkPhase: Bool) -> String {
        if hasExceededTarget {
            return blinkPhase ? "chevron.up.circle.fill" : "arrow.up.circle.fill"
        }

        if !isRunning && activeSeconds == 0 {
            return "arrow.up.circle.dotted"
        }

        if isRunning && isUserActive {
            return "pointer.arrow.click.2"
        }

        if !isUserActive {
            return "pointer.arrow.click.badge.clock"
        }

        return "arrow.up.circle.dotted"
    }

    func resetAfterCompletion() {
        activeSeconds = 0
        isRunning = false
        isPaused = false
        hasAlertedForCurrentSession = false
    }

    func setCompletionImageURL(_ url: URL) throws {
        completionImageBookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func clearCompletionImage() {
        completionImageBookmarkData = nil
    }

    func completionImage() -> NSImage? {
        guard let completionImageBookmarkData else {
            return bundledCompletionImage()
        }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: completionImageBookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            return NSImage(contentsOf: url) ?? bundledCompletionImage()
        } catch {
            return bundledCompletionImage()
        }
    }

    func togglePause() {
        guard !hasExceededTarget else { return }
        isPaused.toggle()
        if isPaused {
            isRunning = false
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        let idleSeconds = SystemIdleTime.seconds()
        isUserActive = idleSeconds <= activeIdleThreshold

        guard !isPaused else {
            return
        }

        if idleSeconds >= inactivityResetSeconds {
            resetCurrentSessionProgress()
            return
        }

        guard !hasExceededTarget else {
            return
        }

        if isUserActive {
            isRunning = true
            activeSeconds += 1
        }

        if activeSeconds >= targetSeconds, !hasAlertedForCurrentSession {
            notifyStandUp()
        }
    }

    private func resetCurrentSessionProgress() {
        guard activeSeconds != 0 || hasAlertedForCurrentSession else { return }
        activeSeconds = 0
        isRunning = false
        isPaused = false
        hasAlertedForCurrentSession = false
        onSessionReset?()
    }

    private func notifyStandUp() {
        hasAlertedForCurrentSession = true
        NSSound(named: "Hero")?.play()
        onStandUpAlert?()
    }

    private func bundledCompletionImage() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "PopoverHeader", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

enum SystemIdleTime {
    static func seconds() -> TimeInterval {
        var iterator: io_iterator_t = 0
        defer {
            if iterator != 0 {
                IOObjectRelease(iterator)
            }
        }

        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"), &iterator)
        guard result == KERN_SUCCESS else { return .greatestFiniteMagnitude }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return .greatestFiniteMagnitude }
        defer { IOObjectRelease(entry) }

        var properties: Unmanaged<CFMutableDictionary>?
        let propertiesResult = IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0)
        guard propertiesResult == KERN_SUCCESS, let dictionary = properties?.takeRetainedValue() else {
            return .greatestFiniteMagnitude
        }

        let key = "HIDIdleTime" as CFString
        let value = CFDictionaryGetValue(dictionary, Unmanaged.passUnretained(key).toOpaque())
        guard value != nil else { return .greatestFiniteMagnitude }

        let number = unsafeBitCast(value, to: CFNumber.self)
        var nanoseconds: Int64 = 0
        guard CFNumberGetValue(number, .sInt64Type, &nanoseconds) else {
            return .greatestFiniteMagnitude
        }

        return TimeInterval(nanoseconds) / 1_000_000_000
    }
}
