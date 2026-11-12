import Foundation

public struct RunOptions: Equatable {
    public var backfill: Int?
    public var dryRun: Bool

    public init(backfill: Int? = nil, dryRun: Bool = false) {
        self.backfill = backfill
        self.dryRun = dryRun
    }
}

public struct BatchOutcome: Equatable {
    public var postedRowIDs: [Int64]
    public var skippedOTPRowIDs: [Int64]
    public var failedRowID: Int64?
    public var failureSummary: String?
    public var highWater: Int64?
    public var payloads: [Data]
    public var didInitializeHighWater: Bool

    public init() {
        postedRowIDs = []
        skippedOTPRowIDs = []
        failedRowID = nil
        failureSummary = nil
        highWater = nil
        payloads = []
        didInitializeHighWater = false
    }
}

public func retryDelaySeconds(attempt: Int) -> Double {
    let exponent = min(max(attempt, 1) - 1, 10)
    return min(300, pow(2.0, Double(exponent)))
}

public final class RelayEngine {
    private let source: MessageSource
    private let contacts: NameResolving
    private let state: HighWaterStoring
    private let poster: WebhookPosting
    private var config: RelayConfig
    private let options: RunOptions
    private let timeZone: TimeZone
    private let logger: (String) -> Void
    private var awaitingSave: Int64?
    private var didApplyBackfill = false

    public init(
        source: MessageSource,
        contacts: NameResolving,
        state: HighWaterStoring,
        poster: WebhookPosting,
        config: RelayConfig,
        options: RunOptions = RunOptions(),
        timeZone: TimeZone = TimeZone(secondsFromGMT: 0) ?? .current,
        logger: @escaping (String) -> Void = { _ in }
    ) {
        self.source = source
        self.contacts = contacts
        self.state = state
        self.poster = poster
        self.config = config
        self.options = options
        self.timeZone = timeZone
        self.logger = logger
    }

    /// Called before each message. Return false to stop without moving past the current row.
    public var shouldContinue: () -> Bool = { true }

    public func replaceConfig(_ config: RelayConfig) {
        self.config = config
    }

    public func runBatch() throws -> BatchOutcome {
        var outcome = BatchOutcome()
        if let pending = awaitingSave {
            do {
                try state.save(pending)
                awaitingSave = nil
                logger("saved high-water rowid=\(pending) after earlier delivery")
            } catch {
                outcome.failedRowID = pending
                outcome.failureSummary = "error=state"
                outcome.highWater = try? state.load()
                return outcome
            }
        }

        let existing = try state.load()
        var cursor: Int64
        if !didApplyBackfill, let count = positiveBackfill {
            didApplyBackfill = true
            let start = try backfillCursor(count)
            if existing == nil || start < (existing ?? start) {
                cursor = start
                logger("backfill starting at rowid>\(cursor)")
                if !options.dryRun {
                    try state.save(cursor)
                }
            } else {
                cursor = existing ?? start
            }
        } else if let existing {
            cursor = existing
        } else {
            let maxID = try source.maximumRowID()
            outcome.didInitializeHighWater = true
            outcome.highWater = maxID
            if options.dryRun {
                logger("would initialize high-water to \(maxID); history will not be forwarded")
                return outcome
            }
            try state.save(maxID)
            logger("initialized high-water to \(maxID); history will not be forwarded")
            return outcome
        }

        if config.detailLevel != .ping {
            contacts.refreshIfNeeded(now: Date())
        }

        processing: while true {
            if !shouldContinue() { break }
            let batch = try source.incomingMessages(after: cursor, limit: 50)
                .sorted { $0.rowID < $1.rowID }
            if batch.isEmpty { break }
            for message in batch where message.rowID > cursor {
                if !shouldContinue() { break processing }
                if message.isFromMe {
                    cursor = message.rowID
                    if commit(cursor, outcome: &outcome) == false { return outcome }
                    logger("skipped outgoing rowid=\(message.rowID)")
                    continue
                }
                let text = resolvedText(message)
                if shouldSkipOneTimeCode(
                    text: text,
                    otpFlagged: message.otpFlagged,
                    enabled: config.skipOneTimeCodes
                ) {
                    logger(otpSkipLog(rowID: message.rowID))
                    outcome.skippedOTPRowIDs.append(message.rowID)
                    cursor = message.rowID
                    if commit(cursor, outcome: &outcome) == false { return outcome }
                    continue
                }
                let draft = makeDraft(message, text: text)
                let payload = try makePayload(draft: draft, detail: config.detailLevel, timeZone: timeZone)
                if options.dryRun {
                    outcome.payloads.append(payload)
                    cursor = message.rowID
                    continue
                }
                do {
                    let status = try poster.post(
                        body: payload,
                        url: config.webhookURL,
                        authorization: config.authorizationHeader
                    )
                    logger(deliveryLog(
                        rowID: message.rowID,
                        service: message.service,
                        isGroup: message.chat?.isGroup ?? false,
                        sender: message.senderHandle,
                        status: status
                    ))
                } catch let error as WebhookError {
                    outcome.failedRowID = message.rowID
                    outcome.failureSummary = error.description
                    outcome.highWater = try? state.load()
                    return outcome
                } catch {
                    outcome.failedRowID = message.rowID
                    outcome.failureSummary = "error=failed"
                    outcome.highWater = try? state.load()
                    return outcome
                }
                cursor = message.rowID
                if commit(cursor, outcome: &outcome) == false {
                    awaitingSave = cursor
                    return outcome
                }
                outcome.postedRowIDs.append(message.rowID)
            }
        }
        if !options.dryRun, try state.load() == nil {
            try state.save(cursor)
        }
        outcome.highWater = try state.load() ?? cursor
        return outcome
    }

