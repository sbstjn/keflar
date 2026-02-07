import Foundation

// MARK: - API Path Constants

internal let playerDataPath = "player:player/data"
internal let playTimePath = "player:player/data/playTime"
internal let playerControlPath = "player:player/control"
internal let playQueuePath = "playlists:pq/getitems"
internal let playModePath = "settings:/mediaPlayer/playMode"

// MARK: - Play Context (Tidal action IDs)

internal let tidalActionFavoriteRemove = "airable://tidal/action/favorite.remove"
internal let tidalActionFavoriteInsert = "airable://tidal/action/favorite.insert"
internal let tidalActionPlaylistInsert = "airable://tidal/action/playlist.insert"

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

/// Delay before refetching play context after activate (like/unlike); device may apply asynchronously.
internal let playContextRefetchDelayAfterActivate: TimeInterval = 0.4
