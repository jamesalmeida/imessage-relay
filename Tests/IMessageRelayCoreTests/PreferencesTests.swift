import XCTest
@testable import IMessageRelayCore

final class PreferencesTests: XCTestCase {
    func testDefaultsArePingSkipAndSkipMissed() {
        let defaults = RelayPreferences.defaults
        XCTAssertTrue(defaults.enabled)
        XCTAssertEqual(defaults.detailLevel, .ping)
        XCTAssertTrue(defaults.skipOneTimeCodes)
        XCTAssertEqual(defaults.pollSeconds, 3)
        XCTAssertFalse(defaults.showInDock)
        XCTAssertTrue(defaults.launchAtLogin)
        XCTAssertEqual(defaults.reenableBehavior, .skipMissed)
    }

    func testUserDefaultsRoundTrip() {
        let suite = "imessage-relay-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("could not open defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suite)
        XCTAssertEqual(RelayPreferences.load(from: defaults), .defaults)
        var edited = RelayPreferences.defaults
        edited.enabled = false
        edited.detailLevel = .full
        edited.skipOneTimeCodes = false
        edited.pollSeconds = 9
        edited.showInDock = true
        edited.launchAtLogin = false
        edited.reenableBehavior = .catchUp
        edited.write(to: defaults)
        XCTAssertEqual(RelayPreferences.load(from: defaults), edited)
        defaults.removePersistentDomain(forName: suite)
    }

    func testReenableSkipMissedAdvancesAndNeverMovesBackward() {
        XCTAssertEqual(rowIDAfterReenable(behavior: .skipMissed, saved: 50, currentMax: 80), 80)
        XCTAssertEqual(rowIDAfterReenable(behavior: .skipMissed, saved: nil, currentMax: 80), 80)
        XCTAssertEqual(rowIDAfterReenable(behavior: .skipMissed, saved: 90, currentMax: 80), 90)
        XCTAssertNil(rowIDAfterReenable(behavior: .catchUp, saved: 50, currentMax: 80))
        XCTAssertNil(rowIDAfterReenable(behavior: .catchUp, saved: nil, currentMax: 80))
    }
}
