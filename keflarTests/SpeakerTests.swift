//
//  SpeakerTests.swift
//  keflarTests
//

import Foundation
import Testing
@testable import keflar

private let defaultHost = "192.168.8.4"

private func connectToSpeaker(host: String = defaultHost, awaitInitialState: Bool = true, countRequests: Bool = false) async throws -> Speaker {
    try await SpeakerConnection(host: host).connect(awaitInitialState: awaitInitialState, countRequests: countRequests)
}

/// Tidal playlist "Sins, Not Tragedies" — https://tidal.com/playlist/a1696225-3c8e-4333-99a1-a77afa213f24
private let tidalPlaylistId = "a1696225-3c8e-4333-99a1-a77afa213f24"

private let waitPlaybackTimeout: Duration = .seconds(10)
private let waitAfterScrub: Duration = .seconds(5)
private let waitAfterScrubStep: Duration = .seconds(1)
private let minPlayTimeIncreaseMs: Int = 500
private let waitAfterSkip: Duration = .seconds(2)
private let seekToleranceMs: Int = 2000

private func formatAudioCodecInfo(_ info: AudioCodecInfo?) -> String {
    guard let info = info else { return "none" }
    var parts: [String] = []
    if let c = info.codec { parts.append("codec=\(c)") }
    if let f = info.sampleFrequency { parts.append("sampleFreq=\(f)") }
    if let r = info.streamSampleRate { parts.append("streamRate=\(r)") }
    if let ch = info.streamChannels { parts.append("channels=\(ch)") }
    if let n = info.nrAudioChannels { parts.append("nrCh=\(n)") }
    if let s = info.serviceID { parts.append("service=\(s)") }
    return parts.isEmpty ? "none" : parts.joined(separator: ", ")
}

struct SpeakerTests {

    /// Set speaker to wifi, play first song, scrub 10s, wait 5s (assert play progress). First skip with shuffle off, then enable shuffle and second skip; assert song after second skip is not the deterministic next (i.e. different from song after first skip).
    @MainActor
    @Test(.disabled("Requires live speaker on network")) func playThenFlipModes() async throws {
        let name = "playThenFlipModes"
        let speaker: Speaker
        do {
            speaker = try await connectToSpeaker(countRequests: true)
        } catch {
            if let connectErr = error as? SpeakerConnectError, case .invalidJSON(let preview) = connectErr {
                print("[\(name)] Connect failed (invalid JSON): \(preview)")
            } else {
                print("[\(name)] Connect failed: \(error)")
            }
            Issue.record("connect failed: \(error)")
            return
        }
        #expect(!speaker.model.isEmpty)
        print("[\(name)] Connected: \(speaker.model) \(speaker.version)")

        try await speaker.powerOn()
        try await Task.sleep(for: .milliseconds(500))
        try await speaker.setSource(.wifi)
        try await Task.sleep(for: .seconds(2))

        try await speaker.setShuffle(false)
        try await Task.sleep(for: .seconds(1))
        try await speaker.playTidalPlaylist(playlistId: tidalPlaylistId)
        try await waitUntil(timeout: waitPlaybackTimeout) { speaker.isPlaying() }
        #expect(speaker.isPlaying(), "speaker should be playing after playlist start")

        try await waitUntil(timeout: waitPlaybackTimeout) { speaker.currentSong != nil }
        guard let song1 = speaker.currentSong else {
            Issue.record("currentSong still nil after waiting for first track")
            return
        }
        print("[\(name)] Track 1: \(song1.title ?? "-") — \(song1.artist ?? "-")")
        print("[\(name)] Audio codec: \(formatAudioCodecInfo(speaker.audioCodecInfo))")

        let posBefore = speaker.state.playTime ?? 0
        let seekTargetMs = max(0, posBefore + 10_000)
        try await speaker.seekTo(playTimeMs: seekTargetMs)
        try await waitUntil(timeout: waitPlaybackTimeout) { (speaker.state.playTime ?? 0) >= seekTargetMs - seekToleranceMs }
        #expect((speaker.state.playTime ?? 0) >= seekTargetMs - seekToleranceMs, "scrub: playTime should update after seek")
        print("[\(name)] Scrubbed: playTime \(posBefore) ms → \(speaker.state.playTime ?? 0) ms")

        // Wait 5s in steps and assert play timer progresses at each step.
        var lastPlayTimeMs = speaker.state.playTime ?? 0
        var elapsed: Duration = .zero
        while elapsed < waitAfterScrub {
            try await Task.sleep(for: waitAfterScrubStep)
            elapsed += waitAfterScrubStep
            let nowMs = speaker.state.playTime ?? 0
            #expect(nowMs >= lastPlayTimeMs + minPlayTimeIncreaseMs, "playTime should progress: was \(lastPlayTimeMs) ms, now \(nowMs) ms after \(elapsed)")
            lastPlayTimeMs = nowMs
            print("[\(name)] Play progress: \(nowMs) ms after \(elapsed)")
        }

        // First skip: shuffle off (deterministic next track).
        try await speaker.playNext()
        try await Task.sleep(for: waitAfterSkip)
        let songAfterFirstSkip = speaker.currentSong?.title
        print("[\(name)] After first skip (no shuffle): \(songAfterFirstSkip ?? "-")")
        #expect(songAfterFirstSkip != nil && songAfterFirstSkip != song1.title, "first skip should change track")

        // Enable shuffle, then second skip; with shuffle the next track must not be the same as the deterministic next (i.e. must differ from song after first skip).
        try await speaker.setShuffle(true)
        try await Task.sleep(for: .seconds(1))
        try await speaker.playNext()
        try await Task.sleep(for: waitAfterSkip)
        let songAfterSecondSkip = speaker.currentSong?.title
        print("[\(name)] After second skip (shuffle on): \(songAfterSecondSkip ?? "-")")
        print("[\(name)] Audio codec: \(formatAudioCodecInfo(speaker.audioCodecInfo))")
        #expect(songAfterSecondSkip != songAfterFirstSkip, "with shuffle, second skip should not land on the same track as deterministic next (was \(songAfterFirstSkip ?? "nil"))")

        if let counts = await speaker.getRequestCounts() {
            print("[\(name)] HTTP requests: getData=\(counts.getData) setDataWithBody=\(counts.setDataWithBody) getRows=\(counts.getRows) modifyQueue=\(counts.modifyQueue) pollQueue=\(counts.pollQueue) total=\(counts.total)")
        }
        print("[\(name)] Done: first song, scrub 10s, wait 5s, skip (no shuffle), shuffle on, skip (shuffle)")
    }
}

/// Wait until condition is true, polling every 300ms; returns when met or timeout (and records an issue on timeout).
@MainActor
private func waitUntil(timeout: Duration, condition: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now >= deadline {
            Issue.record("Timeout waiting for condition after \(timeout)")
            return
        }
        try await Task.sleep(for: .milliseconds(300))
    }
}
