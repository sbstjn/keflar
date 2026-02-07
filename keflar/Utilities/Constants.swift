import Foundation

// MARK: - API Paths

internal let playerDataPath = APIPath.playerData
internal let playTimePath = APIPath.playTime
internal let playerControlPath = APIPath.playerControl
internal let playQueuePath = APIPath.playQueue
internal let playModePath = APIPath.playMode

// MARK: - Initial State Paths

internal let initialGetDataPaths: [APIPath] = [
    .volume,
    .physicalSource,
    .speakerStatus,
    .deviceName,
    .mute,
    .macAddress,
    playModePath,
    playerDataPath,
    playTimePath,
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
