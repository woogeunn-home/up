import AppKit
import Combine
import SwiftUI

@main
struct UpApp: App {
    @StateObject private var model = UpAppModel()

    var body: some Scene {
        MenuBarExtra(isInserted: activeMenuBarExtraBinding) {
            MenuBarContent()
                .environmentObject(model.monitor)
        } label: {
            MenuBarLabel()
                .environmentObject(model.monitor)
        }
        .menuBarExtraStyle(.window)

        Settings {
            EmptyView()
        }
    }

    private var activeMenuBarExtraBinding: Binding<Bool> {
        Binding {
            !model.monitor.hasExceededTarget
        } set: { _ in }
    }
}

@MainActor
private final class UpAppModel: ObservableObject {
    let monitor: ActivityMonitor
    private let completionPanelController: CompletionPanelController
    private let completionStatusItemController: CompletionStatusItemController

    init() {
        let monitor = ActivityMonitor()
        let completionPanelController = CompletionPanelController(monitor: monitor)
        let completionStatusItemController = CompletionStatusItemController(
            monitor: monitor,
            onMenuWillOpen: { [weak completionPanelController] in
                completionPanelController?.close()
            }
        )

        self.monitor = monitor
        self.completionPanelController = completionPanelController
        self.completionStatusItemController = completionStatusItemController

        monitor.onStandUpAlert = { [weak completionPanelController] in
            completionPanelController?.show()
        }
        monitor.onSessionReset = { [weak completionPanelController] in
            completionPanelController?.close()
        }
    }
}

@MainActor
private final class CompletionStatusItemController: NSObject, NSMenuDelegate {
    private let monitor: ActivityMonitor
    private let onMenuWillOpen: () -> Void
    private var statusItem: NSStatusItem?
    private var cancellable: AnyCancellable?
    private var blinkTimer: Timer?
    private var blinkPhase = false

    init(monitor: ActivityMonitor, onMenuWillOpen: @escaping () -> Void) {
        self.monitor = monitor
        self.onMenuWillOpen = onMenuWillOpen
        super.init()

        cancellable = Publishers.CombineLatest(monitor.$activeSeconds, monitor.$targetSeconds)
            .map { $0 >= $1 }
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateVisibility()
                }
            }
        updateVisibility()
    }

    private func updateVisibility() {
        if monitor.hasExceededTarget {
            showStatusItem()
        } else {
            hideStatusItem()
        }
    }

    private func showStatusItem() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem?.menu = makeMenu()
        }

        updateButton()
        startBlinking()
    }

    private func hideStatusItem() {
        stopBlinking()

        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let confirmItem = NSMenuItem(
            title: "알겠어, 일어날게!",
            action: #selector(confirm),
            keyEquivalent: ""
        )
        confirmItem.target = self
        menu.addItem(confirmItem)
        return menu
    }

    nonisolated func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor in
            onMenuWillOpen()
        }
    }

    private func updateButton() {
        guard let button = statusItem?.button else { return }

        button.image = NSImage(
            systemSymbolName: monitor.menuBarSystemImage(blinkPhase: blinkPhase),
            accessibilityDescription: "Up"
        )
        button.imagePosition = .imageLeft
        button.title = "Up!"
    }

    private func startBlinking() {
        guard blinkTimer == nil else { return }

        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.blinkPhase.toggle()
                self.updateButton()
            }
        }
    }

    private func stopBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        blinkPhase = false
    }

    @objc private func confirm() {
        monitor.resetAfterCompletion()
    }
}

private struct MenuBarLabel: View {
    @EnvironmentObject private var monitor: ActivityMonitor

    var body: some View {
        HStack(spacing: 5) {
            // MenuBarLabel은 !hasExceededTarget일 때만 보이므로 blinkPhase는 무의미.
            Image(systemName: monitor.menuBarSystemImage(blinkPhase: false))

            if !statusText.isEmpty {
                Text(statusText)
                    .font(.system(size: NSFont.systemFontSize))
                    .monospacedDigit()
            }
        }
        .fixedSize()
    }

    private var statusText: String {
        if monitor.hasExceededTarget {
            return "Up!"
        }

        if monitor.isRunning {
            return "\(Int(ceil(monitor.remainingSeconds / 60)))분 후 휴식"
        }

        return ""
    }
}
