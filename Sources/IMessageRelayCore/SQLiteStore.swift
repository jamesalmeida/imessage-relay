import Foundation
#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite)
import CSQLite
#endif

#if canImport(SQLite3) || canImport(CSQLite)

public enum StoreError: Error, CustomStringConvertible {
    case open(String)
    case query(String)

    public var description: String {
        switch self {
        case .open(let message):
            return message
        case .query(let message):
            return message
        }
    }
}

final class ReadOnlySQLite {
    private var db: OpaquePointer?

    init(path: String) throws {
        let uri = sqliteReadOnlyURI(path: path)
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        let rc = sqlite3_open_v2(uri, &handle, flags, nil)
        guard rc == SQLITE_OK, let handle else {
            let detail = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            if let handle {
                sqlite3_close(handle)
            }
            throw StoreError.open("cannot open database read-only (\(detail))")
        }
        db = handle
        sqlite3_busy_timeout(handle, 2000)
        try exec("PRAGMA query_only = ON;")
        try exec("PRAGMA temp_store = MEMORY;")
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func exec(_ sql: String) throws {
        guard let db else { throw StoreError.query("database is closed") }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if rc != SQLITE_OK {
            let detail = errorMessage.map { String(cString: $0) } ?? "sqlite error \(rc)"
            sqlite3_free(errorMessage)
            throw StoreError.query(detail)
        }
    }

    #if DEBUG
    func execResultCode(_ sql: String) -> Int32 {
        guard let db else { return SQLITE_MISUSE }
        return sqlite3_exec(db, sql, nil, nil, nil)
    }
    #endif

    func tableNames() throws -> Set<String> {
        var names = Set<String>()
        try forEachRow("SELECT name FROM sqlite_master WHERE type = 'table'") { statement in
            if let name = columnText(statement, 0) {
                names.insert(name)
            }
        }
        return names
    }

    func columnNames(_ table: String) throws -> Set<String> {
        guard let table = validatedSQLIdentifier(table) else {
            throw StoreError.query("invalid table name")
        }
        var names = Set<String>()
        try forEachRow("PRAGMA table_info(\(table))") { statement in
            if let name = columnText(statement, 1) {
                names.insert(name)
            }
        }
        return names
    }

    func queryInt64(_ sql: String, bind: ((OpaquePointer) -> Void)? = nil) throws -> Int64? {
        var value: Int64?
        try forEachRow(sql, bind: bind) { statement in
            if sqlite3_column_type(statement, 0) != SQLITE_NULL {
                value = sqlite3_column_int64(statement, 0)
            }
        }
        return value
    }

    func forEachRow(
        _ sql: String,
        bind: ((OpaquePointer) -> Void)? = nil,
        _ body: (OpaquePointer) throws -> Void
    ) throws {
        guard let db else { throw StoreError.query("database is closed") }
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else {
            throw StoreError.query(currentError())
        }
        defer { sqlite3_finalize(statement) }
        bind?(statement)
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                try body(statement)
            } else if step == SQLITE_DONE {
                return
            } else {
                throw StoreError.query(currentError())
            }
        }
    }

    private func currentError() -> String {
        guard let db, let message = sqlite3_errmsg(db) else { return "sqlite error" }
        return String(cString: message)
    }
}

func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
    guard let pointer = sqlite3_column_text(statement, index) else { return nil }
    return String(cString: pointer)
}

func columnBlob(_ statement: OpaquePointer, _ index: Int32) -> Data? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
    let count = Int(sqlite3_column_bytes(statement, index))
    guard count > 0, let pointer = sqlite3_column_blob(statement, index) else { return nil }
    return Data(bytes: pointer, count: count)
}

public final class SQLiteMessageStore: MessageSource {
    private let db: ReadOnlySQLite
    private let messageColumns: Set<String>
    private let chatColumns: Set<String>
    private let attachmentColumns: Set<String>

    public init(path: String) throws {
        let database = try ReadOnlySQLite(path: path)
        let tables = try database.tableNames()
        guard tables.contains(where: { $0.caseInsensitiveCompare("message") == .orderedSame }) else {
            throw StoreError.query("not a Messages database (missing message table)")
        }
        let columns = try database.columnNames("message")
        guard columns.actualName("is_from_me") != nil else {
            throw StoreError.query("not a Messages database (message.is_from_me is missing)")
        }
        db = database
        messageColumns = columns
        chatColumns = (try? database.columnNames("chat")) ?? []
        attachmentColumns = (try? database.columnNames("attachment")) ?? []
    }

