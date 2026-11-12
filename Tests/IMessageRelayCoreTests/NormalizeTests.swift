import XCTest
@testable import IMessageRelayCore

final class NormalizeTests: XCTestCase {
    func testPhoneDigitsAndLastTen() {
        XCTAssertEqual(phoneDigits("+1 (415) 555-0100"), "14155550100")
        XCTAssertTrue(handlesReferToSamePhone("+1 (415) 555-0100", "4155550100"))
        XCTAssertTrue(handlesReferToSamePhone("415-555-0100", "+14155550100"))
        XCTAssertTrue(handlesReferToSamePhone("12345", "12345"))
        XCTAssertFalse(handlesReferToSamePhone("12345", "99912345"))
        XCTAssertFalse(handlesReferToSamePhone("4155550100", "4155550101"))
    }

    func testEmailNormalizationAndContactIndex() {
        XCTAssertEqual(normalizeEmail(" Ada@Example.com "), "ada@example.com")
        var index = ContactIndex()
        index.add(name: "Test Person", phone: "+1 (415) 555-0100", email: "Ada@Example.com")
        index.add(name: "Other Person", phone: "4155550100", email: "ada@example.com")
        XCTAssertEqual(index.name(for: "4155550100"), "Test Person")
        XCTAssertEqual(index.name(for: "+14155550100"), "Test Person")
        XCTAssertEqual(index.name(for: "ada@example.com"), "Test Person")
        XCTAssertNil(index.name(for: "12345"))
    }

    func testShortCodeDoesNotMatchLongerNumber() {
        var index = ContactIndex()
        index.add(name: "Desk", phone: "12345")
        XCTAssertEqual(index.name(for: "12345"), "Desk")
        XCTAssertNil(index.name(for: "99912345"))
    }

    func testMaskHandle() {
        XCTAssertEqual(maskHandle("+14155550100"), "***0100")
        XCTAssertFalse(maskHandle("+14155550100").contains("415555"))
        XCTAssertEqual(maskHandle("ada@example.com"), "***.com")
        XCTAssertFalse(maskHandle("ada@example.com").contains("ada"))
        XCTAssertEqual(maskHandle("abc"), "***")
    }

    func testAttachmentNamesAreBasenamesOnly() {
        XCTAssertEqual(
            attachmentDisplayName(
                transferName: nil,
                filename: "/Users/example/Library/Messages/Attachments/aa/bb/IMG.heic"
            ),
            "IMG.heic"
        )
        XCTAssertEqual(
            attachmentDisplayName(transferName: "photo.jpg", filename: "/tmp/secret/photo.jpg"),
            "photo.jpg"
        )
        XCTAssertEqual(attachmentDisplayName(transferName: "  ", filename: "notes.txt"), "notes.txt")
        let name = attachmentDisplayName(transferName: nil, filename: "/tmp/secret/photo.jpg")
        XCTAssertFalse(name?.contains("/") ?? true)
        XCTAssertFalse(name?.contains("secret") ?? true)
    }

    func testGroupDetection() {
        XCTAssertTrue(chatIsGroup(style: 43, participantCount: 1))
        XCTAssertFalse(chatIsGroup(style: 45, participantCount: 1))
        XCTAssertTrue(chatIsGroup(style: 45, participantCount: 2))
    }
}
