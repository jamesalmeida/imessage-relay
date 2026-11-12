import XCTest
@testable import IMessageRelayCore

final class PayloadTests: XCTestCase {
    func testPingHasNoSenderOrText() throws {
        let data = try makePayload(draft: sample(), detail: .ping, timeZone: TimeZone(secondsFromGMT: 0)!)
        let object = try jsonObject(data)
        XCTAssertEqual(Set(object.keys), ["date", "detail_level", "event"])
        XCTAssertEqual(object["event"] as? String, "message.received")
        XCTAssertEqual(object["detail_level"] as? String, "ping")
        XCTAssertEqual(object["date"] as? String, "2001-01-01T00:00:00+00:00")
        let rendered = String(data: data, encoding: .utf8)!
        XCTAssertFalse(rendered.contains("secret-text"))
        XCTAssertFalse(rendered.contains("sender"))
        XCTAssertFalse(rendered.contains("photo.jpg"))
        XCTAssertFalse(rendered.contains("rowid"))
        XCTAssertFalse(rendered.contains("guid-1"))
    }

    func testSenderOmitsTextAndAttachmentNames() throws {
        let data = try makePayload(draft: sample(), detail: .sender, timeZone: TimeZone(secondsFromGMT: 0)!)
        let object = try jsonObject(data)
        XCTAssertNil(object["text"])
        XCTAssertNil(object["attachments"])
        XCTAssertNil(object["rowid"])
        XCTAssertNil(object["guid"])
        XCTAssertNil(object["participants"])
        XCTAssertNil(object["associated_message_type"])
        XCTAssertEqual(object["detail_level"] as? String, "sender")
        XCTAssertEqual(object["service"] as? String, "iMessage")
        XCTAssertEqual(object["attachment_count"] as? Int ?? (object["attachment_count"] as? NSNumber)?.intValue, 1)
        let sender = object["sender"] as? [String: Any]
        XCTAssertEqual(sender?["handle"] as? String, "sender-handle")
        XCTAssertEqual(sender?["name"] as? String, "Test Person")
        let chat = object["chat"] as? [String: Any] ?? [:]
        XCTAssertEqual(Set(chat.keys), ["is_group", "name"])
        XCTAssertEqual(chat["name"] as? String, "Family")
        XCTAssertEqual((chat["is_group"] as? Bool) ?? (chat["is_group"] as? NSNumber)?.boolValue, true)
        let rendered = String(data: data, encoding: .utf8)!
        XCTAssertFalse(rendered.contains("secret-text"))
        XCTAssertFalse(rendered.contains("photo.jpg"))
        XCTAssertFalse(rendered.contains("other-handle"))
    }

    func testFullPayloadIncludesTextParticipantsAndNames() throws {
        let data = try makePayload(draft: sample(), detail: .full, timeZone: TimeZone(secondsFromGMT: 0)!)
        let object = try jsonObject(data)
        XCTAssertEqual(object["detail_level"] as? String, "full")
        XCTAssertEqual(object["text"] as? String, "secret-text")
        XCTAssertEqual(object["guid"] as? String, "guid-1")
        XCTAssertEqual((object["rowid"] as? NSNumber)?.int64Value, 42)
        XCTAssertEqual((object["associated_message_type"] as? NSNumber)?.intValue, 2000)
        let attachments = object["attachments"] as? [Any]
        XCTAssertEqual(attachments?.first as? String, "photo.jpg")
        let chat = object["chat"] as? [String: Any]
        XCTAssertEqual(chat?["identifier"] as? String, "chat-id")
        let participants = chat?["participants"] as? [[String: Any]]
        XCTAssertEqual(participants?.count, 1)
        XCTAssertEqual(participants?.first?["handle"] as? String, "other-handle")
        XCTAssertEqual(participants?.first?["name"] as? String, "Other Person")
    }

    func testRedactionHidesTextUnlessAsked() throws {
        let data = try makePayload(draft: sample(), detail: .full, timeZone: TimeZone(secondsFromGMT: 0)!)
        let hidden = redactPayloadForDisplay(data, showText: false)
        XCTAssertFalse(String(data: hidden, encoding: .utf8)!.contains("secret-text"))
        XCTAssertTrue(String(data: hidden, encoding: .utf8)!.contains("[redacted]"))
        let shown = redactPayloadForDisplay(data, showText: true)
        XCTAssertTrue(String(data: shown, encoding: .utf8)!.contains("secret-text"))
        let ping = try makePayload(draft: sample(), detail: .ping, timeZone: TimeZone(secondsFromGMT: 0)!)
        let pingShown = redactPayloadForDisplay(ping, showText: false)
        XCTAssertEqual(Set(try jsonObject(pingShown).keys), ["date", "detail_level", "event"])
    }

    func testDeliveryLogOmitsTextAndMasksHandle() {
        let line = deliveryLog(rowID: 7, service: "SMS", isGroup: false, sender: "+14155550100", status: 204)
        XCTAssertEqual(line, "rowid=7 service=SMS is_group=false sender=***0100 status=204")
        XCTAssertFalse(line.contains("secret-text"))
        XCTAssertFalse(line.contains("4155550100"))
        XCTAssertEqual(otpSkipLog(rowID: 9), "skipped otp rowid=9")
    }

    private func sample() -> OutboundDraft {
        OutboundDraft(
            rowID: 42,
            guid: "guid-1",
            service: "iMessage",
            senderHandle: "sender-handle",
            senderName: "Test Person",
            text: "secret-text",
            dateRaw: 0,
            chatGUID: "chat-guid",
            chatName: "Family",
            chatIdentifier: "chat-id",
            isGroup: true,
            participants: [Participant(handle: "other-handle", name: "Other Person")],
            attachmentNames: ["/tmp/secret/photo.jpg"],
            associatedMessageType: 2000
        )
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
}
