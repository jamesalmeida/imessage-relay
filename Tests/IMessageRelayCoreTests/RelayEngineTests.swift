import XCTest
@testable import IMessageRelayCore

final class RelayEngineTests: XCTestCase {
    func testFirstRunInitializesToMaxAndDoesNotFetchHistory() throws {
        let source = FakeSource(maxID: 100, messages: [message(1, text: "old")])
        let state = FakeState()
        let poster = FakePoster()
        let logs = LogBox()
        let engine = makeEngine(source: source, state: state, poster: poster, logs: logs)
        let outcome = try engine.runBatch()
        XCTAssertTrue(outcome.didInitializeHighWater)
        XCTAssertEqual(outcome.highWater, 100)
        XCTAssertEqual(state.value, 100)
        XCTAssertTrue(outcome.postedRowIDs.isEmpty)
        XCTAssertTrue(poster.bodies.isEmpty)
        XCTAssertTrue(source.fetchedAfter.isEmpty)
        XCTAssertTrue(logs.lines.contains { $0.contains("initialized high-water to 100") })
    }

    func testPostsInOrderAndStopsOnFailure() throws {
        let source = FakeSource(maxID: 3, messages: [message(1, text: "one"), message(2, text: "two"), message(3, text: "three")])
        let state = FakeState(value: 0)
        let poster = FakePoster()
        poster.failOnCall = 2
        let engine = makeEngine(source: source, state: state, poster: poster, detail: .full)
        let outcome = try engine.runBatch()
        XCTAssertEqual(outcome.postedRowIDs, [1])
        XCTAssertEqual(outcome.failedRowID, 2)
        XCTAssertEqual(outcome.failureSummary, "status=500")
        XCTAssertEqual(state.value, 1)
        XCTAssertEqual(poster.bodies.count, 1)
        let text = String(data: poster.bodies[0], encoding: .utf8)
        XCTAssertTrue(text?.contains("one") == true)
        XCTAssertFalse(text?.contains("two") == true)
    }

    func testOTPSkipAdvancesHighWaterAndDoesNotPostText() throws {
        let source = FakeSource(
            maxID: 6,
            messages: [
                message(5, text: "Your Apple ID code is 123456 pineapples"),
                message(6, text: "hello from a friend"),
            ]
        )
        let state = FakeState(value: 0)
        let poster = FakePoster()
        let logs = LogBox()
        let engine = makeEngine(source: source, state: state, poster: poster, logs: logs, detail: .full)
        let outcome = try engine.runBatch()
        XCTAssertEqual(outcome.skippedOTPRowIDs, [5])
        XCTAssertEqual(outcome.postedRowIDs, [6])
        XCTAssertEqual(state.value, 6)
        XCTAssertEqual(poster.bodies.count, 1)
        let posted = String(data: poster.bodies[0], encoding: .utf8) ?? ""
        XCTAssertFalse(posted.contains("pineapples"))
        XCTAssertFalse(posted.contains("123456"))
        XCTAssertTrue(logs.lines.contains("skipped otp rowid=5"))
        XCTAssertFalse(logs.lines.joined(separator: "\n").contains("pineapples"))
        XCTAssertFalse(logs.lines.joined(separator: "\n").contains("123456"))
    }

    func testOTPThenFailureKeepsTheCodeAdvanced() throws {
        let source = FakeSource(
            maxID: 6,
            messages: [
                message(5, text: "Your verification code is 847291"),
                message(6, text: "after"),
            ]
        )
        let state = FakeState(value: 0)
        let poster = FakePoster()
        poster.failOnCall = 1
        let engine = makeEngine(source: source, state: state, poster: poster, detail: .full)
        let outcome = try engine.runBatch()
        XCTAssertEqual(outcome.skippedOTPRowIDs, [5])
        XCTAssertEqual(outcome.failedRowID, 6)
        XCTAssertEqual(state.value, 5)
        XCTAssertTrue(poster.bodies.isEmpty)
    }

