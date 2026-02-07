import Foundation

/// Focused slice of state for volume/mute. Observe this to reduce re-renders when only volume changes.
public struct VolumeState: Equatable, Sendable {
    public var volume: Int?
    public var mute: Bool?

    public init(volume: Int? = nil, mute: Bool? = nil) {
        self.volume = volume
        self.mute = mute
    }
}

/// Focused slice of state for playback. Observe this to reduce re-renders when only playback changes.
public struct PlaybackStateSlice: Equatable, Sendable {
    public var playerState: String?
    public var playTime: Int?
    public var duration: Int?
    public var currentQueueIndex: Int?
    public var shuffle: Bool?
    public var repeatMode: RepeatMode?

    public init(
        playerState: String? = nil,
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
    public var source: String?
    public var volume: Int?
    public var mute: Bool?
    public var speakerStatus: String?
    public var deviceName: String?
    public var macAddress: String?
    /// Player state: `"playing"`, `"paused"`, etc. (`player:player/data`).
    public var playerState: String?
    /// Playback position in ms (`player:player/data/playTime`).
    public var playTime: Int?
    /// Track duration in ms (`player:player/data` → `status.duration`).
    public var duration: Int?
    /// Zero-based index of current track in queue (`player:player/data` → `trackRoles.value.i32_`).
    public var currentQueueIndex: Int?
    /// Shuffle on/off from settings:/mediaPlayer/playMode.
    public var shuffle: Bool?
    /// Repeat mode from settings:/mediaPlayer/playMode.
    public var repeatMode: RepeatMode?
    /// Raw getData/event payloads by API path. Values are SendableDict (boxed [String: Any]). Internal; use typed accessors (e.g. currentSong) or path-specific APIs.
    var typedData: [APIPath: SendableDict]

    /// Internal: typedData uses internal SendableDict; library constructs state.
    init(
        source: String? = nil,
        volume: Int? = nil,
        mute: Bool? = nil,
        speakerStatus: String? = nil,
        deviceName: String? = nil,
        macAddress: String? = nil,
        playerState: String? = nil,
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
        self.speakerStatus = speakerStatus
        self.deviceName = deviceName
        self.macAddress = macAddress
        self.playerState = playerState
        self.playTime = playTime
        self.duration = duration
        self.currentQueueIndex = currentQueueIndex
        self.shuffle = shuffle
        self.repeatMode = repeatMode
        self.typedData = typedData
    }
}
