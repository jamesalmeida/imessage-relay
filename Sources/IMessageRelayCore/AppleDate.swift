import Foundation

/// Apple's Messages `date` column counts from 2001-01-01 00:00:00 UTC.
/// Modern macOS stores nanoseconds. Values below this magnitude are seconds.
public let appleNanosecondThreshold: Int64 = 10_000_000_000

public let appleEpochUnixOffset: Int64 = 978_307_200

public func dateFromAppleTimestamp(_ raw: Int64) -> Date {
    let seconds: Int64
    var nanos: Int64
    if raw >= appleNanosecondThreshold || raw <= -appleNanosecondThreshold {
        seconds = raw / 1_000_000_000
        nanos = raw % 1_000_000_000
    } else {
        seconds = raw
        nanos = 0
    }
    var unix = seconds &+ appleEpochUnixOffset
    if nanos < 0 {
        unix &-= 1
        nanos += 1_000_000_000
    }
    let fraction = Double(nanos) / 1_000_000_000
    return Date(timeIntervalSince1970: Double(unix) + fraction)
}

public func formatISO8601(_ date: Date, timeZone: TimeZone) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    let year = parts.year ?? 0
    let month = parts.month ?? 0
    let day = parts.day ?? 0
    let hour = parts.hour ?? 0
    let minute = parts.minute ?? 0
    let second = parts.second ?? 0
    let offset = timeZone.secondsFromGMT(for: date)
    let sign = offset >= 0 ? "+" : "-"
    let absolute = abs(offset)
    let offsetHours = absolute / 3600
    let offsetMinutes = (absolute % 3600) / 60
    let clock = String(
        format: "%04d-%02d-%02dT%02d:%02d:%02d",
        year, month, day, hour, minute, second
    )
    let zone = String(format: "%02d:%02d", offsetHours, offsetMinutes)
    return clock + sign + zone
}
