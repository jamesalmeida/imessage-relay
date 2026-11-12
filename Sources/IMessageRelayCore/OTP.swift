import Foundation

public enum OTPDetector {
    /// Column names that are real one-time-code indicators if a future or
    /// current `message` table has them. Spam, schedule, and auto-reply flags
    /// are not OTP and are ignored.
    public static func isIndicatorColumn(_ name: String) -> Bool {
        let lowered = name.lowercased()
        let denied: Set<String> = [
            "is_auto_reply",
            "expressive_send_style_id",
            "is_spam",
            "schedule_type",
            "schedule_state",
            "is_system_message",
            "is_service_message",
        ]
        if denied.contains(lowered) { return false }
        if lowered.contains("not_otp") || lowered.contains("no_otp") || lowered.contains("non_otp") {
            return false
        }
        if lowered.contains("otp") { return true }
        if lowered.contains("one_time") || lowered.contains("onetime") { return true }
        if lowered.contains("verification_code") || lowered.contains("verify_code") { return true }
        if lowered.contains("2fa") || lowered.contains("two_factor") { return true }
        if lowered.contains("passcode") { return true }
        return false
    }

    public static func isOneTimeCode(_ text: String) -> Bool {
        let normalized = normalizeApostrophes(text)
        let keywords = ranges(of: keywordPattern, in: normalized)
        if keywords.isEmpty { return false }
        var masked = normalized
        for pattern in maskPatterns {
            masked = mask(masked, pattern: pattern)
        }
        let codes = ranges(of: codePattern, in: masked)
        for code in codes {
            for keyword in keywords where nearby(code, keyword, window: 80) {
                return true
            }
        }
        return false
    }
}

public func shouldSkipOneTimeCode(text: String?, otpFlagged: Bool, enabled: Bool) -> Bool {
    guard enabled else { return false }
    if otpFlagged { return true }
    guard let text, !text.isEmpty else { return false }
    return OTPDetector.isOneTimeCode(text)
}

private let keywordPattern = compile(
    #"\b(?:code|verification|verify|passcode|otp|login|authentication|confirm|2fa)\b|one-time|one time|security code|sign-in|sign in|do not share|don't share|is your"#
)

private let codePattern = compile(#"\b(?:[A-Za-z]-\d{4,8}|\d{4,8})\b"#)

private let maskPatterns: [NSRegularExpression] = [
    compile(
        #"(?:\+\d{1,3}[\s.\-]?)?(?:\(\d{3}\)|\d{3})[\s.\-]?\d{3}[\s.\-]?\d{4}\b|\b\d{3}[\s.\-]\d{4}\b"#
    ),
    compile(#"\b\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AaPp]\.?[Mm]\.?)?\b"#),
    compile(#"\$\s*\d{1,3}(?:,\d{3})+(?:\.\d{2})?|\$\s*\d+(?:\.\d{2})?"#),
    compile(
        #"\b\d{1,6}\s+(?:[A-Za-z][A-Za-z0-9.'\-]*\s+){1,4}(?:street|st|avenue|ave|road|rd|boulevard|blvd|drive|dr|lane|ln|way|court|ct|place|pl|terrace|ter|circle|cir|trail|trl|parkway|pkwy)\b\.?"#
    ),
    compile(#"\b\d{4}-\d{2}-\d{2}\b|\b\d{1,2}/\d{1,2}/\d{2,4}\b"#),
]

private func compile(_ pattern: String) -> NSRegularExpression {
    do {
        return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    } catch {
        fatalError("invalid OTP pattern")
    }
}

private func normalizeApostrophes(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{2019}", with: "'")
        .replacingOccurrences(of: "\u{2018}", with: "'")
        .replacingOccurrences(of: "\u{02BC}", with: "'")
}

private func ranges(of pattern: NSRegularExpression, in text: String) -> [NSRange] {
    let ns = text as NSString
    let full = NSRange(location: 0, length: ns.length)
    return pattern.matches(in: text, options: [], range: full).map(\.range)
}

private func mask(_ text: String, pattern: NSRegularExpression) -> String {
    let ns = text as NSString
    let full = NSRange(location: 0, length: ns.length)
    let matches = pattern.matches(in: text, options: [], range: full)
    if matches.isEmpty { return text }
    let mutable = NSMutableString(string: text)
    for match in matches.reversed() {
        mutable.replaceCharacters(in: match.range, with: String(repeating: " ", count: match.range.length))
    }
    return mutable as String
}

private func nearby(_ lhs: NSRange, _ rhs: NSRange, window: Int) -> Bool {
    let leftEnd = lhs.location + lhs.length
    let rightEnd = rhs.location + rhs.length
    if leftEnd < rhs.location {
        return rhs.location - leftEnd <= window
    }
    if rightEnd < lhs.location {
        return lhs.location - rightEnd <= window
    }
    return true
}
