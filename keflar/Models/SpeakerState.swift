import Foundation

/// Accumulated shadow state of the remote device; updated from initial getData and event batches.
///
/// Not `Sendable`: `other` holds `[String: Any]` (API payloads). Use from a single isolation context;
/// the library expects one `Speaker` instance per connection, used from one actor or the main thread.
public struct SpeakerState {
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
    public var other: [String: Any]

    public init(
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
        other: [String: Any] = [:]
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
        self.other = other
    }
}
