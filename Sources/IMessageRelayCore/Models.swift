import Foundation

public struct ChatSnapshot: Equatable {
    public var guid: String?
    public var name: String?
    public var identifier: String?
    public var isGroup: Bool
    public var participantHandles: [String]

    public init(
        guid: String? = nil,
        name: String? = nil,
        identifier: String? = nil,
        isGroup: Bool = false,
        participantHandles: [String] = []
    ) {
        self.guid = guid
        self.name = name
        self.identifier = identifier
        self.isGroup = isGroup
        self.participantHandles = participantHandles
    }
}

public struct StoredMessage: Equatable {
    public var rowID: Int64
    public var guid: String
    public var service: String?
    public var senderHandle: String?
    public var plainText: String?
    public var attributedBody: Data?
    public var dateRaw: Int64
    public var isFromMe: Bool
    public var associatedMessageType: Int
    public var otpFlagged: Bool
    public var chat: ChatSnapshot?
    public var attachmentNames: [String]

    public init(
        rowID: Int64,
        guid: String,
        service: String? = nil,
        senderHandle: String? = nil,
        plainText: String? = nil,
        attributedBody: Data? = nil,
        dateRaw: Int64 = 0,
        isFromMe: Bool = false,
        associatedMessageType: Int = 0,
        otpFlagged: Bool = false,
        chat: ChatSnapshot? = nil,
        attachmentNames: [String] = []
    ) {
        self.rowID = rowID
        self.guid = guid
        self.service = service
        self.senderHandle = senderHandle
        self.plainText = plainText
        self.attributedBody = attributedBody
        self.dateRaw = dateRaw
        self.isFromMe = isFromMe
        self.associatedMessageType = associatedMessageType
        self.otpFlagged = otpFlagged
        self.chat = chat
        self.attachmentNames = attachmentNames
    }
}

public protocol MessageSource: AnyObject {
    func maximumRowID() throws -> Int64
    func incomingRowID(fromEnd offset: Int) throws -> Int64?
    func oldestIncomingRowID() throws -> Int64?
    func incomingMessages(after rowID: Int64, limit: Int) throws -> [StoredMessage]
}

public protocol NameResolving: AnyObject {
    func refreshIfNeeded(now: Date)
    func name(for handle: String) -> String?
}
