import XCTest
@testable import IMessageRelayCore

final class ConfigTests: XCTestCase {
    func testAuthorizationHeaderParsing() {
        XCTAssertNil(normalizeAuthorizationHeader(nil))
        XCTAssertNil(normalizeAuthorizationHeader("   "))
        XCTAssertEqual(normalizeAuthorizationHeader("Bearer abc"), "Bearer abc")
        XCTAssertEqual(normalizeAuthorizationHeader("  Bearer abc  "), "Bearer abc")
        XCTAssertEqual(normalizeAuthorizationHeader("Authorization: Bearer abc"), "Bearer abc")
        XCTAssertEqual(normalizeAuthorizationHeader("authorization: Bearer abc"), "Bearer abc")
        XCTAssertEqual(normalizeAuthorizationHeader("Authorization:Bearer abc"), "Bearer abc")
        XCTAssertEqual(normalizeAuthorizationHeader("AUTHORIZATION: bearer abc"), "bearer abc")
    }

    func testLoosePermissionsAreRejectedWithoutLeakingSecrets() throws {
        let url = try writeConfig(
            """
            {"webhook_url":"https://example.com/hook?token=super-secret-query","auth_header":"Bearer super-secret-header","detail_level":"ping"}
            """,
            mode: 0o644
        )
        XCTAssertThrowsError(try loadConfig(from: url.path)) { error in
            let text = String(describing: error)
            XCTAssertTrue(text.contains("chmod 600"))
            XCTAssertFalse(text.contains("super-secret-query"))
            XCTAssertFalse(text.contains("super-secret-header"))
        }
    }

    func testMode600AndStricterAreAcceptedAndDefaultsArePing() throws {
        let body = """
        {"webhook_url":"https://example.com/hooks/messages","auth_header":"Bearer replace-me"}
        """
        let secure = try writeConfig(body, mode: 0o600)
        let config = try loadConfig(from: secure.path)
        XCTAssertEqual(config.detailLevel, .ping)
        XCTAssertTrue(config.skipOneTimeCodes)
        XCTAssertEqual(config.pollSeconds, 3)
        XCTAssertEqual(config.authorizationHeader, "Bearer replace-me")

        let stricter = try writeConfig(body, mode: 0o400)
        XCTAssertEqual(try loadConfig(from: stricter.path).detailLevel, .ping)
    }

    func testExecutableBitAndGroupReadAreRejected() throws {
        let body = #"{"webhook_url":"https://example.com/hook"}"#
        for mode in [0o700, 0o640, 0o666] {
            let url = try writeConfig(body, mode: mode)
            XCTAssertThrowsError(try loadConfig(from: url.path))
        }
    }

    func testInvalidDetailLevelRefusesWithoutEchoingHeader() throws {
        let url = try writeConfig(
            """
            {"webhook_url":"https://example.com/hook?token=super-secret-query","auth_header":"Bearer super-secret-header","detail_level":"verbose"}
            """,
            mode: 0o600
        )
        XCTAssertThrowsError(try loadConfig(from: url.path)) { error in
            let text = String(describing: error)
            XCTAssertTrue(text.contains("detail_level"))
            XCTAssertFalse(text.contains("super-secret-query"))
            XCTAssertFalse(text.contains("super-secret-header"))
            XCTAssertFalse(text.contains("verbose"))
        }
    }

    func testExplicitValues() throws {
        let url = try writeConfig(
            """
            {"webhook_url":"https://example.com/hook","auth_header":"Authorization: Bearer xyz","poll_seconds":5,"skip_one_time_codes":false,"detail_level":"FULL"}
            """,
            mode: 0o600
        )
        let config = try loadConfig(from: url.path)
        XCTAssertEqual(config.detailLevel, .full)
        XCTAssertFalse(config.skipOneTimeCodes)
        XCTAssertEqual(config.pollSeconds, 5)
        XCTAssertEqual(config.authorizationHeader, "Bearer xyz")
    }

    func testExampleFileDefaults() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let example = try Data(contentsOf: root.appendingPathComponent("config.example.json"))
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("example-\(UUID().uuidString).json")
        try example.write(to: copy)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: copy.path)
        let config = try loadConfig(from: copy.path)
        XCTAssertEqual(config.detailLevel, .ping)
        XCTAssertTrue(config.skipOneTimeCodes)
        XCTAssertEqual(config.pollSeconds, 3)
        XCTAssertEqual(config.webhookURL.host, "example.com")
    }

    func testMissingFileAndBadPoll() throws {
        XCTAssertThrowsError(try loadConfig(from: "/tmp/does-not-exist-\(UUID().uuidString).json"))
        let zero = try writeConfig(#"{"webhook_url":"https://example.com/hook","poll_seconds":0}"#, mode: 0o600)
        XCTAssertThrowsError(try loadConfig(from: zero.path))
        let fileURL = try writeConfig(#"{"webhook_url":"file:///tmp/hook"}"#, mode: 0o600)
        XCTAssertThrowsError(try loadConfig(from: fileURL.path))
    }

    func testReadOnlyURI() {
        let uri = sqliteReadOnlyURI(path: "/tmp/my db/chat.db")
        XCTAssertTrue(uri.contains("mode=ro"))
        XCTAssertTrue(uri.contains("my%20db") || uri.contains("%20"))
        XCTAssertFalse(uri.contains("mode=rw"))
        XCTAssertFalse(uri.contains("mode=rwc"))
    }

    private func writeConfig(_ body: String, mode: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-config-\(UUID().uuidString).json")
        try Data(body.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: mode)], ofItemAtPath: url.path)
        return url
    }
}
