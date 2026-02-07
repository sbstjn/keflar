//
//  SpeakerControlTests.swift
//  keflarTests
//
//  Unit tests for Speaker control methods (play, pause, volume, seek). Speaker delegates to SpeakerTransport;
//  these tests verify the full path from Speaker API to mock client calls.
//

import Foundation
import Testing
@testable import keflar

@MainActor
private func makeSpeakerForTesting(mockClient: MockSpeakerClient) -> Speaker {
    let transport = DefaultSpeakerTransport(client: mockClient)
    let stateHolder = SpeakerStateHolder(continuation: nil)
    let (stateStream, stateCont) = AsyncStream.makeStream(of: SpeakerState.self)
    stateCont.finish()
    return Speaker(
        model: "Test",
        version: "1.0",
        client: mockClient,
        transport: transport,
        playlistManager: MockPlaylistManager(),
        queueId: "test-queue",
        stateHolder: stateHolder,
        stateStream: stateStream
    )
}

struct SpeakerControlTests {

    @Test @MainActor func speakerPlayCallsTransport() async throws {
        let mock = MockSpeakerClient()
        let speaker = makeSpeakerForTesting(mockClient: mock)
        try await speaker.play()
        #expect(mock.setDataWithBodyCalls.contains { $0.path == APIPath.playerControl.path && $0.role == "activate" })
    }

    @Test @MainActor func speakerPauseCallsTransport() async throws {
        let mock = MockSpeakerClient()
        let speaker = makeSpeakerForTesting(mockClient: mock)
        try await speaker.pause()
        #expect(mock.setDataWithBodyCalls.contains { $0.path == APIPath.playerControl.path })
    }

    @Test @MainActor func speakerSetVolumeCallsTransport() async throws {
        let mock = MockSpeakerClient()
        let speaker = makeSpeakerForTesting(mockClient: mock)
        try await speaker.setVolume(50)
        #expect(mock.setDataWithBodyCalls.contains { $0.path == APIPath.volume.path && $0.role == "value" })
    }

    @Test @MainActor func speakerSeekToCallsTransport() async throws {
        let mock = MockSpeakerClient()
        let speaker = makeSpeakerForTesting(mockClient: mock)
        try await speaker.seekTo(playTimeMs: 30_000)
        #expect(mock.setDataWithBodyCalls.contains { $0.path == APIPath.playerControl.path && $0.role == "activate" })
    }

    @Test @MainActor func speakerSetMuteCallsTransport() async throws {
        let mock = MockSpeakerClient()
        let speaker = makeSpeakerForTesting(mockClient: mock)
        try await speaker.setMute(true)
        #expect(mock.setDataWithBodyCalls.contains { $0.path == APIPath.mute.path && $0.role == "value" })
    }
}
