import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let monitor: ActivityMonitor
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []
    private var blinkPhase = false
    private var blinkTimer: Timer?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var requiresInternalClose = false

    init(monitor: ActivityMonitor) {
        self.monitor = monitor
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        popover.behavior = .applicationDefined
        popover.delegate = self
        popover.contentSize = NSSize(width: MenuBarContent.contentWidth, height: 560)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContent { [weak self] in
                self?.closePopover()
            }
                .environmentObject(monitor)
        )

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
        }

        monitor.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateStatusItem()
                }
            }
            .store(in: &cancellables)

        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.blinkPhase.toggle()
                self?.updateStatusItem()
            }
        }

        updateStatusItem()
    }

    func showPopover() {
        showPopover(requiresInternalClose: false)
    }

    func showCompletionPopover() {
        updateStatusItem()
        showPopover(requiresInternalClose: true)
    }

    func closeCompletionPopover() {
        guard requiresInternalClose, popover.isShown else { return }
        closePopover()
    }

    private func showPopover(requiresInternalClose: Bool) {
        guard let button = statusItem.button else { return }
        self.requiresInternalClose = requiresInternalClose
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContent { [weak self] in
                self?.closePopover()
            }
            .environmentObject(monitor)
        )
        NSApp.activate(ignoringOtherApps: true)
        updateStatusItem()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        if requiresInternalClose {
            stopOutsideClickMonitoring()
        } else {
            startOutsideClickMonitoring()
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        requiresInternalClose = false
        stopOutsideClickMonitoring()
    }

    private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover(requiresInternalClose: false)
        }
    }

    @objc private func statusItemClicked() {
        guard !requiresInternalClose else { return }

        if monitor.hasExceededTarget {
            monitor.resetAfterCompletion()
        }

        togglePopover()
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let symbolName = monitor.menuBarSystemImage(blinkPhase: blinkPhase)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Up")
        image?.isTemplate = true
        button.image = image

        let text: String
        if monitor.hasExceededTarget {
            text = "Up!"
        } else if monitor.isRunning {
            text = "\(Int(ceil(monitor.remainingSeconds / 60)))분"
        } else {
            text = ""
        }

        let attributed = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.menuBarFont(ofSize: 0)]
        )
        button.attributedTitle = attributed
        button.imagePosition = text.isEmpty ? .imageOnly : .imageLeading
    }

    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitoring()
    }

    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self else { return event }
            let popoverWindow = self.popover.contentViewController?.view.window
            let statusWindow = self.statusItem.button?.window

            if event.window !== popoverWindow, event.window !== statusWindow {
                self.closePopover()
            }

            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover()
            }
        }
    }

    private func stopOutsideClickMonitoring() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }

        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }
}
