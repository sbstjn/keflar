import Foundation

/// Aggregate root for playback session: current track, queue, playback control.
@MainActor
public final class PlaybackSession: @unchecked Sendable {
    private let playbackControl: PlaybackControl
    private let queueManager: QueueManager
    private var getState: () -> SpeakerState

    init(playbackControl: PlaybackControl, queueManager: QueueManager, getState: @escaping () -> SpeakerState) {
        self.playbackControl = playbackControl
        self.queueManager = queueManager
        self.getState = getState
    }

    public func configureGetState(_ getState: @escaping () -> SpeakerState) {
        self.getState = getState
    }

    // MARK: - State (from shadow state)

    public var playerState: PlayerState? { getState().playerState }
    public var playTime: Int? { getState().playTime }
    public var duration: Int? { getState().duration }
    public var currentQueueIndex: Int? { getState().currentQueueIndex }
    public var shuffle: Bool? { getState().shuffle }
    public var repeatMode: RepeatMode? { getState().repeatMode }

    // MARK: - Control

    public func play() async throws {
        try await playbackControl.play()
    }

    public func pause() async throws {
        try await playbackControl.pause()
    }

    public func playNext() async throws {
        try await playbackControl.playNext()
    }

    public func playPrevious() async throws {
        try await playbackControl.playPrevious()
    }

    public func seekTo(playTimeMs: Int) async throws {
        try await playbackControl.seekTo(playTimeMs: playTimeMs)
    }

    public func setShuffle(_ on: Bool) async throws {
        try await playbackControl.setShuffle(on)
    }

    public func setRepeat(_ mode: RepeatMode) async throws {
        try await playbackControl.setRepeat(mode)
    }

    public func fetchPlayQueue(from startIndex: Int, to endIndex: Int) async throws -> PlayQueueResult {
        try await queueManager.fetchPlayQueue(from: startIndex, to: endIndex)
    }

    public func fetchPlayQueueWithRaw(from startIndex: Int, to endIndex: Int) async throws -> PlayQueueWithRawResult {
        try await queueManager.fetchPlayQueueWithRaw(from: startIndex, to: endIndex)
    }

    public func playPlaylist(service: AudioService, playlistId: String) async throws {
        try await queueManager.playPlaylist(service: service, playlistId: playlistId)
    }

    public func hasServiceConfiguration(_ service: AudioService) async throws -> Bool {
        try await queueManager.hasServiceConfiguration(service)
    }
}
