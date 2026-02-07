import Foundation

// MARK: - API Path Constants

internal let playerDataPath = "player:player/data"
internal let playTimePath = "player:player/data/playTime"
internal let playerControlPath = "player:player/control"
internal let playQueuePath = "playlists:pq/getitems"
internal let playModePath = "settings:/mediaPlayer/playMode"

// MARK: - Initial State Paths

internal let initialGetDataPaths = [
    "player:volume",
    "settings:/kef/play/physicalSource",
    "settings:/kef/host/speakerStatus",
    "settings:/deviceName",
    "settings:/mediaPlayer/mute",
    "settings:/system/primaryMacAddress",
    playModePath,
    playerDataPath,
]

// MARK: - Timing Constants

/// Queue staleness threshold in seconds. If no poll for this long, recreate the event queue.
internal let queueStaleInterval: TimeInterval = 25

/// Long-poll timeout for event stream. Local LAN + typically foreground app: 2s keeps progress drift small; rendering should use local interpolation at 60fps.
internal let defaultPollTimeout: TimeInterval = 2

/// Minimum consecutive event-poll failures before declaring connection lost (grace period).
internal let connectionGraceMinFailures: Int = 3

/// Minimum duration (seconds) of consecutive failures before declaring connection lost. For local LAN (single app, same room) 6s is enough to avoid false disconnect on brief blips while declaring loss sooner when the speaker is off or WiFi is down.
internal let connectionGraceDuration: TimeInterval = 6