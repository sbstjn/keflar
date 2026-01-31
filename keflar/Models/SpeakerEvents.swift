import Foundation

/// Delta: one batch from the event stream. Internal; not part of the public API.
/// Not `Sendable`: `other` holds `[String: Any]`. Used only within the library from a single context.
struct SpeakerEvents {
    var source: String?
    var volume: Int?
    var mute: Bool?
    var speakerStatus: String?
    var deviceName: String?
    /// Player state: `"playing"`, `"paused"`, etc. (`player:player/data`).
    var playerState: String?
    /// Playback position in ms (`player:player/data/playTime`).
    var playTime: Int?
    /// Track duration in ms (`player:player/data` → `status.duration`).
    var duration: Int?
    /// Zero-based index of current track in queue (`player:player/data` → `trackRoles.value.i32_`).
    var currentQueueIndex: Int?
    /// Shuffle on/off from settings:/mediaPlayer/playMode.
    var shuffle: Bool?
    /// Repeat mode from settings:/mediaPlayer/playMode.
    var repeatMode: RepeatMode?
    var other: [String: Any]

    init(
        source: String? = nil,
        volume: Int? = nil,
        mute: Bool? = nil,
        speakerStatus: String? = nil,
        deviceName: String? = nil,
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
        self.playerState = playerState
        self.playTime = playTime
        self.duration = duration
        self.currentQueueIndex = currentQueueIndex
        self.shuffle = shuffle
        self.repeatMode = repeatMode
        self.other = other
    }
}