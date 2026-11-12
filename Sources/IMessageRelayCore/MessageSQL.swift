import Foundation

public enum MessageSQL {
    public static let maximumRowID = "SELECT COALESCE(MAX(ROWID), 0) FROM message"
    public static let incomingFromEnd =
        "SELECT ROWID FROM message WHERE is_from_me = 0 ORDER BY ROWID DESC LIMIT 1 OFFSET ?"
    public static let oldestIncoming = "SELECT MIN(ROWID) FROM message WHERE is_from_me = 0"

    public static func fetchIncoming(columns: Set<String>) -> String {
        let body = columnExpression(columns, "attributedBody", qualifier: "m")
        let service = columnExpression(columns, "service", qualifier: "m")
        let text = columnExpression(columns, "text", qualifier: "m")
        let associated = columns.actualName("associated_message_type").map { "COALESCE(m.\($0), 0)" } ?? "0"
        let otpColumns = columns.compactMap { name -> String? in
            guard OTPDetector.isIndicatorColumn(name), let safe = validatedSQLIdentifier(name) else { return nil }
            return safe
        }.sorted()
        let otpExpression: String
        if otpColumns.isEmpty {
            otpExpression = "0"
        } else {
            let checks = otpColumns.map { "COALESCE(m.\($0), 0) != 0" }.joined(separator: " OR ")
            otpExpression = "CASE WHEN \(checks) THEN 1 ELSE 0 END"
        }
        return """
        SELECT
          m.ROWID,
          m.guid,
          \(text),
          \(body),
          COALESCE(m.date, 0),
          m.is_from_me,
          \(service) AS service,
          h.service AS handle_service,
          h.id AS sender_handle,
          \(associated) AS associated_message_type,
          \(otpExpression) AS otp_flagged
        FROM message AS m
        LEFT JOIN handle AS h ON h.ROWID = m.handle_id
        WHERE m.is_from_me = 0 AND m.ROWID > ?
        ORDER BY m.ROWID ASC
        LIMIT ?
        """
    }

    public static func selectChats(columns: Set<String>) -> String {
        let guid = columnExpression(columns, "guid", qualifier: "c")
        let name = columnExpression(columns, "display_name", qualifier: "c")
        let identifier = columnExpression(columns, "chat_identifier", qualifier: "c")
        let style = columns.actualName("style").map { "COALESCE(c.\($0), 0)" } ?? "0"
        return """
        SELECT
          c.ROWID,
          \(guid),
          \(name),
          \(identifier),
          \(style),
          (SELECT COUNT(*) FROM chat_handle_join AS j WHERE j.chat_id = c.ROWID)
        FROM chat_message_join AS cmj
        JOIN chat AS c ON c.ROWID = cmj.chat_id
        WHERE cmj.message_id = ?
        """
    }

    public static let selectParticipants = """
    SELECT h.id
    FROM chat_handle_join AS chj
    JOIN handle AS h ON h.ROWID = chj.handle_id
    WHERE chj.chat_id = ?
    ORDER BY h.id
    """

    public static func selectAttachments(columns: Set<String>) -> String {
        let transfer = columnExpression(columns, "transfer_name", qualifier: "a")
        let filename = columnExpression(columns, "filename", qualifier: "a")
        return """
        SELECT \(transfer), \(filename)
        FROM message_attachment_join AS maj
        JOIN attachment AS a ON a.ROWID = maj.attachment_id
        WHERE maj.message_id = ?
        """
    }
}

private func columnExpression(_ columns: Set<String>, _ name: String, qualifier: String) -> String {
    if let actual = columns.actualName(name) {
        return "\(qualifier).\(actual)"
    }
    return "NULL"
}

extension Set where Element == String {
    func actualName(_ name: String) -> String? {
        guard let found = first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
            return nil
        }
        return validatedSQLIdentifier(found)
    }
}