    func testSkipCanBeDisabled() throws {
        let source = FakeSource(maxID: 2, messages: [message(2, text: "Your Uber code is 4921")])
        let state = FakeState(value: 0)
        let poster = FakePoster()
        let engine = makeEngine(source: source, state: state, poster: poster, detail: .full, skip: false)
        let outcome = try engine.runBatch()
        XCTAssertEqual(outcome.postedRowIDs, [2])
        XCTAssertTrue(outcome.skippedOTPRowIDs.isEmpty)
        XCTAssertTrue(String(data: poster.bodies[0], encoding: .utf8)?.contains("4921") == true)
    }

    func testDatabaseOTPFlagSkipsWithoutKeywords() throws {
        var flagged = message(4, text: "see you at 7:30")
        flagged.otpFlagged = true
        let source = FakeSource(maxID: 4, messages: [flagged])
        let state = FakeState(value: 0)
        let poster = FakePoster()
        let logs = LogBox()
        let engine = makeEngine(source: source, state: state, poster: poster, logs: logs)
        let outcome = try engine.runBatch()
        XCTAssertEqual(outcome.skippedOTPRowIDs, [4])
        XCTAssertTrue(poster.bodies.isEmpty)
        XCTAssertEqual(logs.lines.filter { $0.hasPrefix("skipped otp") }, ["skipped otp rowid=4"])
        XCTAssertFalse(logs.lines.joined(separator: "\n").contains("7:30"))
    }

    func testPingPayloadFromEngineOmitsText() throws {
        let source = FakeSource(maxID: 8, messages: [message(8, text: "UNIQUE_TEXT_TOKEN")])
        let state = FakeState(value: 0)
        let poster = FakePoster()
        let engine = makeEngine(source: source, state: state, poster: poster, detail: .ping)
        _ = try engine.runBatch()
        let body = String(data: poster.bodies[0], encoding: .utf8) ?? ""
        XCTAssertFalse(body.contains("UNIQUE_TEXT_TOKEN"))
        XCTAssertFalse(body.contains("sender"))
        XCTAssertTrue(body.contains("\"detail_level\":\"ping\""))
    }

    func testAttributedBodyIsUsedWhenTextIsNull() throws {
        var stored = message(3, text: nil)
        stored.attributedBody = helloArchive()
        let source = FakeSource(maxID: 3, messages: [stored])
        let state = FakeState(value: 0)
        let poster = FakePoster()
        let engine = makeEngine(source: source, state: state, poster: poster, detail: .full)
        _ = try engine.runBatch()
        XCTAssertTrue(String(data: poster.bodies[0], encoding: .utf8)?.contains("Hello") == true)
    }

    func testDryRunDoesNotPostOrSave() throws {
        let source = FakeSource(maxID: 4, messages: [message(4, text: "secret-text")])
        let state = FakeState(value: 0)
        let poster = FakePoster()
        let engine = makeEngine(source: source, state: state, poster: poster, detail: .full, dryRun: true)
        let outcome = try engine.runBatch()
        XCTAssertEqual(outcome.payloads.count, 1)
        XCTAssertTrue(poster.bodies.isEmpty)
        XCTAssertEqual(state.value, 0)
        XCTAssertTrue(String(data: outcome.payloads[0], encoding: .utf8)?.contains("secret-text") == true)
    }

    func testBackfillSelectsTheLastNIncoming() throws {
        let source = FakeSource(
            maxID: 30,
            messages: [message(10, text: "old"), message(20, text: "mid"), message(30, text: "new")]
        )
        let state = FakeState()
        let poster = FakePoster()
        let engine = makeEngine(source: source, state: state, poster: poster, detail: .full, backfill: 2)
        let first = try engine.runBatch()
        XCTAssertEqual(first.postedRowIDs, [20, 30])
        let second = try engine.runBatch()
        XCTAssertTrue(second.postedRowIDs.isEmpty)
        XCTAssertEqual(poster.bodies.count, 2)
    }