    private var positiveBackfill: Int? {
        guard let backfill = options.backfill, backfill > 0 else { return nil }
        return backfill
    }

    private func commit(_ rowID: Int64, outcome: inout BatchOutcome) -> Bool {
        if options.dryRun { return true }
        do {
            try state.save(rowID)
            return true
        } catch {
            outcome.failedRowID = rowID
            outcome.failureSummary = "error=state"
            outcome.highWater = try? state.load()
            return false
        }
    }

    private func backfillCursor(_ count: Int) throws -> Int64 {
        if let row = try source.incomingRowID(fromEnd: count - 1) {
            return row - 1
        }
        if let oldest = try source.oldestIncomingRowID() {
            return oldest - 1
        }
        return try source.maximumRowID()
    }

    private func resolvedText(_ message: StoredMessage) -> String? {
        if let plain = message.plainText { return plain }
        guard let body = message.attributedBody,
              let decoded = AttributedBodyDecoder.decode(body),
              !decoded.isEmpty
        else {
            return nil
        }
        return decoded
    }

    private func makeDraft(_ message: StoredMessage, text: String?) -> OutboundDraft {
        let senderName: String?
        if config.detailLevel == .ping {
            senderName = nil
        } else if let handle = message.senderHandle {
            senderName = contacts.name(for: handle)
        } else {
            senderName = nil
        }
        let participants: [Participant]
        if config.detailLevel == .full {
            participants = (message.chat?.participantHandles ?? []).map { handle in
                Participant(handle: handle, name: contacts.name(for: handle))
            }
        } else {
            participants = []
        }
        return OutboundDraft(
            rowID: message.rowID,
            guid: message.guid,
            service: message.service,
            senderHandle: message.senderHandle,
            senderName: senderName,
            text: text,
            dateRaw: message.dateRaw,
            chatGUID: message.chat?.guid,
            chatName: message.chat?.name,
            chatIdentifier: message.chat?.identifier,
            isGroup: message.chat?.isGroup ?? false,
            participants: participants,
            attachmentNames: message.attachmentNames,
            associatedMessageType: message.associatedMessageType
        )
    }
}

public final class ContactBook: NameResolving {
    private var index = ContactIndex()
    private var loadedAt: Date?
    private let refreshInterval: TimeInterval
    private let loader: () throws -> ContactIndex
    private let logger: (String) -> Void
    private var loggedFailure = false

    public init(
        refreshInterval: TimeInterval = 600,
        loader: @escaping () throws -> ContactIndex,
        logger: @escaping (String) -> Void = { _ in }
    ) {
        self.refreshInterval = refreshInterval
        self.loader = loader
        self.logger = logger
    }

    public func refreshIfNeeded(now: Date) {
        if let loadedAt, now.timeIntervalSince(loadedAt) < refreshInterval {
            return
        }
        do {
            index = try loader()
            loadedAt = now
        } catch {
            if !loggedFailure {
                loggedFailure = true
                logger("contact names unavailable")
            }
            loadedAt = now
        }
    }

    public func name(for handle: String) -> String? {
        index.name(for: handle)
    }
}
