import Foundation

/// Parse settings:/mediaPlayer/playMode getData value (playerPlayMode string) into shuffle and repeatMode. Internal for testing.
func parsePlayMode(from dict: [String: Any]) -> (shuffle: Bool, repeatMode: RepeatMode) {
    let raw = dict["playerPlayMode"] as? String ?? "normal"
    switch raw {
    case "shuffle": return (true, .off)
    case "repeatOne": return (false, .one)
    case "repeatAll": return (false, .all)
    default: return (false, .off)
    }
}

/// Parse track duration in ms from player:player/data (status.duration). Internal for testing.
func parseDuration(from playerData: [String: Any]) -> Int? {
    (playerData["status"] as? [String: Any])?["duration"] as? Int
}

/// Parse current queue index (0-based) from player:player/data (trackRoles.value.i32_). Internal for testing.
func parseQueueIndex(from playerData: [String: Any]) -> Int? {
    ((playerData["trackRoles"] as? [String: Any])?["value"] as? [String: Any])?["i32_"] as? Int
}
