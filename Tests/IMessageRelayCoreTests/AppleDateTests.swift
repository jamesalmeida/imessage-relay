import XCTest
@testable import IMessageRelayCore

final class AppleDateTests: XCTestCase {
    func testEpochSecondsAre2001UTC() {
        let date = dateFromAppleTimestamp(0)
        XCTAssertEqual(
            formatISO8601(date, timeZone: TimeZone(secondsFromGMT: 0)!),
            "2001-01-01T00:00:00+00:00"
        )
    }

    func testEpochRespectsNegativeOffset() {
        let date = dateFromAppleTimestamp(0)
        XCTAssertEqual(
            formatISO8601(date, timeZone: TimeZone(secondsFromGMT: -8 * 3600)!),
            "2000-12-31T16:00:00-08:00"
        )
    }

    func testSecondsAndNanosecondsMatch() {
        let appleSeconds: Int64 = 599_529_600
        let appleNanos = appleSeconds * 1_000_000_000
        let utc = TimeZone(secondsFromGMT: 0)!
        let fromSeconds = formatISO8601(dateFromAppleTimestamp(appleSeconds), timeZone: utc)
        let fromNanos = formatISO8601(dateFromAppleTimestamp(appleNanos), timeZone: utc)
        XCTAssertEqual(fromSeconds, "2020-01-01T00:00:00+00:00")
        XCTAssertEqual(fromNanos, fromSeconds)
        XCTAssertLessThan(appleSeconds, appleNanosecondThreshold)
        XCTAssertGreaterThanOrEqual(appleNanos, appleNanosecondThreshold)
    }

    func testFractionalNanosecondsStayInTheSameSecond() {
        let raw = Int64(599_529_600) * 1_000_000_000 + 500_000_000
        let utc = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(
            formatISO8601(dateFromAppleTimestamp(raw), timeZone: utc),
            "2020-01-01T00:00:00+00:00"
        )
    }

    func testTenSecondsOfNanoseconds() {
        let utc = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(
            formatISO8601(dateFromAppleTimestamp(10_000_000_000), timeZone: utc),
            "2001-01-01T00:00:10+00:00"
        )
    }
}
