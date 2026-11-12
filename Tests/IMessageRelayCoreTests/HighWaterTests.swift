import XCTest
@testable import IMessageRelayCore

final class HighWaterTests: XCTestCase {
    func testAtomicRoundTripAndPermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("state.json")
        let store = FileHighWaterStore(url: url)
        XCTAssertNil(try store.load())
        try store.save(42)
        XCTAssertEqual(try store.load(), 42)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual((mode?.intValue ?? 0) & 0o777, 0o600)
        let leftovers = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(leftovers.map(\.lastPathComponent), ["state.json"])
    }

    func testCorruptStateIsNotReset() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("state-\(UUID().uuidString).json")
        try Data("{".utf8).write(to: url)
        let store = FileHighWaterStore(url: url)
        XCTAssertThrowsError(try store.load()) { error in
            guard case HighWaterError.corrupt = error else {
                return XCTFail("unexpected \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: url), Data("{".utf8))
    }
}
