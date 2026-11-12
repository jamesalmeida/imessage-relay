import Foundation

public struct Participant: Equatable {
    public var handle: String
    public var name: String?

    public init(handle: String, name: String?) {
        self.handle = handle
        self.name = name
    }
}

public struct OutboundDraft: Equatable {
    public var rowID: Int64
    public var guid: String
    public var service: String?
    public var senderHandle: String?
    public var senderName: String?
    public var text: String?
    public var dateRaw: Int64
    public var chatGUID: String?
    public var chatName: String?
    public var chatIdentifier: String?
    public var isGroup: Bool
    public var participants: [Participant]
    public var attachmentNames: [String]
    public var associatedMessageType: Int

    public init(
        rowID: Int64,
        guid: String,
        service: String? = nil,
        senderHandle: String? = nil,
        senderName: String? = nil,
        text: String? = nil,
        dateRaw: Int64 = 0,
        chatGUID: String? = nil,
        chatName: String? = nil,
        chatIdentifier: String? = nil,
        isGroup: Bool = false,
        participants: [Participant] = [],
        attachmentNames: [String] = [],
        associatedMessageType: Int = 0
    ) {
        self.rowID = rowID
        self.guid = guid
        self.service = service
        self.senderHandle = senderHandle
        self.senderName = senderName
        self.text = text
        self.dateRaw = dateRaw
        self.chatGUID = chatGUID
        self.chatName = chatName
        self.chatIdentifier = chatIdentifier
        self.isGroup = isGroup
        self.participants = participants
        self.attachmentNames = attachmentNames
        self.associatedMessageType = associatedMessageType
    }
}

public func makePayload(draft: OutboundDraft, detail: DetailLevel, timeZone: TimeZone) throws -> Data {
    let date = formatISO8601(dateFromAppleTimestamp(draft.dateRaw), timeZone: timeZone)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    switch detail {
    case .ping:
        return try encoder.encode(PingBody(event: "message.received", detail_level: detail.rawValue, date: date))
    case .sender:
        let body = SenderBody(
            event: "message.received",
            detail_level: detail.rawValue,
            date: date,
            service: draft.service,
            sender: PersonBody(handle: draft.senderHandle, name: draft.senderName),
            chat: SenderChatBody(name: draft.chatName, is_group: draft.isGroup),
            attachment_count: draft.attachmentNames.count
        )
        return try encoder.encode(body)
    case .full:
        let body = FullBody(
            event: "message.received",
            detail_level: detail.rawValue,
            rowid: draft.rowID,
            guid: draft.guid,
            service: draft.service,
            sender: PersonBody(handle: draft.senderHandle, name: draft.senderName),
            chat: FullChatBody(
                guid: draft.chatGUID,
                name: draft.chatName,
                identifier: draft.chatIdentifier,
                is_group: draft.isGroup,
                participants: draft.participants.map { PersonBody(handle: $0.handle, name: $0.name) }
            ),
            date: date,
            text: draft.text,
            attachments: draft.attachmentNames.map(lastPathComponent).filter { !$0.isEmpty },
            associated_message_type: draft.associatedMessageType
        )
        return try encoder.encode(body)
    }
}

public func redactPayloadForDisplay(_ data: Data, showText: Bool) -> Data {
    guard !showText else { return data }
    guard var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return data
    }
    if object["text"] is String {
        object["text"] = "[redacted]"
    }
    guard let rendered = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
        return data
    }
    return rendered
}

public func deliveryLog(rowID: Int64, service: String?, isGroup: Bool, sender: String?, status: Int) -> String {
    let serviceText = nilIfBlank(service) ?? "unknown"
    return "rowid=\(rowID) service=\(serviceText) is_group=\(isGroup) sender=\(maskHandle(sender ?? "")) status=\(status)"
}

public func otpSkipLog(rowID: Int64) -> String {
    "skipped otp rowid=\(rowID)"
}

private struct PingBody: Encodable {
    var event: String
    var detail_level: String
    var date: String
}

private struct PersonBody: Encodable {
    var handle: String?
    var name: String?
}

private struct SenderChatBody: Encodable {
    var name: String?
    var is_group: Bool
}

private struct SenderBody: Encodable {
    var event: String
    var detail_level: String
    var date: String
    var service: String?
    var sender: PersonBody
    var chat: SenderChatBody
    var attachment_count: Int
}

private struct FullChatBody: Encodable {
    var guid: String?
    var name: String?
    var identifier: String?
    var is_group: Bool
    var participants: [PersonBody]
}

private struct FullBody: Encodable {
    var event: String
    var detail_level: String
    var rowid: Int64
    var guid: String
    var service: String?
    var sender: PersonBody
    var chat: FullChatBody
    var date: String
    var text: String?
    var attachments: [String]
    var associated_message_type: Int
}
