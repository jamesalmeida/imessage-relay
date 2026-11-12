import Foundation
import IMessageRelayCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

let cliUsage = """
imessage-relay

Debug entry point for the iMessage Relay app. Reads chat.db read-only and
prints or POSTs pending incoming messages. It never sends texts and never
writes to chat.db. The menu-bar app stores the webhook in the Keychain;
this CLI reads an optional config file.

Usage:
  imessage-relay [--config PATH] [--state-dir PATH]
      [--chat-db PATH] [--address-book-dir PATH]
      [--backfill N] [--dry-run] [--once] [--show-text]

  --config PATH         Config JSON. Defaults to \(RelayPaths.configEnvironmentVariable)
                        or ~/.config/imessage-relay/config.json.
                        The file must be mode 600 or stricter.
  --state-dir PATH      Directory for state.json.
  --chat-db PATH        Messages database. Default is ~/Library/Messages/chat.db.
  --address-book-dir    Address Book folder to read for contact names.
  --backfill N          Also forward the last N incoming messages. Applied once
                        per process. With no state file, this replaces the
                        default of starting at the current maximum ROWID.
  --dry-run             Print payloads and do not POST or update state.
                        Message text is replaced with [redacted].
  --once                Drain what is pending now, then exit.
  --show-text           With --dry-run, print message text. Never written to the log.

detail_level defaults to ping. skip_one_time_codes defaults to true.
A failed POST is retried and the high-water mark does not move past it.
"""

func shouldRunCLI(_ args: [String]) -> Bool {
    let flags: Set<String> = [
        "--once", "--dry-run", "--help", "-h", "--backfill", "--config",
        "--chat-db", "--state-dir", "--show-text", "--address-book-dir", "--cli",
    ]
    return args.dropFirst().contains { flags.contains($0) }
}

struct CLI {
    var configPath: String?
    var stateDir: String?
    var chatDB: String?
    var addressBookDir: String?
    var backfill: Int?
    var dryRun = false
    var once = false
    var showText = false
    var help = false
}

enum CLIError: Error, CustomStringConvertible {
    case message(String)
    var description: String { switch self { case .message(let text): return text } }
}

func parseCLI(_ args: [String]) throws -> CLI {
    var cli = CLI()
    var index = 1
    func value(for flag: String) throws -> String {
        index += 1
        guard index < args.count else { throw CLIError.message("\(flag) needs a value") }
        return args[index]
    }
    while index < args.count {
        let argument = args[index]
        switch argument {
        case "--help", "-h":
            cli.help = true
        case "--config":
            cli.configPath = try value(for: argument)
        case "--state-dir":
            cli.stateDir = try value(for: argument)
        case "--chat-db":
            cli.chatDB = try value(for: argument)
        case "--address-book-dir":
            cli.addressBookDir = try value(for: argument)
        case "--backfill":
            let raw = try value(for: argument)
            guard let number = Int(raw), number > 0 else {
                throw CLIError.message("--backfill expects a positive integer")
            }
            cli.backfill = number
        case "--dry-run":
            cli.dryRun = true
        case "--once":
            cli.once = true
        case "--show-text":
            cli.showText = true
        default:
            throw CLIError.message("unknown argument \(argument)")
        }
        index += 1
    }
    return cli
}

final class CancelFlag {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

func logLine(_ message: String) {
    let stamp = formatISO8601(Date(), timeZone: .current)
    fputs("\(stamp) \(message)\n", stderr)
    fflush(stderr)
}

func acquireLock(directory: String) -> Int32? {
    let path = (directory as NSString).appendingPathComponent("relay.lock")
    let fd = open(path, O_CREAT | O_RDWR, 0o600)
    if fd < 0 { return nil }
    if flock(fd, LOCK_EX | LOCK_NB) != 0 {
        close(fd)
        return nil
    }
    return fd
}

func sleepUnlessCancelled(_ seconds: Double, flag: CancelFlag) {
    let steps = max(1, Int(seconds * 10))
    for _ in 0..<steps {
        if flag.isSet { return }
        Thread.sleep(forTimeInterval: 0.1)
    }
}

func waitForPoll(seconds: Double, wake: DispatchSemaphore, flag: CancelFlag) {
    if flag.isSet { return }
    let capped = min(max(seconds, 0.05), 86_400)
    let nanoseconds = Int(capped * 1_000_000_000)
    _ = wake.wait(timeout: .now() + .nanoseconds(nanoseconds))
}

func emitDryRun(_ data: Data, showText: Bool) {
    let redacted = redactPayloadForDisplay(data, showText: showText)
    let pretty: Data
    if let object = try? JSONSerialization.jsonObject(with: redacted),
       let rendered = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
        pretty = rendered
    } else {
        pretty = redacted
    }
    FileHandle.standardOutput.write(pretty)
    FileHandle.standardOutput.write(Data("\n".utf8))
    fflush(stdout)
}

#if os(macOS)
final class WALWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var watching = ""

    func refresh(path: String, wake: DispatchSemaphore) {
        guard source == nil || watching != path else { return }
        stop()
        let opened = open(path, O_EVTONLY)
        guard opened >= 0 else { return }
        fd = opened
        watching = path
        let created = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: opened,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .global(qos: .utility)
        )
        created.setEventHandler {
            wake.signal()
        }
        created.setCancelHandler {
            close(opened)
        }
        created.resume()
        source = created
    }

    func stop() {
        source?.cancel()
        source = nil
        fd = -1
    }
}
#endif

