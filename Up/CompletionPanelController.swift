import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class CompletionPanelController: NSObject {
    private let monitor: ActivityMonitor
    private var panel: NSPanel?

    init(monitor: ActivityMonitor) {
        self.monitor = monitor
        super.init()
    }

    func show() {
        let panel = makePanel()
        self.panel = panel
        positionPanel(panel)
        panel.orderFrontRegardless()
        animateBounce()
    }

    func close() {
        panel?.close()
        panel = nil
    }

    private func makePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let rootView = CompletionPanelContent(
            onConfirm: { [weak self] in
                self?.monitor.resetAfterCompletion()
                self?.close()
            },
            onShake: { [weak self] in
                self?.shake()
            }
        )
        .environmentObject(monitor)

        let hostingController = NSHostingController(rootView: rootView)
        let panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: MenuBarContent.contentWidth,
                height: AnimationHolder.minBoxHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        return panel
    }

    private func positionPanel(_ panel: NSPanel) {
        panel.layoutIfNeeded()

        let frame = panel.frame
        let screen = NSScreen.screens.first { screen in
            screen.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main ?? NSScreen.screens.first

        guard let visibleFrame = screen?.visibleFrame else { return }

        let margin: CGFloat = 16
        let origin = NSPoint(
            x: visibleFrame.maxX - frame.width - margin,
            y: visibleFrame.maxY - frame.height - margin
        )
        panel.setFrameOrigin(origin)
    }

    private func animateBounce() {
        guard let view = panel?.contentView else { return }
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
        view.layer?.add(animation, forKey: "completionPanelBounce")
    }

    private func shake() {
        guard let view = panel?.contentView else { return }
        view.wantsLayer = true

        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [0, -5, 4, -3, 2, -1, 0]
        animation.keyTimes = [0, 0.12, 0.30, 0.50, 0.68, 0.85, 1]
        animation.duration = 0.4
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animation.isRemovedOnCompletion = true

        view.layer?.add(animation, forKey: "completionPanelShake")
    }
}

private struct CompletionPanelContent: View {
    var onConfirm: () -> Void
    var onShake: (() -> Void)?

    private let contentPadding: CGFloat = 16

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.separator.opacity(0.5), lineWidth: 1)
                }

            CompletionAnimationView(onShake: onShake)

            Button {
                onConfirm()
            } label: {
                Text("알겠어, 일어날게!")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.solidButtonForeground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(.solidButtonBackground, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
            .padding(.horizontal, contentPadding)
            .padding(.bottom, contentPadding)
        }
        .frame(width: MenuBarContent.contentWidth)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
