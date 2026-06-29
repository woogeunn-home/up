import AppKit
import SwiftUI

@main
struct UpApp: App {
    @StateObject private var model = UpAppModel()

    var body: some Scene {
        MenuBarExtra {
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
}

@MainActor
private final class UpAppModel: ObservableObject {
    let monitor: ActivityMonitor
    private let completionPanelController: CompletionPanelController

    init() {
        let monitor = ActivityMonitor()
        let completionPanelController = CompletionPanelController(monitor: monitor)

        self.monitor = monitor
        self.completionPanelController = completionPanelController

        monitor.onStandUpAlert = { [weak completionPanelController] in
            completionPanelController?.show()
        }
        monitor.onSessionReset = { [weak completionPanelController] in
            completionPanelController?.close()
        }
    }
}

private struct MenuBarLabel: View {
    @EnvironmentObject private var monitor: ActivityMonitor
    @State private var blinkPhase = false

    private let blinkTimer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: monitor.menuBarSystemImage(blinkPhase: blinkPhase))

            if !statusText.isEmpty {
                Text(statusText)
                    .font(.system(size: NSFont.systemFontSize))
                    .monospacedDigit()
            }
        }
        .fixedSize()
        .onReceive(blinkTimer) { _ in
            blinkPhase.toggle()
        }
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
