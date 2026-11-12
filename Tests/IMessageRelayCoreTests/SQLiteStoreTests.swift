import XCTest
@testable import IMessageRelayCore
#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite)
import CSQLite
#endif

#if canImport(SQLite3) || canImport(CSQLite)
final class SQLiteStoreTests: XCTestCase {
    func testReadOnlyStoreFiltersSortsAndDecodes() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-\(UUID().uuidString).db").path
        try createFixture(at: path)
        let store = try SQLiteMessageStore(path: path)
        XCTAssertEqual(try store.maximumRowID(), 6)
        let rows = try store.incomingMessages(after: 0, limit: 20)
        XCTAssertEqual(rows.map(\.rowID), [2, 3, 4, 5, 6])
        XCTAssertEqual(rows[0].service, "iMessage")
        XCTAssertEqual(rows[0].attachmentNames, ["IMG.heic"])
        XCTAssertFalse(rows[0].attachmentNames.joined().contains("secret"))
        XCTAssertEqual(rows[1].plainText, nil)
        XCTAssertEqual(AttributedBodyDecoder.decode(rows[1].attributedBody ?? Data()), "Hello")
        XCTAssertEqual(rows[1].chat?.isGroup, true)
        XCTAssertEqual(rows[1].chat?.participantHandles, ["+14155550100", "+14155550199"])
        XCTAssertEqual(rows[1].chat?.name, "Family")
        XCTAssertEqual(rows[2].service, "SMS")
        XCTAssertFalse(rows[3].otpFlagged)
        XCTAssertTrue(rows[4].otpFlagged)
        XCTAssertEqual(rows[3].plainText, "see you at 7:30")
        let code = store.debugExecResultCode(
            "INSERT INTO message (ROWID, guid, text, is_from_me) VALUES (999, 'x', 'nope', 0)"
        )
        XCTAssertNotEqual(code, SQLITE_OK)
        XCTAssertEqual(try store.maximumRowID(), 6)
        XCTAssertFalse(try store.incomingMessages(after: 0, limit: 20).contains { $0.rowID == 999 })
    }

    func testEngineOnFixtureSkipsOTPAndPostsBasenameOnly() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-\(UUID().uuidString).db").path
        try createFixture(at: path)
        let store = try SQLiteMessageStore(path: path)
        let poster = RecordingPoster()
        let state = MemoryState(value: 0)
        let engine = RelayEngine(
            source: store,
            contacts: EmptyNames(),
            state: state,
            poster: poster,
            config: RelayConfig(
                webhookURL: URL(string: "https://example.com/hook")!,
                authorizationHeader: nil,
                pollSeconds: 3,
                skipOneTimeCodes: true,
                detailLevel: .full
            ),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let outcome = try engine.runBatch()
        XCTAssertEqual(outcome.skippedOTPRowIDs, [6])
        XCTAssertEqual(outcome.postedRowIDs, [2, 3, 4, 5])
        let joined = poster.bodies.compactMap { String(data: $0, encoding: .utf8) }.joined(separator: "\n")
        XCTAssertTrue(joined.contains("Hello"))
        XCTAssertTrue(joined.contains("IMG.heic"))
        XCTAssertFalse(joined.contains("/tmp/secret"))
        XCTAssertFalse(joined.contains("Your Apple ID code"))
        XCTAssertFalse(joined.contains("123456"))
    }

    func testAddressBookLookup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources/ABC"), withIntermediateDirectories: true)
        let database = root.appendingPathComponent("Sources/ABC/AddressBook-v22.abcddb")
        try createAddressBook(at: database.path)
        let index = try AddressBookLoader(roots: [root]).load()
        XCTAssertEqual(index.name(for: "+1 (415) 555-0100"), "Test Person")
        XCTAssertEqual(index.name(for: "test.person@example.com"), "Test Person")
        XCTAssertNil(index.name(for: "+14155550199"))
    }

    private func createFixture(at path: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let db else {
            XCTFail("open")
            return
        }
        defer { sqlite3_close(db) }
        let schema = """
        CREATE TABLE handle (ROWID INTEGER PRIMARY KEY, id TEXT, service TEXT);
        CREATE TABLE message (
          ROWID INTEGER PRIMARY KEY,
          guid TEXT,
          text TEXT,
          attributedBody BLOB,
          date INTEGER,
          is_from_me INTEGER,
          service TEXT,
          handle_id INTEGER,
          associated_message_type INTEGER,
          is_otp INTEGER,
          is_spam INTEGER,
          schedule_type INTEGER,
          is_auto_reply INTEGER
        );
        CREATE TABLE chat (
          ROWID INTEGER PRIMARY KEY,
          guid TEXT,
          style INTEGER,
          chat_identifier TEXT,
          display_name TEXT
        );
        CREATE TABLE chat_message_join (chat_id INTEGER, message_id INTEGER);
        CREATE TABLE chat_handle_join (chat_id INTEGER, handle_id INTEGER);
        CREATE TABLE attachment (ROWID INTEGER PRIMARY KEY, transfer_name TEXT, filename TEXT);
        CREATE TABLE message_attachment_join (message_id INTEGER, attachment_id INTEGER);
        INSERT INTO handle (ROWID, id, service) VALUES (1, '+14155550100', 'iMessage');
        INSERT INTO handle (ROWID, id, service) VALUES (2, '+14155550199', 'SMS');
        INSERT INTO message (ROWID, guid, text, is_from_me, date, service, handle_id, associated_message_type, is_otp, is_spam, schedule_type)
          VALUES (1, 'out', 'outgoing secret', 1, 0, 'iMessage', 1, 0, 0, 0, 0);
        INSERT INTO message (ROWID, guid, text, is_from_me, date, service, handle_id, associated_message_type, is_otp, is_spam, schedule_type)
          VALUES (2, 'in2', 'hello there', 0, 599529600, 'iMessage', 1, 0, 0, 0, 0);
        INSERT INTO message (ROWID, guid, text, is_from_me, date, service, handle_id, associated_message_type, is_otp, is_spam, schedule_type)
          VALUES (3, 'in3', NULL, 0, 0, 'iMessage', 1, 0, 0, 0, 0);
        INSERT INTO message (ROWID, guid, text, is_from_me, date, service, handle_id, associated_message_type, is_otp, is_spam, schedule_type)
          VALUES (4, 'in4', 'sms hello', 0, 0, NULL, 2, 0, 0, 0, 0);
        INSERT INTO message (ROWID, guid, text, is_from_me, date, service, handle_id, associated_message_type, is_otp, is_spam, schedule_type, is_auto_reply)
          VALUES (5, 'in5', 'see you at 7:30', 0, 0, 'iMessage', 1, 0, 0, 1, 2, 1);
        INSERT INTO message (ROWID, guid, text, is_from_me, date, service, handle_id, associated_message_type, is_otp, is_spam, schedule_type)
          VALUES (6, 'in6', 'Your Apple ID code is 123456', 0, 0, 'iMessage', 1, 2000, 1, 0, 0);
        INSERT INTO chat (ROWID, guid, style, chat_identifier, display_name) VALUES (1, 'dm', 45, '+14155550100', NULL);
        INSERT INTO chat (ROWID, guid, style, chat_identifier, display_name) VALUES (2, 'group', 43, 'chat-group', 'Family');
        INSERT INTO chat_message_join (chat_id, message_id) VALUES (1, 2);
        INSERT INTO chat_message_join (chat_id, message_id) VALUES (2, 3);
        INSERT INTO chat_message_join (chat_id, message_id) VALUES (1, 4);
        INSERT INTO chat_message_join (chat_id, message_id) VALUES (1, 5);
        INSERT INTO chat_message_join (chat_id, message_id) VALUES (1, 6);
        INSERT INTO chat_handle_join (chat_id, handle_id) VALUES (1, 1);
        INSERT INTO chat_handle_join (chat_id, handle_id) VALUES (2, 1);
        INSERT INTO chat_handle_join (chat_id, handle_id) VALUES (2, 2);
        INSERT INTO attachment (ROWID, transfer_name, filename) VALUES (1, '', '/tmp/secret/Attachments/aa/IMG.heic');
        INSERT INTO message_attachment_join (message_id, attachment_id) VALUES (2, 1);
        """
        try exec(db, schema)
        let blob = helloArchive()
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "UPDATE message SET attributedBody = ? WHERE ROWID = 3", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = blob.withUnsafeBytes { raw in
            sqlite3_bind_blob(statement, 1, raw.baseAddress, Int32(blob.count), transient)
        }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
    }

    private func createAddressBook(at path: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let db else {
            XCTFail("open address book")
            return
        }
        defer { sqlite3_close(db) }
        try exec(db, """
        CREATE TABLE ZABCDRECORD (Z_PK INTEGER PRIMARY KEY, ZFIRSTNAME TEXT, ZLASTNAME TEXT, ZORGANIZATION TEXT);
        CREATE TABLE ZABCDPHONENUMBER (Z_PK INTEGER PRIMARY KEY, ZOWNER INTEGER, ZFULLNUMBER TEXT);
        CREATE TABLE ZABCDEMAILADDRESS (Z_PK INTEGER PRIMARY KEY, ZOWNER INTEGER, ZADDRESS TEXT);
        INSERT INTO ZABCDRECORD (Z_PK, ZFIRSTNAME, ZLASTNAME, ZORGANIZATION) VALUES (1, 'Test', 'Person', NULL);
        INSERT INTO ZABCDPHONENUMBER (Z_PK, ZOWNER, ZFULLNUMBER) VALUES (1, 1, '+1 (415) 555-0100');
        INSERT INTO ZABCDEMAILADDRESS (Z_PK, ZOWNER, ZADDRESS) VALUES (1, 1, 'Test.Person@Example.com');
        """)
    }

    private func exec(_ db: OpaquePointer, _ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &error)
        if rc != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "sqlite"
            sqlite3_free(error)
            XCTFail(message)
        }
    }

    private func helloArchive() -> Data {
        var data = Data([0x04, 0x0B])
        data.append(contentsOf: "streamtyped".utf8)
        data.append(contentsOf: [0x81, 0xE8, 0x03, 0x84, 0x01, 0x40, 0x84, 0x84, 0x84, 0x12])
        data.append(contentsOf: "NSAttributedString".utf8)
        data.append(contentsOf: [0x00, 0x84, 0x84, 0x08])
        data.append(contentsOf: "NSObject".utf8)
        data.append(contentsOf: [0x00, 0x85, 0x92, 0x84, 0x84, 0x84, 0x08])
        data.append(contentsOf: "NSString".utf8)
        data.append(contentsOf: [0x01, 0x94, 0x84, 0x01, 0x2B, 0x05])
        data.append(contentsOf: "Hello".utf8)
        data.append(contentsOf: [0x86, 0x84, 0x02, 0x69, 0x49, 0x01, 0x05, 0x92])
        return data
    }
}

private final class RecordingPoster: WebhookPosting {
    var bodies: [Data] = []
    func post(body: Data, url: URL, authorization: String?) throws -> Int {
        bodies.append(body)
        return 204
    }
}

private final class MemoryState: HighWaterStoring {
    var value: Int64?
    init(value: Int64?) { self.value = value }
    func load() throws -> Int64? { value }
    func save(_ rowID: Int64) throws { value = rowID }
}

private final class EmptyNames: NameResolving {
    func refreshIfNeeded(now: Date) {}
    func name(for handle: String) -> String? { nil }
}
#endif