    public func maximumRowID() throws -> Int64 {
        try db.queryInt64(MessageSQL.maximumRowID) ?? 0
    }

    public func incomingRowID(fromEnd offset: Int) throws -> Int64? {
        guard offset >= 0 else { return nil }
        return try db.queryInt64(MessageSQL.incomingFromEnd) { statement in
            sqlite3_bind_int64(statement, 1, sqlite3_int64(offset))
        }
    }

    public func oldestIncomingRowID() throws -> Int64? {
        try db.queryInt64(MessageSQL.oldestIncoming)
    }

    public func incomingMessages(after rowID: Int64, limit: Int) throws -> [StoredMessage] {
        let sql = MessageSQL.fetchIncoming(columns: messageColumns)
        var messages: [StoredMessage] = []
        try db.forEachRow(sql, bind: { statement in
            sqlite3_bind_int64(statement, 1, rowID)
            sqlite3_bind_int64(statement, 2, sqlite3_int64(max(limit, 1)))
        }) { statement in
            messages.append(self.readMessage(statement))
        }
        for index in messages.indices {
            messages[index].chat = try loadChat(messageID: messages[index].rowID)
            messages[index].attachmentNames = try loadAttachments(messageID: messages[index].rowID)
        }
        return messages
    }

    #if DEBUG
    public func debugExecResultCode(_ sql: String) -> Int32 {
        db.execResultCode(sql)
    }
    #endif

    private func readMessage(_ statement: OpaquePointer) -> StoredMessage {
        let service = nilIfBlank(columnText(statement, 6)) ?? nilIfBlank(columnText(statement, 7))
        return StoredMessage(
            rowID: sqlite3_column_int64(statement, 0),
            guid: columnText(statement, 1) ?? "",
            service: service,
            senderHandle: nilIfBlank(columnText(statement, 8)),
            plainText: columnText(statement, 2),
            attributedBody: columnBlob(statement, 3),
            dateRaw: sqlite3_column_int64(statement, 4),
            isFromMe: sqlite3_column_int64(statement, 5) != 0,
            associatedMessageType: Int(truncatingIfNeeded: sqlite3_column_int64(statement, 9)),
            otpFlagged: sqlite3_column_int64(statement, 10) != 0
        )
    }

    private func loadChat(messageID: Int64) throws -> ChatSnapshot? {
        guard !chatColumns.isEmpty else { return nil }
        let sql = MessageSQL.selectChats(columns: chatColumns)
        var rows: [ChatCandidate] = []
        try db.forEachRow(sql, bind: { statement in
            sqlite3_bind_int64(statement, 1, messageID)
        }) { statement in
            rows.append(ChatCandidate(
                rowID: sqlite3_column_int64(statement, 0),
                guid: nilIfBlank(columnText(statement, 1)),
                name: nilIfBlank(columnText(statement, 2)),
                identifier: nilIfBlank(columnText(statement, 3)),
                style: Int(truncatingIfNeeded: sqlite3_column_int64(statement, 4)),
                participantCount: Int(truncatingIfNeeded: sqlite3_column_int64(statement, 5))
            ))
        }
        guard let chosen = rows.min(by: { rank($0) < rank($1) }) else { return nil }
        let handles = try loadParticipants(chatID: chosen.rowID)
        return ChatSnapshot(
            guid: chosen.guid,
            name: chosen.name,
            identifier: chosen.identifier,
            isGroup: chatIsGroup(style: chosen.style, participantCount: max(chosen.participantCount, handles.count)),
            participantHandles: handles
        )
    }

    private func loadParticipants(chatID: Int64) throws -> [String] {
        var handles: [String] = []
        try db.forEachRow(MessageSQL.selectParticipants, bind: { statement in
            sqlite3_bind_int64(statement, 1, chatID)
        }) { statement in
            if let handle = nilIfBlank(columnText(statement, 0)) {
                handles.append(handle)
            }
        }
        return handles
    }

    private func loadAttachments(messageID: Int64) throws -> [String] {
        guard !attachmentColumns.isEmpty else { return [] }
        let sql = MessageSQL.selectAttachments(columns: attachmentColumns)
        var names: [String] = []
        try db.forEachRow(sql, bind: { statement in
            sqlite3_bind_int64(statement, 1, messageID)
        }) { statement in
            let transfer = columnText(statement, 0)
            let filename = columnText(statement, 1)
            if let name = attachmentDisplayName(transferName: transfer, filename: filename) {
                names.append(name)
            }
        }
        return names
    }
}