func installSignals(flag: CancelFlag, wake: DispatchSemaphore) {
    signal(SIGPIPE, SIG_IGN)
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    let queue = DispatchQueue.global()
    for sig in [SIGINT, SIGTERM] {
        let source = DispatchSource.makeSignalSource(signal: sig, queue: queue)
        source.setEventHandler {
            flag.set()
            wake.signal()
        }
        source.resume()
        signalSources.append(source)
    }
}

private var signalSources: [DispatchSourceSignal] = []
private var heldLock: Int32 = -1

func runCLI(_ arguments: [String]) -> Int32 {
    let cli: CLI
    do {
        cli = try parseCLI(arguments)
    } catch {
        fputs("\(error)\n\n\(cliUsage)\n", stderr)
        return 2
    }
    if cli.help {
        fputs(cliUsage + "\n", stdout)
        return 0
    }
    if cli.showText && !cli.dryRun {
        logLine("show-text only changes dry-run stdout; message text is not written to the log")
    }

    let home = FileManager.default.homeDirectoryForCurrentUser
    let configPath = cli.configPath
        ?? ProcessInfo.processInfo.environment[RelayPaths.configEnvironmentVariable].flatMap { $0.isEmpty ? nil : $0 }
        ?? RelayPaths.configFile(home: home).path
    let stateDirectory = cli.stateDir ?? RelayPaths.stateDirectory(home: home).path
    let chatPath = cli.chatDB ?? RelayPaths.chatDatabase(home: home).path
    let addressRoot = URL(fileURLWithPath: cli.addressBookDir ?? RelayPaths.addressBookRoot(home: home).path)

    let config: RelayConfig
    do {
        config = try loadConfig(from: configPath)
    } catch {
        logLine(String(describing: error))
        return 1
    }

    do {
        try FileManager.default.createDirectory(atPath: stateDirectory, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: stateDirectory)
    } catch {
        logLine("could not create state directory")
        return 1
    }
    if let fd = acquireLock(directory: stateDirectory) {
        heldLock = fd
    } else {
        logLine("another imessage-relay is already running")
        return 1
    }

    let store: SQLiteMessageStore
    do {
        store = try SQLiteMessageStore(path: chatPath)
    } catch {
        logLine(String(describing: error))
        logLine("Grant Full Disk Access to iMessage Relay.app: System Settings > Privacy & Security > Full Disk Access.")
        logLine("After a rebuild, enable the checkbox again. Ad-hoc signatures change the cdhash, so macOS may drop the previous grant.")
        return 1
    }

    let contacts = ContactBook(loader: {
        try AddressBookLoader(roots: [addressRoot]).load()
    }, logger: logLine)
    let engine = RelayEngine(
        source: store,
        contacts: contacts,
        state: FileHighWaterStore(url: URL(fileURLWithPath: stateDirectory).appendingPathComponent("state.json")),
        poster: URLSessionWebhookClient(),
        config: config,
        options: RunOptions(backfill: cli.backfill, dryRun: cli.dryRun),
        timeZone: .current,
        logger: logLine
    )

    let flag = CancelFlag()
    let wake = DispatchSemaphore(value: 0)
    installSignals(flag: flag, wake: wake)
    #if os(macOS)
    let watcher = WALWatcher()
    let walPath = chatPath + "-wal"
    #endif

    logLine("starting detail_level=\(config.detailLevel.rawValue) skip_one_time_codes=\(config.skipOneTimeCodes) poll_seconds=\(config.pollSeconds)")
    var attempt = 1
    while !flag.isSet {
        #if os(macOS)
        watcher.refresh(path: walPath, wake: wake)
        #endif
        do {
            let outcome = try engine.runBatch()
            if cli.dryRun {
                for payload in outcome.payloads {
                    emitDryRun(payload, showText: cli.showText)
                }
            }
            if let failed = outcome.failedRowID {
                let summary = outcome.failureSummary ?? "error=failed"
                if summary == "error=state" {
                    logLine("state save failed rowid=\(failed) attempt=\(attempt) error=state")
                } else {
                    logLine("webhook failed rowid=\(failed) attempt=\(attempt) \(summary)")
                }
                sleepUnlessCancelled(retryDelaySeconds(attempt: attempt), flag: flag)
                attempt += 1
                continue
            }
            attempt = 1
            if cli.dryRun || cli.once || flag.isSet {
                break
            }
            waitForPoll(seconds: config.pollSeconds, wake: wake, flag: flag)
        } catch let error as HighWaterError {
            logLine(error.description)
            return 1
        } catch let error as StoreError {
            logLine("database read failed: \(error.description)")
            sleepUnlessCancelled(retryDelaySeconds(attempt: attempt), flag: flag)
            attempt += 1
        } catch {
            logLine("read failed; will retry")
            sleepUnlessCancelled(retryDelaySeconds(attempt: attempt), flag: flag)
            attempt += 1
        }
    }
    if flag.isSet {
        logLine("stopping")
    }
    return 0
}

#if !os(macOS)
@main
enum LinuxEntry {
    static func main() {
        exit(runCLI(CommandLine.arguments))
    }
}
#endif
