import Foundation

/// Playback control: play, pause, seek, next, previous, shuffle, repeat.
struct PlaybackControl: Sendable {
    private let transport: any SpeakerTransport
    private let client: any SpeakerClientProtocol
    private var getState: @Sendable () -> SpeakerState

    init(transport: any SpeakerTransport, client: any SpeakerClientProtocol, getState: @escaping @Sendable () -> SpeakerState) {
        self.transport = transport
        self.client = client
        self.getState = getState
    }

    func play() async throws {
        try await transport.play()
    }

    func pause() async throws {
        try await transport.pause()
    }

    func playNext() async throws {
        try await transport.playNext()
    }

    func playPrevious() async throws {
        try await transport.playPrevious()
    }

    func seekTo(playTimeMs: Int) async throws {
        try await transport.seekTo(playTimeMs: playTimeMs)
    }

    func setShuffle(_ on: Bool) async throws {
        let state = getState()
        let repeatMode = state.repeatMode ?? .off
        let mode = playModeString(shuffle: on, repeatMode: repeatMode)
        try await client.setDataWithBody(path: playModePath.path, role: "value", value: SetPlayModeRequest(mode: mode))
    }

    func setRepeat(_ mode: RepeatMode) async throws {
        let state = getState()
        let shuffleOn = state.shuffle ?? false
        let modeString = playModeString(shuffle: shuffleOn, repeatMode: mode)
        try await client.setDataWithBody(path: playModePath.path, role: "value", value: SetPlayModeRequest(mode: modeString))
    }

    private func playModeString(shuffle: Bool, repeatMode: RepeatMode) -> String {
        if shuffle {
            switch repeatMode {
            case .off: return "shuffle"
            case .one: return "shuffleRepeatOne"
            case .all: return "shuffleRepeatAll"
            }
        }
        switch repeatMode {
        case .off: return "normal"
        case .one: return "repeatOne"
        case .all: return "repeatAll"
        }
    }
}
