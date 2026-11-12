import XCTest
@testable import IMessageRelayCore

final class AttributedBodyTests: XCTestCase {
    func testFixtureHello() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/hello-typedstream.bin")
        let data = try Data(contentsOf: url)
        XCTAssertEqual(AttributedBodyDecoder.decodeFallback(data), "Hello")
        XCTAssertEqual(AttributedBodyDecoder.decode(data), "Hello")
        XCTAssertEqual(data, archive(text: "Hello", length: [0x05]))
    }

    func testMultibyteUTF8() {
        let text = "Hi 👋"
        let data = archive(text: text, length: [UInt8(text.utf8.count)])
        XCTAssertEqual(AttributedBodyDecoder.decodeFallback(data), text)
    }

    func testTwoByteLittleEndianLength() {
        let text = String(repeating: "é", count: 200)
        XCTAssertEqual(text.utf8.count, 400)
        let data = archive(text: text, length: [0x81, 0x90, 0x01])
        XCTAssertEqual(AttributedBodyDecoder.decodeFallback(data), text)
    }

    func testFourByteLittleEndianLength() {
        let data = archive(text: "four", length: [0x82, 4, 0, 0, 0])
        XCTAssertEqual(AttributedBodyDecoder.decodeFallback(data), "four")
    }

    func testGarbageAndTruncationReturnNil() {
        XCTAssertNil(AttributedBodyDecoder.decodeFallback(Data("no class here".utf8)))
        XCTAssertNil(AttributedBodyDecoder.decodeFallback(Data()))
        XCTAssertNil(AttributedBodyDecoder.decodeFallback(Data("NSString+".utf8)))
        var distant = Data("NSString".utf8)
        distant.append(contentsOf: [UInt8](repeating: 0x01, count: 30))
        distant.append(0x2B)
        distant.append(0x01)
        distant.append(UInt8(ascii: "a"))
        XCTAssertNil(AttributedBodyDecoder.decodeFallback(distant))
    }

    private func archive(text: String, length: [UInt8]) -> Data {
        var data = Data([0x04, 0x0B])
        data.append(contentsOf: "streamtyped".utf8)
        data.append(contentsOf: [
            0x81, 0xE8, 0x03, 0x84, 0x01, 0x40, 0x84, 0x84, 0x84, 0x12,
        ])
        data.append(contentsOf: "NSAttributedString".utf8)
        data.append(contentsOf: [0x00, 0x84, 0x84, 0x08])
        data.append(contentsOf: "NSObject".utf8)
        data.append(contentsOf: [0x00, 0x85, 0x92, 0x84, 0x84, 0x84, 0x08])
        data.append(contentsOf: "NSString".utf8)
        data.append(contentsOf: [0x01, 0x94, 0x84, 0x01, 0x2B])
        data.append(contentsOf: length)
        data.append(contentsOf: text.utf8)
        data.append(contentsOf: [0x86, 0x84, 0x02, 0x69, 0x49, 0x01, 0x05, 0x92])
        return data
    }
}
