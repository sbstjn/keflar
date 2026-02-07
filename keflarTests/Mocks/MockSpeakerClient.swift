//
//  MockSpeakerClient.swift
//  keflarTests
//
//  For use in single-threaded tests only. Not thread-safe.
//

import Foundation
@testable import keflar

/// Mock implementation of SpeakerClientProtocol for unit tests. Stub responses and record calls.
final class MockSpeakerClient: SpeakerClientProtocol, @unchecked Sendable {
    private var getDataStubs: [String: [String: Any]] = [:]
    private var getDataErrors: [String: Error] = [:]
    private var getRowsStub: [String: Any] = [:]
    private var getRowsError: Error?
    private var modifyQueueResult: String = "mock-queue-id"
    private var modifyQueueError: Error?
    private var pollQueueResult: [[String: Any]] = []
    private var pollQueueError: Error?

    private(set) var setDataWithBodyCalls: [(path: String, role: String)] = []
    private(set) var getDataCalls: [String] = []
    private(set) var getRowsCalls: [(path: String, from: Int, to: Int)] = []

    func stubGetData(path: String, response: [String: Any]) {
        getDataStubs[path] = response
    }

    func stubGetData(path: String, error: Error) {
        getDataErrors[path] = error
    }

    func stubGetRows(response: [String: Any]) {
        getRowsStub = response
    }

    func stubGetRows(error: Error) {
        getRowsError = error
    }

    func stubModifyQueue(queueId: String) {
        modifyQueueResult = queueId
    }

    func stubModifyQueue(error: Error) {
        modifyQueueError = error
    }

    func stubPollQueue(events: [[String: Any]]) {
        pollQueueResult = events
    }

    func stubPollQueue(error: Error) {
        pollQueueError = error
    }

    func getData(path: String) async throws -> [String: Any] {
        getDataCalls.append(path)
        if let err = getDataErrors[path] {
            throw err
        }
        return getDataStubs[path] ?? [:]
    }

    func setDataWithBody<E: Encodable>(path: String, role: String, value: E) async throws {
        setDataWithBodyCalls.append((path, role))
    }

    func getRows(path: String, from: Int, to: Int) async throws -> [String: Any] {
        getRowsCalls.append((path, from, to))
        if let err = getRowsError {
            throw err
        }
        return getRowsStub
    }

    func modifyQueue() async throws -> String {
        if let err = modifyQueueError {
            throw err
        }
        return modifyQueueResult
    }

    func pollQueue(queueId: String, timeout: TimeInterval) async throws -> [[String: Any]] {
        if let err = pollQueueError {
            throw err
        }
        return pollQueueResult
    }

    func getRequestCounts() async -> RequestCounts? {
        nil
    }

    func reset() {
        getDataStubs = [:]
        getDataErrors = [:]
        getRowsStub = [:]
        getRowsError = nil
        modifyQueueResult = "mock-queue-id"
        modifyQueueError = nil
        pollQueueResult = []
        pollQueueError = nil
        setDataWithBodyCalls = []
        getDataCalls = []
        getRowsCalls = []
    }
}
