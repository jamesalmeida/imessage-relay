import Foundation

public enum ReenableBehavior: String, Equatable, Codable {
    case catchUp
    case skipMissed
}

/// Where to put the high-water mark when Enabled is turned back on.
/// `nil` means leave the saved mark untouched.
/// Skip missed never moves the mark backward.
public func rowIDAfterReenable(behavior: ReenableBehavior, saved: Int64?, currentMax: Int64) -> Int64? {
    switch behavior {
    case .catchUp:
        return nil
    case .skipMissed:
        return max(saved ?? currentMax, currentMax)
    }
}

public struct RelayPreferences: Equatable {
    public var enabled: Bool
    public var detailLevel: DetailLevel
    public var skipOneTimeCodes: Bool
    public var pollSeconds: Double
    public var showInDock: Bool
    public var launchAtLogin: Bool
    public var reenableBehavior: ReenableBehavior

    public static let defaults = RelayPreferences(
        enabled: true,
        detailLevel: .ping,
        skipOneTimeCodes: true,
        pollSeconds: 3,
        showInDock: true,
        launchAtLogin: true,
        reenableBehavior: .skipMissed
    )

    public enum Key {
        public static let enabled = "enabled"
        public static let detailLevel = "detailLevel"
        public static let skipOneTimeCodes = "skipOneTimeCodes"
        public static let pollSeconds = "pollSeconds"
        public static let showInDock = "showInDock"
        public static let launchAtLogin = "launchAtLogin"
        public static let reenableBehavior = "reenableBehavior"
        public static let lastForwardedAt = "lastForwardedAt"
    }

    public init(
        enabled: Bool,
        detailLevel: DetailLevel,
        skipOneTimeCodes: Bool,
        pollSeconds: Double,
        showInDock: Bool,
        launchAtLogin: Bool,
        reenableBehavior: ReenableBehavior
    ) {
        self.enabled = enabled
        self.detailLevel = detailLevel
        self.skipOneTimeCodes = skipOneTimeCodes
        self.pollSeconds = pollSeconds
        self.showInDock = showInDock
        self.launchAtLogin = launchAtLogin
        self.reenableBehavior = reenableBehavior
    }

    public static var registration: [String: Any] {
        [
            Key.enabled: defaults.enabled,
            Key.detailLevel: defaults.detailLevel.rawValue,
            Key.skipOneTimeCodes: defaults.skipOneTimeCodes,
            Key.pollSeconds: defaults.pollSeconds,
            Key.showInDock: defaults.showInDock,
            Key.launchAtLogin: defaults.launchAtLogin,
            Key.reenableBehavior: defaults.reenableBehavior.rawValue,
        ]
    }

    public static func load(from defaults: UserDefaults) -> RelayPreferences {
        let base = RelayPreferences.defaults
        let detailRaw = defaults.string(forKey: Key.detailLevel) ?? base.detailLevel.rawValue
        let behaviorRaw = defaults.string(forKey: Key.reenableBehavior) ?? base.reenableBehavior.rawValue
        let poll = double(defaults, Key.pollSeconds) ?? base.pollSeconds
        return RelayPreferences(
            enabled: bool(defaults, Key.enabled, fallback: base.enabled),
            detailLevel: DetailLevel(rawValue: detailRaw) ?? base.detailLevel,
            skipOneTimeCodes: bool(defaults, Key.skipOneTimeCodes, fallback: base.skipOneTimeCodes),
            pollSeconds: poll > 0 && poll <= 86_400 ? poll : base.pollSeconds,
            showInDock: bool(defaults, Key.showInDock, fallback: base.showInDock),
            launchAtLogin: bool(defaults, Key.launchAtLogin, fallback: base.launchAtLogin),
            reenableBehavior: ReenableBehavior(rawValue: behaviorRaw) ?? base.reenableBehavior
        )
    }

    private static func bool(_ defaults: UserDefaults, _ key: String, fallback: Bool) -> Bool {
        guard let object = defaults.object(forKey: key) else { return fallback }
        if let value = object as? Bool { return value }
        if let number = object as? NSNumber { return number.boolValue }
        return fallback
    }

    private static func double(_ defaults: UserDefaults, _ key: String) -> Double? {
        guard let object = defaults.object(forKey: key) else { return nil }
        if let value = object as? Double { return value }
        if let number = object as? NSNumber { return number.doubleValue }
        return nil
    }

    public func write(to defaults: UserDefaults) {
        defaults.set(enabled, forKey: Key.enabled)
        defaults.set(detailLevel.rawValue, forKey: Key.detailLevel)
        defaults.set(skipOneTimeCodes, forKey: Key.skipOneTimeCodes)
        defaults.set(pollSeconds, forKey: Key.pollSeconds)
        defaults.set(showInDock, forKey: Key.showInDock)
        defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
        defaults.set(reenableBehavior.rawValue, forKey: Key.reenableBehavior)
    }
}
