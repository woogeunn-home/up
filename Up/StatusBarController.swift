import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let monitor: ActivityMonitor
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []
    private var blinkPhase = false
    private var blinkTimer: Timer?
    private var requiresInternalClose = false

    init(monitor: ActivityMonitor) {
        self.monitor = monitor
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        popover.behavior = .transient   // standard menu-bar dismissal behavior
        popover.delegate = self
        popover.contentViewController = makeHostingController()

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

    private func makeHostingController() -> NSHostingController<some View> {
        let controller = NSHostingController(
            rootView: MenuBarContent(
                onClose: { [weak self] in self?.closePopover() },
                onPinPopover: { [weak self] pin in
                    self?.popover.behavior = pin ? .applicationDefined : .transient
                },
                onShake: { [weak self] in self?.shakePopover() }
            )
            .environmentObject(monitor)
        )
        controller.sizingOptions = .preferredContentSize
        return controller
    }

    func showPopover() {
        showPopover(requiresInternalClose: false)
    }

    func showCompletionPopover() {
        updateStatusItem()
        showPopover(requiresInternalClose: true)
        animateCompletionPopoverBounce()
    }

    func closeCompletionPopover() {
        guard requiresInternalClose, popover.isShown else { return }
        closePopover()
    }

    private func showPopover(requiresInternalClose: Bool) {
        guard let button = statusItem.button else { return }
        self.requiresInternalClose = requiresInternalClose
        // Completion popover must stay open until the user taps 확인, so use
        // .applicationDefined for that case; everything else uses the standard
        // .transient (auto-closes on outside click).
        popover.behavior = requiresInternalClose ? .applicationDefined : .transient
        popover.contentViewController = makeHostingController()
        updateStatusItem()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func closePopover() {
        requiresInternalClose = false
        popover.performClose(nil)
    }

    private func animateCompletionPopoverBounce() {
        guard let view = popover.contentViewController?.view else { return }
        view.wantsLayer = true

        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = [0.94, 1.05, 0.98, 1.0]
        animation.keyTimes = [0, 0.42, 0.72, 1]
        animation.duration = 0.36
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeOut)
        ]
        animation.isRemovedOnCompletion = true

        view.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        view.layer?.add(animation, forKey: "completionPopoverBounce")
    }

    /// Shake the whole popover window left-right with a quick damped wobble,
    /// in sync with the in-scene slosh.
    private func shakePopover() {
        guard let frameView = popover.contentViewController?.view.window?.contentView else { return }
        frameView.wantsLayer = true

        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [0, -5, 4, -3, 2, -1, 0]
        animation.keyTimes = [0, 0.12, 0.30, 0.50, 0.68, 0.85, 1]
        animation.duration = 0.4
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animation.isRemovedOnCompletion = true

        frameView.layer?.add(animation, forKey: "popoverShake")
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
            text = " \(Int(ceil(monitor.remainingSeconds / 60)))분 후 휴식"
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

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        !requiresInternalClose
    }

    func popoverDidClose(_ notification: Notification) {
        requiresInternalClose = false
    }
}
