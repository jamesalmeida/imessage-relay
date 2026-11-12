import Foundation

public func phoneDigits(_ raw: String) -> String {
    var digits = String.UnicodeScalarView()
    for scalar in raw.unicodeScalars where CharacterSet.decimalDigits.contains(scalar) {
        digits.append(scalar)
    }
    return String(digits)
}

public func normalizeEmail(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

public func handlesReferToSamePhone(_ lhs: String, _ rhs: String) -> Bool {
    let left = phoneDigits(lhs)
    let right = phoneDigits(rhs)
    guard !left.isEmpty, !right.isEmpty else { return false }
    if left == right { return true }
    if left.count >= 10 && right.count >= 10 {
        return left.suffix(10) == right.suffix(10)
    }
    return false
}

public struct ContactIndex: Equatable {
    private var byExactDigits: [String: String] = [:]
    private var byLast10: [String: String] = [:]
    private var byEmail: [String: String] = [:]

    public init() {}

    public mutating func add(name: String, phone: String? = nil, email: String? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let phone {
            let digits = phoneDigits(phone)
            if !digits.isEmpty {
                if byExactDigits[digits] == nil {
                    byExactDigits[digits] = trimmed
                }
                if digits.count >= 10 {
                    let key = String(digits.suffix(10))
                    if byLast10[key] == nil {
                        byLast10[key] = trimmed
                    }
                }
            }
        }
        if let email {
            let key = normalizeEmail(email)
            if key.contains("@"), byEmail[key] == nil {
                byEmail[key] = trimmed
            }
        }
    }

    public func name(for handle: String) -> String? {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("@") {
            return byEmail[normalizeEmail(trimmed)]
        }
        let digits = phoneDigits(trimmed)
        if digits.isEmpty { return nil }
        if digits.count >= 10, let name = byLast10[String(digits.suffix(10))] {
            return name
        }
        return byExactDigits[digits]
    }
}

public func maskHandle(_ handle: String) -> String {
    let digits = phoneDigits(handle)
    if digits.count >= 4 {
        return "***" + String(digits.suffix(4))
    }
    if handle.count >= 4 {
        return "***" + String(handle.suffix(4))
    }
    return "***"
}

public func lastPathComponent(_ path: String) -> String {
    let normalized = path.replacingOccurrences(of: "\\", with: "/")
    let trimmed = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/ \t\n\r"))
    guard let slash = trimmed.lastIndex(of: "/") else { return trimmed }
    return String(trimmed[trimmed.index(after: slash)...])
}

public func attachmentDisplayName(transferName: String?, filename: String?) -> String? {
    func clean(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let base = lastPathComponent(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        if base.isEmpty || base.contains("/") { return nil }
        return base
    }
    if let name = clean(transferName) { return name }
    return clean(filename)
}

public func chatIsGroup(style: Int, participantCount: Int) -> Bool {
    style == 43 || participantCount > 1
}

public func nilIfBlank(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

public func validatedSQLIdentifier(_ name: String) -> String? {
    let pattern = #"^[A-Za-z_][A-Za-z0-9_]*$"#
    guard name.range(of: pattern, options: .regularExpression) != nil else { return nil }
    return name
}
