//
//  EventPollStateTests.swift
//  keflarTests
//

import Foundation
import Testing
@testable import keflar

struct EventPollStateTests {

    @Test func pollOnceSuccessReturnsEvents() async throws {
        let mock = MockSpeakerClient()
        mock.stubModifyQueue(queueId: "q1")
        mock.stubPollQueue(events: [["path": "player:volume", "itemValue": ["i32_": 50]]])
        let (_, continuation) = AsyncStream.makeStream(of: SpeakerState.self)
        let stateHolder = SpeakerStateHolder(continuation: continuation)
        let pollState = EventPollState(
            client: mock,
            queueId: nil,
            pollTimeout: 1,
            stateHolder: stateHolder,
            graceMinFailures: 3,
            graceDuration: 10
        )
        let events = await pollState.pollOnce()
        #expect(events != nil)
        #expect(events?.volume == 50)
    }

    @Test func pollOnceFailureAfterGracePeriodReturnsNil() async {
        let mock = MockSpeakerClient()
        mock.stubModifyQueue(queueId: "q1")
        mock.stubPollQueue(error: URLError(.networkConnectionLost))
        let (_, continuation) = AsyncStream.makeStream(of: SpeakerState.self)
        let stateHolder = SpeakerStateHolder(continuation: continuation)
        let pollState = EventPollState(
            client: mock,
            queueId: nil,
            pollTimeout: 0.5,
            stateHolder: stateHolder,
            graceMinFailures: 2,
            graceDuration: 0
        )
        let first = await pollState.pollOnce()
        #expect(first == nil)
        let second = await pollState.pollOnce()
        #expect(second == nil)
    }
}
