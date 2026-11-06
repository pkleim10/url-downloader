import AppKit
import SwiftUI

@main
struct SiphonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var queue = DownloadQueue()

    var body: some Scene {
        Window("Siphon", id: WindowID.main) {
            ContentView(queue: queue)
                .onAppear { appDelegate.queue = queue }
        }
        .defaultSize(width: 760, height: 540)

        Window("Sites", id: WindowID.sites) {
            SitesView(queue: queue)
        }
        .defaultSize(width: 640, height: 520)

        Window("History", id: WindowID.history) {
            HistoryView(queue: queue)
        }
        .defaultSize(width: 720, height: 560)

        Settings {
            SettingsView(queue: queue)
        }
    }
}

enum WindowID {
    static let main = "main"
    static let sites = "sites"
    static let history = "history"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var queue: DownloadQueue?

    func applicationWillTerminate(_ notification: Notification) {
        queue?.shutdown()
    }
}
