//
//  TransportTests.swift
//  keflarTests
//

import Foundation
import Testing
@testable import keflar

struct TransportTests {

    @Test func setVolumeCallsClientWithVolumePathAndValueRole() async throws {
        let mock = MockSpeakerClient()
        let transport = DefaultSpeakerTransport(client: mock)
        try await transport.setVolume(75)
        let calls = mock.setDataWithBodyCalls
        #expect(calls.contains { $0.path == APIPath.volume.path && $0.role == "value" })
    }

    @Test func setMuteCallsClientWithMutePathAndValueRole() async throws {
        let mock = MockSpeakerClient()
        let transport = DefaultSpeakerTransport(client: mock)
        try await transport.setMute(true)
        #expect(mock.setDataWithBodyCalls.contains { $0.path == APIPath.mute.path && $0.role == "value" })
    }

    @Test func setSourceCallsClientWithPhysicalSourcePath() async throws {
        let mock = MockSpeakerClient()
        let transport = DefaultSpeakerTransport(client: mock)
        try await transport.setSource(.standby)
        #expect(mock.setDataWithBodyCalls.contains { $0.path == APIPath.physicalSource.path && $0.role == "value" })
    }

    @Test func playCallsClientWithPlayerControlPathAndActivateRole() async throws {
        let mock = MockSpeakerClient()
        let transport = DefaultSpeakerTransport(client: mock)
        try await transport.play()
        #expect(mock.setDataWithBodyCalls.contains { $0.path == APIPath.playerControl.path && $0.role == "activate" })
    }

    @Test func pauseCallsClientWithPlayerControlPath() async throws {
        let mock = MockSpeakerClient()
        let transport = DefaultSpeakerTransport(client: mock)
        try await transport.pause()
        #expect(mock.setDataWithBodyCalls.contains { $0.path == APIPath.playerControl.path })
    }

    @Test func playNextCallsClientWithNextControl() async throws {
        let mock = MockSpeakerClient()
        let transport = DefaultSpeakerTransport(client: mock)
        try await transport.playNext()
        #expect(mock.setDataWithBodyCalls.contains { $0.path == APIPath.playerControl.path })
    }

    @Test func seekToCallsClientWithPlayerControlPath() async throws {
        let mock = MockSpeakerClient()
        let transport = DefaultSpeakerTransport(client: mock)
        try await transport.seekTo(playTimeMs: 30_000)
        #expect(mock.setDataWithBodyCalls.contains { $0.path == APIPath.playerControl.path })
    }
}
