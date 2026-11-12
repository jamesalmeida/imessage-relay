#if os(macOS)
import AppKit
import Darwin
import IMessageRelayCore
import SwiftUI

@main
enum IMessageRelayMain {
    // Plain AppKit entry point: the menu bar item and Settings window are managed by the
    // AppDelegate, so no SwiftUI App scene (which would add a stray empty window) is needed.
    static func main() {
        if shouldRunCLI(CommandLine.arguments) {
            exit(runCLI(CommandLine.arguments))
        }
        UserDefaults.standard.register(defaults: RelayPreferences.registration)
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusBar = StatusBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        RelayController.shared.bootstrap()
        statusBar.install()
        if !RelayController.shared.webhookConfigured {
            RelayController.shared.openSettings()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        RelayController.shared.openSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        RelayController.shared.stop()
    }
}
#endif
