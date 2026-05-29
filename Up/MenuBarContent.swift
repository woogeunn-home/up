import SwiftUI
import AppKit

struct MenuBarContent: View {
    static let contentWidth: CGFloat = 280

    private let contentWidth: CGFloat = Self.contentWidth
    private let contentPadding: CGFloat = 16
    var onClose: (() -> Void)?
    var onPinPopover: ((Bool) -> Void)?

    @EnvironmentObject private var monitor: ActivityMonitor
    @State private var showsSettings = false

    var body: some View {
        Group {
            if showsSettings {
                UpSettingsView(onPinPopover: onPinPopover) {
                    showsSettings = false
                }
                .environmentObject(monitor)
            } else {
                mainContent
            }
        }
        .frame(width: contentWidth)
    }

    @ViewBuilder
    private var mainContent: some View {
        if monitor.hasExceededTarget {
            completionContent
        } else {
            activeContent
        }
    }

    private var completionContent: some View {
        // Animation fills the entire popover; the confirm button floats above
        // it (overlay) with its own padding. Shapes physically pile up from the
        // popover's bottom edge, so the bottom-most shapes show through the
        // floating glass button.
        ZStack(alignment: .bottom) {
            CompletionAnimationView()

            Button {
                monitor.resetAfterCompletion()
                onClose?()
            } label: {
                Text("알겠어, 일어날게!")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .modifier(GlassCapsule())
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
            .padding(.horizontal, contentPadding)
            .padding(.bottom, contentPadding)
        }
    }

    private var activeContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Up")
                    .font(.headline)
                Spacer()
                Button {
                    showsSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            ProgressView(value: monitor.progress)

            HStack {
                Label(timeString(monitor.remainingSeconds), systemImage: "hourglass")
                Spacer()
                Button {
                    monitor.togglePause()
                } label: {
                    Image(systemName: monitor.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(monitor.isPaused ? "재개" : "일시정지")
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(contentPadding)
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Glass capsule modifier

/// Applies the macOS 26 Liquid Glass material clipped to a Capsule. On older
/// systems, falls back to a regularMaterial-filled capsule.
private struct GlassCapsule: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.clear.interactive(), in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}
