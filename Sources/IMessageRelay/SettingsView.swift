#if os(macOS)
import AppKit
import IMessageRelayCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var controller = RelayController.shared
    @State private var webhookURL = ""
    @State private var authHeader = ""
    @State private var notice = ""
    @State private var testing = false

    var body: some View {
        Form {
            Section("Webhook") {
                TextField("Webhook URL", text: $webhookURL)
                    .textFieldStyle(.roundedBorder)
                SecureField("Auth header", text: $authHeader)
                    .textFieldStyle(.roundedBorder)
                Text("The header may be “Bearer …” or “Authorization: Bearer …”. Both the URL and the header are stored in the Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Save") { save() }
                    Button(testing ? "Testing…" : "Test webhook") { testWebhook() }
                        .disabled(testing)
                    Button("Import config.json…") { importConfig() }
                }
                if !notice.isEmpty {
                    Text(notice)
                        .font(.callout)
                }
            }
            Section("Relay") {
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
                Stepper(value: Binding(
                    get: { controller.pollSeconds },
                    set: { controller.setPollSeconds($0) }
                ), in: 1...3600, step: 1) {
                    Text("Poll seconds: \(Int(controller.pollSeconds))")
                }
                Picker("When re-enabled", selection: Binding(
                    get: { controller.reenableBehavior },
                    set: { controller.setReenableBehavior($0) }
                )) {
                    Text("Skip missed").tag(ReenableBehavior.skipMissed)
                    Text("Catch up").tag(ReenableBehavior.catchUp)
                }
                Text("Skip missed moves the high-water mark to the newest row when you turn Enabled back on. Catch up forwards texts that arrived while the relay was paused. Quitting the app does not use this choice; the next launch resumes from the saved mark.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Enabled", isOn: Binding(
                    get: { controller.enabled },
                    set: { controller.setEnabled($0) }
                ))
            }
            Section("App") {
                Toggle("Show in Dock", isOn: Binding(
                    get: { controller.showInDock },
                    set: { controller.setShowInDock($0) }
                ))
                Toggle("Launch at login", isOn: Binding(
                    get: { controller.launchAtLogin },
                    set: { controller.setLaunchAtLogin($0) }
                ))
                if !controller.loginItemNote.isEmpty {
                    Text(controller.loginItemNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Messages database") {
                    Text(databaseStatus)
                }
                Button("Open Full Disk Access settings") {
                    controller.openFullDiskAccessSettings()
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520)
        .onAppear(perform: loadSecrets)
    }

    private var databaseStatus: String {
        let path = RelayPaths.chatDatabase(home: FileManager.default.homeDirectoryForCurrentUser).path
        return (try? SQLiteMessageStore(path: path)) == nil ? "Needs Full Disk Access" : "Readable"
    }

    private func loadSecrets() {
        webhookURL = KeychainStore.load(account: KeychainStore.webhookAccount) ?? ""
        authHeader = KeychainStore.load(account: KeychainStore.authAccount) ?? ""
    }

    private func save() {
        let trimmed = webhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else {
            notice = "Webhook URL must be http or https."
            return
        }
        guard KeychainStore.save(account: KeychainStore.webhookAccount, secret: trimmed) else {
            notice = "Could not save the webhook to the Keychain."
            return
        }
        let header = normalizeAuthorizationHeader(authHeader) ?? ""
        let headerOK: Bool
        if header.isEmpty {
            KeychainStore.delete(account: KeychainStore.authAccount)
            headerOK = true
        } else {
            headerOK = KeychainStore.save(account: KeychainStore.authAccount, secret: header)
        }
        notice = headerOK ? "Saved." : "The URL was saved. The auth header could not be saved."
        appendRelayLog(headerOK ? "webhook settings saved" : "webhook URL saved; auth header was not saved")
        controller.nudge()
    }

    private func testWebhook() {
        let trimmed = webhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else {
            notice = "Webhook URL must be http or https."
            return
        }
        testing = true
        notice = "Sending test…"
        let header = normalizeAuthorizationHeader(authHeader)
        let body = Data(#"{"event":"test"}"#.utf8)
        DispatchQueue.global(qos: .userInitiated).async {
            let result: String
            do {
                let status = try URLSessionWebhookClient().post(body: body, url: url, authorization: header)
                result = "Test webhook returned HTTP \(status)."
            } catch let error as WebhookError {
                result = "Test webhook failed (\(error.description))."
            } catch {
                result = "Test webhook failed."
            }
            DispatchQueue.main.async {
                testing = false
                notice = result
            }
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a config.json file. It must be mode 600 or stricter."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let config = try loadConfig(from: url.path)
                webhookURL = config.webhookURL.absoluteString
                authHeader = config.authorizationHeader ?? ""
                controller.setDetailLevel(config.detailLevel)
                controller.setSkipOneTimeCodes(config.skipOneTimeCodes)
                controller.setPollSeconds(config.pollSeconds)
                notice = "Imported into the form. Save to store the webhook in the Keychain."
            } catch {
                notice = String(describing: error)
            }
        }
    }
}
#endif
