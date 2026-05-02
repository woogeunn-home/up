import SwiftUI
import AppKit

struct MenuBarContent: View {
    static let contentWidth: CGFloat = 280

    private let contentWidth: CGFloat = Self.contentWidth
    private let contentPadding: CGFloat = 16
    private let headerCornerRadius: CGFloat = 10
    var onClose: (() -> Void)?

    @EnvironmentObject private var monitor: ActivityMonitor
    @State private var showsSettings = false

    var body: some View {
        Group {
            if showsSettings {
                UpSettingsView {
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
        VStack(alignment: .leading, spacing: 16) {
            if let headerImage {
                Image(nsImage: headerImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: headerImageWidth, height: headerImageHeight)
                    .clipShape(RoundedRectangle(cornerRadius: headerCornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: headerCornerRadius, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    }
                    .layoutPriority(1)
            }

            Button {
                monitor.resetAfterCompletion()
                onClose?()
            } label: {
                Text("확인")
                    .font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .padding(contentPadding)
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

    private var headerImageWidth: CGFloat {
        contentWidth - (contentPadding * 2)
    }

    private var headerImageHeight: CGFloat {
        guard let headerImage, headerImage.size.width > 0 else {
            return headerImageWidth
        }
        return headerImageWidth * (headerImage.size.height / headerImage.size.width)
    }

    private var headerImage: NSImage? {
        guard let url = Bundle.main.url(forResource: "PopoverHeader", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
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
