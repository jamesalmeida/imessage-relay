#if os(macOS)
import AppKit
import Foundation
import IMessageRelayCore
import ServiceManagement

enum RelayStatusKind: Equatable {
    case running
    case disabled
    case needsFullDiskAccess
    case notConfigured
    case alreadyRunning

    var label: String {
        switch self {
        case .running: return "Running"
        case .disabled: return "Disabled"
        case .needsFullDiskAccess: return "Error: needs Full Disk Access"
        case .notConfigured: return "Not configured"
        case .alreadyRunning: return "Error: already running"
        }
    }

    var symbolName: String {
        switch self {
        case .running: return "bubble.left.fill"
        case .disabled, .notConfigured, .alreadyRunning, .needsFullDiskAccess:
            return "bubble.left.slash"
        }
    }
}

final class RelayController: ObservableObject {
    static let shared = RelayController()

    @Published var statusKind: RelayStatusKind = .disabled
    @Published var lastForwarded: Date?
    @Published var enabled: Bool
    @Published var detailLevel: DetailLevel
    @Published var skipOneTimeCodes: Bool
    @Published var pollSeconds: Double
    @Published var showInDock: Bool
    @Published var launchAtLogin: Bool
    @Published var reenableBehavior: ReenableBehavior
    @Published var loginItemNote: String = ""

