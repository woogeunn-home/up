import SwiftUI
import AppKit

@main
struct UpApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = ActivityMonitor()
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = StatusBarController(monitor: monitor)
        statusBarController = controller
        monitor.onStandUpAlert = { [weak controller] in
            controller?.showCompletionPopover()
        }
    }
}
