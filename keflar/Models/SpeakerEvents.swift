import Foundation

/// Delta: one batch from the event stream. Internal; not part of the public API.
/// Marked `@unchecked Sendable` so it can be passed into actor updateState closures.
struct SpeakerEvents: @unchecked Sendable {
    var source: PhysicalSource?
    var volume: Int?
    var mute: Bool?
    var deviceName: String?
    /// Player state: `.playing`, `.paused`, etc. (`player:player/data`).
    var playerState: PlayerState?
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
        other: [String: Any] = [:]
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
        self.other = other
    }
}