    private let defaults: UserDefaults
    private let stopFlag = StopFlag()
    private let wake = DispatchSemaphore(value: 0)
    private let workQueue = DispatchQueue(label: "com.jamesalmeida.imessage-relay.loop")
    private var loopRunning = false
    private var bootstrapped = false
    private var lockFD: Int32 = -1
    private let contacts: ContactBook
    private let stateStore: FileHighWaterStore
    private let home: URL

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: RelayPreferences.registration)
        let prefs = RelayPreferences.load(from: defaults)
        enabled = prefs.enabled
        detailLevel = prefs.detailLevel
        skipOneTimeCodes = prefs.skipOneTimeCodes
        pollSeconds = prefs.pollSeconds
        showInDock = prefs.showInDock
        launchAtLogin = prefs.launchAtLogin
        reenableBehavior = prefs.reenableBehavior
        if let stamp = defaults.object(forKey: RelayPreferences.Key.lastForwardedAt) as? Double, stamp > 0 {
            lastForwarded = Date(timeIntervalSince1970: stamp)
        }
        home = FileManager.default.homeDirectoryForCurrentUser
        stateStore = FileHighWaterStore(url: RelayPaths.stateFile(home: home))
        let root = RelayPaths.addressBookRoot(home: home)
        contacts = ContactBook(loader: {
            try AddressBookLoader(roots: [root]).load()
        }, logger: appendRelayLog)
    }

    func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true
        prepareDirectories()
        let stateDir = RelayPaths.stateDirectory(home: home).path
        if let fd = acquireLock(directory: stateDir) {
            lockFD = fd
        } else {
            publish(.alreadyRunning)
            appendRelayLog("another imessage-relay is already running")
            return
        }
        applyDockPolicy(showInDock)
        applyLoginItem(launchAtLogin, userInitiated: false)
        publish(enabled ? .notConfigured : .disabled)
        if enabled {
            workQueue.async { self.loop() }
        }
        appendRelayLog("starting detail_level=\(detailLevel.rawValue) skip_one_time_codes=\(skipOneTimeCodes) poll_seconds=\(pollSeconds)")
    }

    func stop() {
        // Do not touch the saved enabled flag: quitting must not turn the relay off for the next launch.
        stopFlag.set()
        wake.signal()
        appendRelayLog("stopping")
    }

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        persist()
        if on {
            workQueue.async {
                self.stopFlag.clear()
                self.applyReenablePolicy()
                self.loop()
            }
        } else {
            stopFlag.set()
            wake.signal()
            publish(.disabled)
            appendRelayLog("paused")
        }
    }

    func setDetailLevel(_ level: DetailLevel) {
        detailLevel = level
        persist()
    }

    func setSkipOneTimeCodes(_ skip: Bool) {
        skipOneTimeCodes = skip
        persist()
    }

    func setPollSeconds(_ seconds: Double) {
        let clamped = min(max(seconds, 1), 86_400)
        pollSeconds = clamped
        persist()
        wake.signal()
    }

    func setShowInDock(_ show: Bool) {
        showInDock = show
        persist()
        applyDockPolicy(show)
    }

    func setLaunchAtLogin(_ on: Bool) {
        launchAtLogin = on
        persist()
        applyLoginItem(on, userInitiated: true)
    }

    func setReenableBehavior(_ behavior: ReenableBehavior) {
        reenableBehavior = behavior
        persist()
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func openLog() {
        prepareDirectories()
        let url = RelayPaths.logFile(home: home)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(
                atPath: url.path,
                contents: nil,
                attributes: [.posixPermissions: NSNumber(value: 0o600)]
            )
        }
        NSWorkspace.shared.open(url)
    }

    func openSettings() {
        DispatchQueue.main.async { SettingsWindowController.shared.show() }
    }

    var webhookConfigured: Bool {
        guard let raw = KeychainStore.load(account: KeychainStore.webhookAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !raw.isEmpty
    }

    /// Wake the poll loop so a newly saved webhook is picked up without waiting out the interval.
    func nudge() {
        wake.signal()
    }

    private func loop() {
        if loopRunning { return }
        loopRunning = true
        defer { loopRunning = false }
        var attempt = 1
        while !stopFlag.isSet && defaults.bool(forKey: RelayPreferences.Key.enabled) {
            let prefs = RelayPreferences.load(from: defaults)
            guard let config = liveConfig(prefs) else {
                publish(.notConfigured)
                wait(prefs.pollSeconds)
                attempt = 1
                continue
            }
            let chatPath = RelayPaths.chatDatabase(home: home).path
            let store: SQLiteMessageStore
            do {
                store = try SQLiteMessageStore(path: chatPath)
            } catch {
                publish(.needsFullDiskAccess)
                appendRelayLog("database unreadable; Full Disk Access is required")
                wait(max(prefs.pollSeconds, 5))
                continue
            }
            let poster = MarkingPoster { [weak self] in
                self?.noteForwarded()
            }
            let engine = RelayEngine(
                source: store,
                contacts: contacts,
                state: stateStore,
                poster: poster,
                config: config,
                timeZone: .current,
                logger: appendRelayLog
            )
            engine.shouldContinue = { [stopFlag, defaults] in
                !stopFlag.isSet && defaults.bool(forKey: RelayPreferences.Key.enabled)
            }
            do {
                let outcome = try engine.runBatch()
                if stopFlag.isSet || !defaults.bool(forKey: RelayPreferences.Key.enabled) {
                    break
                }
                if outcome.failedRowID != nil {
                    let summary = outcome.failureSummary ?? "error=failed"
                    if summary == "error=state" {
                        appendRelayLog("state save failed rowid=\(outcome.failedRowID ?? 0) attempt=\(attempt) error=state")
                    } else {
                        appendRelayLog("webhook failed rowid=\(outcome.failedRowID ?? 0) attempt=\(attempt) \(summary)")
                    }
                    wait(retryDelaySeconds(attempt: attempt))
                    attempt += 1
                    continue
                }
                publish(.running)
                attempt = 1
                wait(RelayPreferences.load(from: defaults).pollSeconds)
            } catch let error as HighWaterError {
                appendRelayLog(error.description)
                wait(retryDelaySeconds(attempt: attempt))
                attempt += 1
            } catch {
                publish(.needsFullDiskAccess)
                appendRelayLog("database read failed")
                wait(max(prefs.pollSeconds, 5))
            }
        }
        if !defaults.bool(forKey: RelayPreferences.Key.enabled) {
            publish(.disabled)
        }
    }

    private func liveConfig(_ prefs: RelayPreferences) -> RelayConfig? {
        guard let raw = KeychainStore.load(account: KeychainStore.webhookAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty,
            let url = URL(string: raw),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            url.host != nil
        else {
            return nil
        }
        let auth = normalizeAuthorizationHeader(KeychainStore.load(account: KeychainStore.authAccount))
        return RelayConfig(
            webhookURL: url,
            authorizationHeader: auth,
            pollSeconds: prefs.pollSeconds,
            skipOneTimeCodes: prefs.skipOneTimeCodes,
            detailLevel: prefs.detailLevel
        )
    }

    private func applyReenablePolicy() {
        let behavior = RelayPreferences.load(from: defaults).reenableBehavior
        guard behavior == .skipMissed else {
            appendRelayLog("re-enabled; resuming from the saved high-water mark")
            return
        }
        let chatPath = RelayPaths.chatDatabase(home: home).path
        guard let store = try? SQLiteMessageStore(path: chatPath),
              let maxID = try? store.maximumRowID()
        else {
            appendRelayLog("re-enabled; could not read the database, so the saved high-water mark was left unchanged")
            return
        }
        let saved = try? stateStore.load()
        guard let next = rowIDAfterReenable(behavior: .skipMissed, saved: saved ?? nil, currentMax: maxID) else {
            return
        }
        do {
            try stateStore.save(next)
            appendRelayLog("re-enabled; high-water set to \(next)")
        } catch {
            appendRelayLog("re-enabled; could not save the high-water mark")
        }
    }

    private func noteForwarded() {
        let now = Date()
        defaults.set(now.timeIntervalSince1970, forKey: RelayPreferences.Key.lastForwardedAt)
        DispatchQueue.main.async {
            self.lastForwarded = now
        }
    }

    private func publish(_ kind: RelayStatusKind) {
        DispatchQueue.main.async {
            self.statusKind = kind
        }
    }

    private func wait(_ seconds: Double) {
        if stopFlag.isSet { return }
        let capped = min(max(seconds, 0.2), 86_400)
        let nanoseconds = Int(capped * 1_000_000_000)
        _ = wake.wait(timeout: .now() + .nanoseconds(nanoseconds))
    }

    private func persist() {
        RelayPreferences(
            enabled: enabled,
            detailLevel: detailLevel,
            skipOneTimeCodes: skipOneTimeCodes,
            pollSeconds: pollSeconds,
            showInDock: showInDock,
            launchAtLogin: launchAtLogin,
            reenableBehavior: reenableBehavior
        ).write(to: defaults)
    }

    private func prepareDirectories() {
        let fileManager = FileManager.default
        let stateDir = RelayPaths.stateDirectory(home: home)
        let logDir = RelayPaths.logDirectory(home: home)
        try? fileManager.createDirectory(at: stateDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: logDir, withIntermediateDirectories: true)
        try? fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: stateDir.path)
        try? fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: logDir.path)
    }

    private func applyDockPolicy(_ show: Bool) {
        NSApp.setActivationPolicy(show ? .regular : .accessory)
        if show {
            NSApp.activate()
        }
    }

    private func applyLoginItem(_ on: Bool, userInitiated: Bool) {
        do {
            if on {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
                DispatchQueue.main.async { self.loginItemNote = "" }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                DispatchQueue.main.async { self.loginItemNote = "" }
            }
        } catch {
            let note = "Launch at login could not be changed. Install iMessage Relay.app in your Applications folder and try again."
            appendRelayLog("launch at login update failed")
            DispatchQueue.main.async { self.loginItemNote = note }
            if !userInitiated {
                return
            }
        }
    }
}

