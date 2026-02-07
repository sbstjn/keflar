import Foundation
import os

private let pollStateLog = Logger(subsystem: "com.sbstjn.keflar", category: "EventPoll")

/// Event polling state machine: manages queue subscription and long-poll lifecycle.
/// Lifecycle: ensure queue (create or reuse if not stale) → pollQueue → parse events → merge into state → notify. Queue is recreated when missing or older than `queueStaleInterval`.
/// After a grace period of consecutive failures (configurable), reports connection lost and terminates the stream.
/// The library only reports `.reconnecting` / `.disconnected`; the app is responsible for reconnect retries (e.g. polling until success or user switches speaker).
actor EventPollState {
    private let client: any SpeakerClientProtocol
    private let pollTimeout: TimeInterval
    private let stateHolder: SpeakerStateHolder
    private let graceMinFailures: Int
    private let graceDuration: TimeInterval
    private let connectionEventContinuation: AsyncStream<ConnectionEvent>.Continuation?

    private var queueId: String?
    private var lastSubscribedAt: Date?
    private var consecutivePollFailures: Int = 0
    private var firstPollFailureTime: Date?
    private var reconnectingReported: Bool = false
    private var disconnectedReported: Bool = false

    init(
        client: any SpeakerClientProtocol,
        queueId: String?,
        pollTimeout: TimeInterval,
        stateHolder: SpeakerStateHolder,
        graceMinFailures: Int = connectionGraceMinFailures,
        graceDuration: TimeInterval = connectionGraceDuration,
        connectionEventContinuation: AsyncStream<ConnectionEvent>.Continuation? = nil
    ) {
        self.client = client
        self.queueId = queueId
        self.lastSubscribedAt = queueId != nil ? Date() : nil
        self.pollTimeout = pollTimeout
        self.stateHolder = stateHolder
        self.graceMinFailures = graceMinFailures
        self.graceDuration = graceDuration
        self.connectionEventContinuation = connectionEventContinuation
    }

    /// Ensure event queue is active; creates new queue if stale or missing.
    func ensureQueue() async throws {
        let now = Date()
        if let last = lastSubscribedAt, now.timeIntervalSince(last) < queueStaleInterval, queueId != nil {
            return
        }
        let id = try await client.modifyQueue()
        queueId = id
        lastSubscribedAt = Date()
    }

    /// Perform a single long-poll; returns events or nil on error/cancellation. Updates failure count and invokes onConnectionEvent when appropriate.
    private func performPoll() async -> SpeakerEvents? {
        if Task.isCancelled { return nil }
        do {
            try await ensureQueue()
        } catch {
            recordPollFailure()
            return nil
        }
        guard let qid = queueId else {
            recordPollFailure()
            return nil
        }
        if Task.isCancelled { return nil }
        do {
            let rawEvents = try await client.pollQueue(queueId: qid, timeout: pollTimeout)
            recordPollSuccess()
            var pathToItemValue: [String: Any] = [:]
            for item in rawEvents {
                guard let path = item["path"] as? String,
                      let itemValue = item["itemValue"] else { continue }
                pathToItemValue[path] = itemValue
            }
            if let physicalPayload = pathToItemValue["settings:/kef/play/physicalSource"] {
                pollStateLog.info("poll received physicalSource payload=\(String(describing: physicalPayload))")
            }
            let events = EventParser.parseEvents(pathToItemValue: pathToItemValue)
            await stateHolder.updateState { state in
                mergeEvents(events, into: state)
            }
            return events
        } catch {
            recordPollFailure()
            return nil
        }
    }

    private func recordPollSuccess() {
        if consecutivePollFailures > 0 {
            consecutivePollFailures = 0
            firstPollFailureTime = nil
            reconnectingReported = false
            lastSubscribedAt = nil
            connectionEventContinuation?.yield(.recovered)
        }
    }

    private func recordPollFailure() {
        consecutivePollFailures += 1
        if firstPollFailureTime == nil {
            firstPollFailureTime = Date()
        }
        if !reconnectingReported {
            reconnectingReported = true
            connectionEventContinuation?.yield(.reconnecting)
        }
        if consecutivePollFailures >= graceMinFailures,
           let first = firstPollFailureTime,
           Date().timeIntervalSince(first) >= graceDuration,
           !disconnectedReported {
            disconnectedReported = true
            connectionEventContinuation?.yield(.disconnected)
        }
    }

    /// Poll once; retry queue creation on first failure. Returns nil to terminate stream after connection lost.
    func pollOnce() async -> SpeakerEvents? {
        if disconnectedReported { return nil }
        if let events = await performPoll() { return events }
        if disconnectedReported { return nil }
        do { try await ensureQueue() } catch {
            recordPollFailure()
            return nil
        }
        if disconnectedReported { return nil }
        return await performPoll()
    }
}