    func testStateSaveFailureDoesNotRepost() throws {
        let source = FakeSource(maxID: 2, messages: [message(1, text: "one"), message(2, text: "two")])
        let state = FakeState(value: 0)
        state.remainingFailures = 1
        let poster = FakePoster()
        let engine = makeEngine(source: source, state: state, poster: poster, detail: .full)
        let first = try engine.runBatch()
        XCTAssertEqual(first.failureSummary, "error=state")
        XCTAssertEqual(poster.bodies.count, 1)
        XCTAssertEqual(state.value, 0)
        let second = try engine.runBatch()
        XCTAssertEqual(second.postedRowIDs, [2])
        XCTAssertEqual(state.value, 2)
        XCTAssertEqual(poster.bodies.count, 2)
        XCTAssertTrue(String(data: poster.bodies[0], encoding: .utf8)?.contains("one") == true)
        XCTAssertTrue(String(data: poster.bodies[1], encoding: .utf8)?.contains("two") == true)
    }

    func testFailureLogDoesNotContainWebhookSecrets() throws {
        let source = FakeSource(maxID: 1, messages: [message(1, text: "hello")])
        let state = FakeState(value: 0)
        let poster = FakePoster()
        poster.failOnCall = 1
        let logs = LogBox()
        var config = baseConfig(detail: .ping, skip: true)
        config = RelayConfig(
            webhookURL: URL(string: "https://example.com/hook?token=unit-test-query")!,
            authorizationHeader: "Bearer unit-test-header",
            pollSeconds: 3,
            skipOneTimeCodes: true,
            detailLevel: .ping
        )
        let engine = RelayEngine(
            source: source,
            contacts: FakeNames(),
            state: state,
            poster: poster,
            config: config,
            timeZone: TimeZone(secondsFromGMT: 0)!,
            logger: { logs.lines.append($0) }
        )
        let outcome = try engine.runBatch()
        XCTAssertEqual(poster.authorizations, ["Bearer unit-test-header"])
        let blob = logs.lines.joined(separator: "\n") + (outcome.failureSummary ?? "")
        XCTAssertFalse(blob.contains("unit-test-query"))
        XCTAssertFalse(blob.contains("unit-test-header"))
        XCTAssertFalse(blob.contains("example.com"))
    }

    func testShouldContinueStopsTheBatch() throws {
        let source = FakeSource(
            maxID: 3,
            messages: [message(1, text: "one"), message(2, text: "two"), message(3, text: "three")]
        )
        let state = FakeState(value: 0)
        let poster = FakePoster()
        let engine = makeEngine(source: source, state: state, poster: poster, detail: .full)
        engine.shouldContinue = { poster.bodies.count < 1 }
        let outcome = try engine.runBatch()
        XCTAssertEqual(outcome.postedRowIDs, [1])
        XCTAssertEqual(poster.bodies.count, 1)
        XCTAssertEqual(state.value, 1)
    }

    func testRetryDelayIsBounded() {
        XCTAssertEqual(retryDelaySeconds(attempt: 1), 1)
        XCTAssertEqual(retryDelaySeconds(attempt: 3), 4)
        XCTAssertEqual(retryDelaySeconds(attempt: 20), 300)
    }

    func testSenderDetailResolvesNameAndSkipsParticipants() throws {
        let source = FakeSource(
            maxID: 1,
            messages: [message(1, text: "secret-text", handle: "+14155550100", chat: ChatSnapshot(
                guid: "c",
                name: "Family",
                identifier: "c",
                isGroup: true,
                participantHandles: ["other-handle"]
            ))]
        )
        let names = FakeNames(map: ["+14155550100": "Test Person", "other-handle": "Hidden"])
        let state = FakeState(value: 0)
        let poster = FakePoster()
        let engine = RelayEngine(
            source: source,
            contacts: names,
            state: state,
            poster: poster,
            config: baseConfig(detail: .sender, skip: true),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            logger: { _ in }
        )
        _ = try engine.runBatch()
        let body = String(data: poster.bodies[0], encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("Test Person"))
        XCTAssertFalse(body.contains("secret-text"))
        XCTAssertFalse(body.contains("other-handle"))
        XCTAssertFalse(body.contains("Hidden"))
        XCTAssertGreaterThan(names.refreshes, 0)
    }