private final class StopFlag {
    private let lock = NSLock()
    private var value = false
    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
    func clear() {
        lock.lock()
        value = false
        lock.unlock()
    }
    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class MarkingPoster: WebhookPosting {
    private let inner = URLSessionWebhookClient()
    private let onSuccess: () -> Void

    init(onSuccess: @escaping () -> Void) {
        self.onSuccess = onSuccess
    }

    func post(body: Data, url: URL, authorization: String?) throws -> Int {
        let status = try inner.post(body: body, url: url, authorization: authorization)
        onSuccess()
        return status
    }
}

func appendRelayLog(_ message: String) {
    if message.localizedCaseInsensitiveContains("bearer ") { return }
    let home = FileManager.default.homeDirectoryForCurrentUser
    let url = RelayPaths.logFile(home: home)
    let directory = url.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let line = formatISO8601(Date(), timeZone: .current) + " " + message + "\n"
    if !FileManager.default.fileExists(atPath: url.path) {
        FileManager.default.createFile(
            atPath: url.path,
            contents: Data(line.utf8),
            attributes: [.posixPermissions: NSNumber(value: 0o600)]
        )
    } else if let handle = try? FileHandle(forWritingTo: url) {
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }
    fputs(line, stderr)
    fflush(stderr)
}
#endif
