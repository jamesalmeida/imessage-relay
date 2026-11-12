#if os(macOS)
import AppKit
import IMessageRelayCore
import SwiftUI

struct MenuLabel: View {
    @ObservedObject private var controller = RelayController.shared

    var body: some View {
        Image(systemName: controller.statusKind.symbolName)
            .opacity(controller.statusKind == .running ? 1 : 0.45)
    }
}

struct MenuContent: View {
    @ObservedObject private var controller = RelayController.shared

    var body: some View {
        Text(RelayPaths.appDisplayName)
        Text("Status: \(controller.statusKind.label)")
        Text(lastForwardedLine)
        Divider()
        Toggle("Enabled", isOn: Binding(
            get: { controller.enabled },
            set: { controller.setEnabled($0) }
        ))
        Picker("Detail level", selection: Binding(
            get: { controller.detailLevel },
            set: { controller.setDetailLevel($0) }
        )) {
            Text("Ping").tag(DetailLevel.ping)
            Text("Sender").tag(DetailLevel.sender)
            Text("Full").tag(DetailLevel.full)
        }
        Toggle("Skip one-time codes", isOn: Binding(
            get: { controller.skipOneTimeCodes },
            set: { controller.setSkipOneTimeCodes($0) }
        ))
        Divider()
        Button("Settings…") { controller.openSettings() }
        Button("Open log") { controller.openLog() }
        Divider()
        Button("Quit") { NSApplication.shared.terminate(nil) }
    }

    private var lastForwardedLine: String {
        guard let date = controller.lastForwarded else { return "Last forwarded: never" }
        return "Last forwarded: " + date.formatted(date: .abbreviated, time: .shortened)
    }
}
#endif
