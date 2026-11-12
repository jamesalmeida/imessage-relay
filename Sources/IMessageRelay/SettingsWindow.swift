#if os(macOS)
import AppKit
import IMessageRelayCore
import SwiftUI

/// A manually managed window hosting SettingsView. SwiftUI's Settings scene cannot be
/// opened reliably from AppKit code on macOS 14+.
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let win = NSWindow(contentViewController: hosting)
            win.title = "iMessage Relay"
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.isReleasedWhenClosed = false
            win.setContentSize(NSSize(width: 560, height: 680))
            win.center()
            window = win
        }
        guard let win = window else { return }
        NSApp.activate()
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
        appendRelayLog("settings window opened visible=\(win.isVisible) key=\(win.isKeyWindow)")
    }
}
#endif
