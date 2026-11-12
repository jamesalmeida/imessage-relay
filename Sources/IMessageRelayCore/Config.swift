import Foundation

public enum DetailLevel: String, Equatable {
    case ping
    case sender
    case full
}

public struct RelayConfig: Equatable {
    public var webhookURL: URL
    public var authorizationHeader: String?
    public var pollSeconds: Double
    public var skipOneTimeCodes: Bool
    public var detailLevel: DetailLevel

    public init(
        webhookURL: URL,
        authorizationHeader: String?,
        pollSeconds: Double,
        skipOneTimeCodes: Bool,
        detailLevel: DetailLevel
    ) {
        self.webhookURL = webhookURL
        self.authorizationHeader = authorizationHeader
        self.pollSeconds = pollSeconds
        self.skipOneTimeCodes = skipOneTimeCodes
        self.detailLevel = detailLevel
    }
}

public enum ConfigError: Error, Equatable, CustomStringConvertible {
    case missing(String)
    case insecurePermissions(path: String, mode: Int)
    case invalid(String)

    public var description: String {
        switch self {
        case .missing(let path):
            return "config file not found at \(path). Copy config.example.json to that path and chmod 600."
        case .insecurePermissions(let path, let mode):
            return "refusing to start: \(path) is mode \(String(format: "%03o", mode)); chmod 600 so group and other have no access"
        case .invalid(let message):
            return message
        }
    }
}

private struct FileConfig: Decodable {
    var webhook_url: String
    var auth_header: String?
    var poll_seconds: Double?
    var skip_one_time_codes: Bool?
    var detail_level: String?
}

public func normalizeAuthorizationHeader(_ raw: String?) -> String? {
    guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return nil
    }
    let prefix = "authorization:"
    if value.lowercased().hasPrefix(prefix) {
        value = String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return nil }
    }
    return value
}

public func loadConfig(from path: String) throws -> RelayConfig {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
        throw ConfigError.missing(path)
    }
    let attributes = try fileManager.attributesOfItem(atPath: path)
    let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
    let bits = mode & 0o777
    if bits & ~0o600 != 0 {
        throw ConfigError.insecurePermissions(path: path, mode: bits)
    }
    let data: Data
    do {
        data = try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
        throw ConfigError.invalid("could not read the config file")
    }
    let decoded: FileConfig
    do {
        decoded = try JSONDecoder().decode(FileConfig.self, from: data)
    } catch {
        throw ConfigError.invalid(
            "config.json must be JSON with webhook_url and optional auth_header, poll_seconds, skip_one_time_codes, and detail_level"
        )
    }
    return try makeConfig(decoded)
}

private func makeConfig(_ file: FileConfig) throws -> RelayConfig {
    let trimmed = file.webhook_url.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed),
          let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https",
          url.host != nil
    else {
        throw ConfigError.invalid("webhook_url must be an http or https URL")
    }
    let poll = file.poll_seconds ?? 3
    guard poll.isFinite, poll > 0, poll <= 86_400 else {
        throw ConfigError.invalid("poll_seconds must be a number greater than 0 and at most 86400")
    }
    let level: DetailLevel
    if let raw = file.detail_level {
        let trimmedLevel = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = DetailLevel(rawValue: trimmedLevel.lowercased()) else {
            throw ConfigError.invalid("invalid detail_level (expected ping, sender, or full)")
        }
        level = parsed
    } else {
        level = .ping
    }
    return RelayConfig(
        webhookURL: url,
        authorizationHeader: normalizeAuthorizationHeader(file.auth_header),
        pollSeconds: poll,
        skipOneTimeCodes: file.skip_one_time_codes ?? true,
        detailLevel: level
    )
}