private struct ChatCandidate {
    var rowID: Int64
    var guid: String?
    var name: String?
    var identifier: String?
    var style: Int
    var participantCount: Int
}

private func rank(_ chat: ChatCandidate) -> (Int, Int, Int64) {
    let groupFirst = chatIsGroup(style: chat.style, participantCount: chat.participantCount) ? 0 : 1
    return (groupFirst, -chat.participantCount, chat.rowID)
}

public struct AddressBookLoader {
    public var roots: [URL]

    public init(roots: [URL]) {
        self.roots = roots
    }

    public func load() throws -> ContactIndex {
        var index = ContactIndex()
        var files = 0
        var opened = 0
        for root in roots {
            for url in addressBookDatabaseURLs(root: root) {
                files += 1
                do {
                    let database = try ReadOnlySQLite(path: url.path)
                    try merge(database, into: &index)
                    opened += 1
                } catch {
                    continue
                }
            }
        }
        if files > 0 && opened == 0 {
            throw StoreError.open("address book databases were unreadable")
        }
        return index
    }
}

private func merge(_ database: ReadOnlySQLite, into index: inout ContactIndex) throws {
    let tables = try database.tableNames()
    guard tables.contains(where: { $0.caseInsensitiveCompare("ZABCDRECORD") == .orderedSame }) else {
        return
    }
    let recordColumns = try database.columnNames("ZABCDRECORD")
    guard recordColumns.actualName("Z_PK") != nil else { return }
    var namesByID: [Int64: String] = [:]
    let recordSQL = recordSelect(columns: recordColumns)
    try database.forEachRow(recordSQL) { statement in
        let id = sqlite3_column_int64(statement, 0)
        let first = recordColumns.actualName("ZFIRSTNAME") == nil ? nil : nilIfBlank(columnText(statement, 1))
        let last = recordColumns.actualName("ZLASTNAME") == nil ? nil : nilIfBlank(columnText(statement, 2))
        let organization = recordColumns.actualName("ZORGANIZATION") == nil ? nil : nilIfBlank(columnText(statement, 3))
        if let name = composeContactName(first: first, last: last, organization: organization) {
            namesByID[id] = name
        }
    }
    if tables.contains(where: { $0.caseInsensitiveCompare("ZABCDPHONENUMBER") == .orderedSame }) {
        let phoneColumns = try database.columnNames("ZABCDPHONENUMBER")
        if phoneColumns.actualName("ZOWNER") != nil, phoneColumns.actualName("ZFULLNUMBER") != nil {
            try database.forEachRow("SELECT ZOWNER, ZFULLNUMBER FROM ZABCDPHONENUMBER") { statement in
                let owner = sqlite3_column_int64(statement, 0)
                guard let name = namesByID[owner], let number = columnText(statement, 1) else { return }
                index.add(name: name, phone: number)
            }
        }
    }
    if tables.contains(where: { $0.caseInsensitiveCompare("ZABCDEMAILADDRESS") == .orderedSame }) {
        let emailColumns = try database.columnNames("ZABCDEMAILADDRESS")
        if emailColumns.actualName("ZOWNER") != nil, emailColumns.actualName("ZADDRESS") != nil {
            try database.forEachRow("SELECT ZOWNER, ZADDRESS FROM ZABCDEMAILADDRESS") { statement in
                let owner = sqlite3_column_int64(statement, 0)
                guard let name = namesByID[owner], let email = columnText(statement, 1) else { return }
                index.add(name: name, email: email)
            }
        }
    }
}

private func recordSelect(columns: Set<String>) -> String {
    func field(_ name: String, alias: String) -> String {
        if let actual = columns.actualName(name) {
            return "\(actual) AS \(alias)"
        }
        return "NULL AS \(alias)"
    }
    return """
    SELECT
      \(field("Z_PK", alias: "pk")),
      \(field("ZFIRSTNAME", alias: "first")),
      \(field("ZLASTNAME", alias: "last")),
      \(field("ZORGANIZATION", alias: "org"))
    FROM ZABCDRECORD
    """
}

func composeContactName(first: String?, last: String?, organization: String?) -> String? {
    let parts = [first, last].compactMap(nilIfBlank)
    if !parts.isEmpty {
        return parts.joined(separator: " ")
    }
    return nilIfBlank(organization)
}

#endif
