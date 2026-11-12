#if os(macOS)
import AppKit
import Darwin
import IMessageRelayCore
import SwiftUI

@main
struct IMessageRelayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        if shouldRunCLI(CommandLine.arguments) {
            let code = runCLI(CommandLine.arguments)
            exit(code)
        }
        UserDefaults.standard.register(defaults: RelayPreferences.registration)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
        } label: {
            MenuLabel()
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        RelayController.shared.bootstrap()
    }

    func applicationWillTerminate(_ notification: Notification) {
        RelayController.shared.stop()
    }
}
#endif