    private func makeEngine(
        source: FakeSource,
        state: FakeState,
        poster: FakePoster,
        logs: LogBox = LogBox(),
        detail: DetailLevel = .ping,
        skip: Bool = true,
        dryRun: Bool = false,
        backfill: Int? = nil
    ) -> RelayEngine {
        RelayEngine(
            source: source,
            contacts: FakeNames(),
            state: state,
            poster: poster,
            config: baseConfig(detail: detail, skip: skip),
            options: RunOptions(backfill: backfill, dryRun: dryRun),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            logger: { logs.lines.append($0) }
        )
    }

    private func baseConfig(detail: DetailLevel, skip: Bool) -> RelayConfig {
        RelayConfig(
            webhookURL: URL(string: "https://example.com/hook")!,
            authorizationHeader: "Bearer unit-test-header",
            pollSeconds: 3,
            skipOneTimeCodes: skip,
            detailLevel: detail
        )
    }

    private func message(
        _ rowID: Int64,
        text: String?,
        handle: String = "+14155550100",
        chat: ChatSnapshot? = nil
    ) -> StoredMessage {
        StoredMessage(
            rowID: rowID,
            guid: "g\(rowID)",
            service: "iMessage",
            senderHandle: handle,
            plainText: text,
            dateRaw: 0,
            chat: chat
        )
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

private final class FakeSource: MessageSource {
    var maxID: Int64
    var messages: [StoredMessage]
    var fetchedAfter: [Int64] = []

    init(maxID: Int64, messages: [StoredMessage]) {
        self.maxID = maxID
        self.messages = messages
    }

    func maximumRowID() throws -> Int64 { maxID }

    func incomingRowID(fromEnd offset: Int) throws -> Int64? {
        let incoming = messages.filter { !$0.isFromMe }.map(\.rowID).sorted(by: >)
        guard offset >= 0, offset < incoming.count else { return nil }
        return incoming[offset]
    }

    func oldestIncomingRowID() throws -> Int64? {
        messages.filter { !$0.isFromMe }.map(\.rowID).min()
    }

    func incomingMessages(after rowID: Int64, limit: Int) throws -> [StoredMessage] {
        fetchedAfter.append(rowID)
        return Array(messages.filter { !$0.isFromMe && $0.rowID > rowID }.sorted { $0.rowID < $1.rowID }.prefix(limit))
    }
}

private final class FakeState: HighWaterStoring {
    var value: Int64?
    var remainingFailures: Int

    init(value: Int64? = nil, remainingFailures: Int = 0) {
        self.value = value
        self.remainingFailures = remainingFailures
    }

    func load() throws -> Int64? { value }

    func save(_ rowID: Int64) throws {
        if remainingFailures > 0 {
            remainingFailures -= 1
            throw HighWaterError.io("full")
        }
        value = rowID
    }
}

private final class FakePoster: WebhookPosting {
    var bodies: [Data] = []
    var authorizations: [String?] = []
    var failOnCall: Int?

    func post(body: Data, url: URL, authorization: String?) throws -> Int {
        authorizations.append(authorization)
        let call = bodies.count + 1
        if failOnCall == call {
            throw WebhookError.status(500)
        }
        bodies.append(body)
        return 204
    }
}

private final class FakeNames: NameResolving {
    var map: [String: String]
    var refreshes = 0

    init(map: [String: String] = [:]) {
        self.map = map
    }

    func refreshIfNeeded(now: Date) { refreshes += 1 }

    func name(for handle: String) -> String? { map[handle] }
}

private final class LogBox {
    var lines: [String] = []
}
