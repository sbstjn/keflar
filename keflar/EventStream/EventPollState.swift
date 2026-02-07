import Foundation
import os

private let pollStateLog = Logger(subsystem: "com.sbstjn.keflar", category: "EventPoll")

/// Event polling state machine: manages queue subscription and long-poll lifecycle.
/// Lifecycle: ensure queue (create or reuse if not stale) → pollQueue → parse events → merge into state → notify. Queue is recreated when missing or older than `queueStaleInterval`.
/// After a grace period of consecutive failures (configurable), reports connection lost and terminates the stream.
/// The library only reports `.reconnecting` / `.disconnected`; the app is responsible for reconnect retries (e.g. polling until success or user switches speaker).
/// Used only from the single event-drive task per Speaker; marked Sendable for AsyncStream unfolding capture.
final class EventPollState: @unchecked Sendable {
    let client: any SpeakerClientProtocol
    let pollTimeout: TimeInterval
    let stateHolder: SpeakerStateHolder
    let graceMinFailures: Int
    let graceDuration: TimeInterval
    let onConnectionEvent: (@Sendable (ConnectionEvent) -> Void)?

    var queueId: String?
    var lastSubscribedAt: Date?
    var consecutivePollFailures: Int = 0
    var firstPollFailureTime: Date?
    var reconnectingReported: Bool = false
    var disconnectedReported: Bool = false

    init(
        client: any SpeakerClientProtocol,
        queueId: String?,
        pollTimeout: TimeInterval,
        stateHolder: SpeakerStateHolder,
        graceMinFailures: Int = connectionGraceMinFailures,
        graceDuration: TimeInterval = connectionGraceDuration,
        onConnectionEvent: (@Sendable (ConnectionEvent) -> Void)? = nil
    ) {
        self.client = client
        self.queueId = queueId
        self.lastSubscribedAt = queueId != nil ? Date() : nil
        self.pollTimeout = pollTimeout
        self.stateHolder = stateHolder
        self.graceMinFailures = graceMinFailures
        self.graceDuration = graceDuration
        self.onConnectionEvent = onConnectionEvent
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
            let events = StateReducer.parseEvents(pathToItemValue: pathToItemValue)
            mergeEvents(events, into: &stateHolder.state)
            stateHolder.notifyStateChanged()
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
            // Force a new queue on next poll so we get a fresh subscription; the device may have invalidated the previous queue during the outage.
            lastSubscribedAt = nil
            onConnectionEvent?(.recovered)
        }
    }

    private func recordPollFailure() {
        consecutivePollFailures += 1
        if firstPollFailureTime == nil {
            firstPollFailureTime = Date()
        }
        if !reconnectingReported {
            reconnectingReported = true
            onConnectionEvent?(.reconnecting)
        }
        if consecutivePollFailures >= graceMinFailures,
           let first = firstPollFailureTime,
           Date().timeIntervalSince(first) >= graceDuration,
           !disconnectedReported {
            disconnectedReported = true
            onConnectionEvent?(.disconnected)
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
