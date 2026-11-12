import XCTest
@testable import IMessageRelayCore

final class SafetyTests: XCTestCase {
    func testFetchSQLIsIncomingOnlyAndIgnoresSpamFlags() {
        let columns: Set<String> = [
            "text", "attributedBody", "service", "associated_message_type",
            "is_otp", "is_spam", "schedule_type", "is_auto_reply", "expressive_send_style_id",
        ]
        let sql = MessageSQL.fetchIncoming(columns: columns)
        XCTAssertTrue(sql.contains("m.is_from_me = 0"))
        XCTAssertTrue(sql.contains("m.ROWID > ?"))
        XCTAssertTrue(sql.contains("ORDER BY m.ROWID ASC"))
        XCTAssertTrue(sql.contains("m.is_otp"))
        XCTAssertFalse(sql.contains("is_spam"))
        XCTAssertFalse(sql.contains("schedule_type"))
        XCTAssertFalse(sql.contains("is_auto_reply"))
        XCTAssertFalse(sql.contains("expressive_send_style_id"))
        let upper = sql.uppercased()
        XCTAssertFalse(upper.contains("INSERT"))
        XCTAssertFalse(upper.contains("UPDATE"))
        XCTAssertFalse(upper.contains("DELETE"))
    }

    func testProductionSourcesDoNotWriteDatabases() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let files = try swiftFiles(under: root)
        XCTAssertFalse(files.isEmpty)
        let forbidden = [
            "SQLITE_OPEN_READWRITE",
            "SQLITE_OPEN_CREATE",
            "sqlite3_open(",
            "INSERT ",
            "UPDATE ",
            "DELETE ",
            "DROP ",
            "ALTER ",
            "mode=rw",
        ]
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in forbidden {
                XCTAssertFalse(text.contains(token), "\(file.lastPathComponent) contains \(token)")
            }
        }
    }

    func testAddressBookDiscovery() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let top = root.appendingPathComponent("AddressBook-v22.abcddb")
        try Data().write(to: top)
        let source = root.appendingPathComponent("Sources/ABC")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data().write(to: source.appendingPathComponent("AddressBook-v22.abcddb"))
        try Data().write(to: root.appendingPathComponent("AddressBook-v23.abcddb"))
        let found = addressBookDatabaseURLs(root: root).map(\.lastPathComponent)
        XCTAssertEqual(found.filter { $0 == "AddressBook-v22.abcddb" }.count, 2)
        XCTAssertFalse(found.contains("AddressBook-v23.abcddb"))
    }

    private func swiftFiles(under url: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else {
            return []
        }
        var files: [URL] = []
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            files.append(file)
        }
        return files
    }
}
