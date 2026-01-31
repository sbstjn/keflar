import Foundation

/// Event polling state machine; manages queue subscription and long-poll lifecycle.
final class EventPollState {
    let client: any SpeakerClientProtocol
    let pollTimeout: TimeInterval
    let stateHolder: SpeakerStateHolder
    var queueId: String?
    var lastSubscribedAt: Date?

    init(client: any SpeakerClientProtocol, queueId: String?, pollTimeout: TimeInterval, stateHolder: SpeakerStateHolder) {
        self.client = client
        self.queueId = queueId
        self.lastSubscribedAt = queueId != nil ? Date() : nil
        self.pollTimeout = pollTimeout
        self.stateHolder = stateHolder
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

    /// Perform a single long-poll; returns events or nil on error/cancellation.
    private func performPoll() async -> SpeakerEvents? {
        if Task.isCancelled { return nil }
        do {
            try await ensureQueue()
        } catch {
            return nil
        }
        guard let qid = queueId else { return nil }
        if Task.isCancelled { return nil }
        do {
            let rawEvents = try await client.pollQueue(queueId: qid, timeout: pollTimeout)
            var pathToItemValue: [String: Any] = [:]
            for item in rawEvents {
                guard let path = item["path"] as? String,
                      let itemValue = item["itemValue"] else { continue }
                pathToItemValue[path] = itemValue
            }
            let events = StateReducer.parseEvents(pathToItemValue: pathToItemValue)
            mergeEvents(events, into: &stateHolder.state)
            stateHolder.notifyStateChanged()
            return events
        } catch {
            return nil
        }
    }

    /// Poll once; retry queue creation on first failure.
    func pollOnce() async -> SpeakerEvents? {
        if let events = await performPoll() { return events }
        do { try await ensureQueue() } catch { return nil }
        return await performPoll()
    }
}
