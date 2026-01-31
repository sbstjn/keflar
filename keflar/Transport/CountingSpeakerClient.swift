import Foundation

/// Wraps a client and counts each HTTP request by type. Use when connecting with `countRequests: true`.
struct CountingSpeakerClient: SpeakerClientProtocol, Sendable {
    private let wrapped: any SpeakerClientProtocol
    private let counter: RequestCounter

    init(wrapping wrapped: any SpeakerClientProtocol) {
        self.wrapped = wrapped
        self.counter = RequestCounter()
    }

    func getData(path: String) async throws -> [String: Any] {
        await counter.incrementGetData()
        return try await wrapped.getData(path: path)
    }

    func setData(path: String, value: String) async throws {
        await counter.incrementSetData()
        try await wrapped.setData(path: path, value: value)
    }

    func setDataWithBody(path: String, role: String, value: SendableBody) async throws {
        await counter.incrementSetDataWithBody()
        try await wrapped.setDataWithBody(path: path, role: role, value: value)
    }

    func getRows(path: String, from: Int, to: Int) async throws -> [String: Any] {
        await counter.incrementGetRows()
        return try await wrapped.getRows(path: path, from: from, to: to)
    }

    func modifyQueue() async throws -> String {
        await counter.incrementModifyQueue()
        return try await wrapped.modifyQueue()
    }

    func pollQueue(queueId: String, timeout: TimeInterval) async throws -> [[String: Any]] {
        await counter.incrementPollQueue()
        return try await wrapped.pollQueue(queueId: queueId, timeout: timeout)
    }

    func getRequestCounts() async -> RequestCounts? { await counter.counts() }
}

private actor RequestCounter {
    var getDataCount = 0
    var setDataCount = 0
    var setDataWithBodyCount = 0
    var getRowsCount = 0
    var modifyQueueCount = 0
    var pollQueueCount = 0

    func incrementGetData() { getDataCount += 1 }
    func incrementSetData() { setDataCount += 1 }
    func incrementSetDataWithBody() { setDataWithBodyCount += 1 }
    func incrementGetRows() { getRowsCount += 1 }
    func incrementModifyQueue() { modifyQueueCount += 1 }
    func incrementPollQueue() { pollQueueCount += 1 }

    func counts() -> RequestCounts {
        RequestCounts(
            getData: getDataCount,
            setData: setDataCount,
            setDataWithBody: setDataWithBodyCount,
            getRows: getRowsCount,
            modifyQueue: modifyQueueCount,
            pollQueue: pollQueueCount
        )
    }
}
