import Foundation

/// Focused slice of state for volume/mute. Observe this to reduce re-renders when only volume changes.
public struct VolumeState: Equatable, Sendable {
    public let volume: Int?
    public let mute: Bool?
    
    public init(volume: Int? = nil, mute: Bool? = nil) {
        self.volume = volume
        self.mute = mute
    }
}

/// Focused slice of state for playback. Observe this to reduce re-renders when only playback changes.
public struct PlaybackStateSlice: Equatable, Sendable {
    public let playerState: PlayerState?
    public let playTime: Int?
    public let duration: Int?
    public let currentQueueIndex: Int?
    public let shuffle: Bool?
    public let repeatMode: RepeatMode?
    
    public init(
        playerState: PlayerState? = nil,
        playTime: Int? = nil,
        duration: Int? = nil,
        currentQueueIndex: Int? = nil,
        shuffle: Bool? = nil,
        repeatMode: RepeatMode? = nil
    ) {
        self.playerState = playerState
        self.playTime = playTime
        self.duration = duration
        self.currentQueueIndex = currentQueueIndex
        self.shuffle = shuffle
        self.repeatMode = repeatMode
    }
}

/// Accumulated shadow state of the remote device; updated from initial getData and event batches.
///
/// Marked `@unchecked Sendable` so it can be passed across actor boundaries (e.g. from SpeakerStateHolder actor to MainActor).
/// Raw payloads keyed by API path; use typed accessors (e.g. currentSong) or typedData[.playerData] for known paths.
public struct SpeakerState: @unchecked Sendable {
    public let source: PhysicalSource?
    public let volume: Int?
    public let mute: Bool?
    public let deviceName: String?
    /// Player state: `.playing`, `.paused`, etc. (`player:player/data`).
    public let playerState: PlayerState?
    /// Playback position in ms (`player:player/data/playTime`).
    public let playTime: Int?
    /// Track duration in ms (`player:player/data` → `status.duration`).
    public let duration: Int?
    /// Zero-based index of current track in queue (`player:player/data` → `trackRoles.value.i32_`).
    public let currentQueueIndex: Int?
    /// Shuffle on/off from settings:/mediaPlayer/playMode.
    public let shuffle: Bool?
    /// Repeat mode from settings:/mediaPlayer/playMode.
    public let repeatMode: RepeatMode?
    /// Raw getData/event payloads by API path. Values are SendableDict (boxed [String: Any]). Internal; use typed accessors (e.g. currentSong) or path-specific APIs.
    let typedData: [APIPath: SendableDict]

    /// Internal: typedData uses internal SendableDict; library constructs state.
    init(
        source: PhysicalSource? = nil,
        volume: Int? = nil,
        mute: Bool? = nil,
        deviceName: String? = nil,
        playerState: PlayerState? = nil,
        playTime: Int? = nil,
        duration: Int? = nil,
        currentQueueIndex: Int? = nil,
        shuffle: Bool? = nil,
        repeatMode: RepeatMode? = nil,
        typedData: [APIPath: SendableDict] = [:]
    ) {
        self.source = source
        self.volume = volume
        self.mute = mute
        self.deviceName = deviceName
        self.playerState = playerState
        self.playTime = playTime
        self.duration = duration
        self.currentQueueIndex = currentQueueIndex
        self.shuffle = shuffle
        self.repeatMode = repeatMode
        self.typedData = typedData
    }
    
    /// Create a copy with updated fields.
    func with(
        source: PhysicalSource?? = nil,
        volume: Int?? = nil,
        mute: Bool?? = nil,
        deviceName: String?? = nil,
        playerState: PlayerState?? = nil,
        playTime: Int?? = nil,
        duration: Int?? = nil,
        currentQueueIndex: Int?? = nil,
        shuffle: Bool?? = nil,
        repeatMode: RepeatMode?? = nil,
        typedData: [APIPath: SendableDict]? = nil
    ) -> SpeakerState {
        SpeakerState(
            source: source ?? self.source,
            volume: volume ?? self.volume,
            mute: mute ?? self.mute,
            deviceName: deviceName ?? self.deviceName,
            playerState: playerState ?? self.playerState,
            playTime: playTime ?? self.playTime,
            duration: duration ?? self.duration,
            currentQueueIndex: currentQueueIndex ?? self.currentQueueIndex,
            shuffle: shuffle ?? self.shuffle,
            repeatMode: repeatMode ?? self.repeatMode,
            typedData: typedData ?? self.typedData
        )
    }
}
