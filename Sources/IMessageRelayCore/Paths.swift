import Foundation

public enum RelayPaths {
    public static let configEnvironmentVariable = "IMESSAGE_RELAY_CONFIG"
    public static let bundleIdentifier = "com.jamesalmeida.imessage-relay"
    public static let keychainService = "com.jamesalmeida.imessage-relay"
    public static let productName = "imessage-relay"
    public static let appDisplayName = "iMessage Relay"

    /// Optional CLI / one-time import file. The app stores the webhook in the Keychain.
    public static func configFile(home: URL) -> URL {
        home.appendingPathComponent(".config/imessage-relay/config.json")
    }

    public static func stateDirectory(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/imessage-relay")
    }

    public static func stateFile(home: URL) -> URL {
        stateDirectory(home: home).appendingPathComponent("state.json")
    }

    public static func logDirectory(home: URL) -> URL {
        home.appendingPathComponent("Library/Logs/imessage-relay")
    }

    public static func logFile(home: URL) -> URL {
        logDirectory(home: home).appendingPathComponent("relay.log")
    }

    public static func chatDatabase(home: URL) -> URL {
        home.appendingPathComponent("Library/Messages/chat.db")
    }

    public static func addressBookRoot(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/AddressBook")
    }

    public static func appBundle(home: URL) -> URL {
        home.appendingPathComponent("Applications/iMessage Relay.app")
    }

    public static func installedExecutable(home: URL) -> URL {
        appBundle(home: home).appendingPathComponent("Contents/MacOS/imessage-relay")
    }
}

public func addressBookDatabaseURLs(root: URL) -> [URL] {
    let fileManager = FileManager.default
    var urls: [URL] = []
    let top = root.appendingPathComponent("AddressBook-v22.abcddb")
    if fileManager.fileExists(atPath: top.path) {
        urls.append(top)
    }
    let sources = root.appendingPathComponent("Sources")
    guard let children = try? fileManager.contentsOfDirectory(
        at: sources,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    ) else {
        return urls
    }
    for child in children.sorted(by: { $0.path < $1.path }) {
        let database = child.appendingPathComponent("AddressBook-v22.abcddb")
        if fileManager.fileExists(atPath: database.path) {
            urls.append(database)
        }
    }
    return urls
}

public func sqliteReadOnlyURI(path: String) -> String {
    var components = URLComponents()
    components.scheme = "file"
    components.path = path.hasPrefix("/") ? path : "/" + path
    components.queryItems = [URLQueryItem(name: "mode", value: "ro")]
    if let rendered = components.string, rendered.contains("mode=ro") {
        return rendered
    }
    let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
    return "file://\(encoded)?mode=ro"
}
