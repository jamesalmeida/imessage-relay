#if os(macOS)
import AppKit
import Combine
import IMessageRelayCore

/// Owns the menu bar item. Uses NSStatusItem directly with a unique autosave name,
/// instead of SwiftUI's MenuBarExtra (which registered as the shared "Item-0" name).
final class StatusBarController: NSObject, NSMenuDelegate {
    static let autosaveName = "com.jamesalmeida.imessage-relay.statusitem"

    private let controller = RelayController.shared
    private var statusItem: NSStatusItem?
    private var cancellable: AnyCancellable?

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.autosaveName
        item.isVisible = true
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateIcon(controller.statusKind)
        cancellable = controller.$statusKind
            .receive(on: DispatchQueue.main)
            .sink { [weak self] kind in self?.updateIcon(kind) }
        appendRelayLog("menu bar item installed visible=\(item.isVisible)")
    }

    private func updateIcon(_ kind: RelayStatusKind) {
        guard let button = statusItem?.button else { return }
        let image = NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: "iMessage Relay")
        image?.isTemplate = true
        button.image = image
        if image == nil { button.title = "iR" }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(NSMenuItem(title: RelayPaths.appDisplayName, action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Status: \(controller.statusKind.label)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: lastForwardedLine, action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let enabled = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self
        enabled.state = controller.enabled ? .on : .off
        menu.addItem(enabled)

        let detail = NSMenuItem(title: "Detail level", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (title, level) in [("Ping", DetailLevel.ping), ("Sender", .sender), ("Full", .full)] {
            let entry = NSMenuItem(title: title, action: #selector(pickDetail(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = level.rawValue
            entry.state = controller.detailLevel == level ? .on : .off
            sub.addItem(entry)
        }
        detail.submenu = sub
        menu.addItem(detail)

        let skip = NSMenuItem(title: "Skip one-time codes", action: #selector(toggleSkip), keyEquivalent: "")
        skip.target = self
        skip.state = controller.skipOneTimeCodes ? .on : .off
        menu.addItem(skip)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let log = NSMenuItem(title: "Open log", action: #selector(openLog), keyEquivalent: "")
        log.target = self
        menu.addItem(log)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private var lastForwardedLine: String {
        guard let date = controller.lastForwarded else { return "Last forwarded: never" }
        return "Last forwarded: " + date.formatted(date: .abbreviated, time: .shortened)
    }

    @objc private func toggleEnabled() { controller.setEnabled(!controller.enabled) }
    @objc private func toggleSkip() { controller.setSkipOneTimeCodes(!controller.skipOneTimeCodes) }
    @objc private func pickDetail(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let level = DetailLevel(rawValue: raw) {
            controller.setDetailLevel(level)
        }
    }
    @objc private func openSettings() { controller.openSettings() }
    @objc private func openLog() { controller.openLog() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
#endif
