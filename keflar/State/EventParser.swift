import Foundation

/// Parses event poll path→itemValue into SpeakerEvents. Single responsibility: event parsing only.
enum EventParser {
    private typealias Apply = (inout SpeakerEvents, [String: Any]) -> Void

    private static func extractPlayerDataFields(
        playerState: inout PlayerState?,
        duration: inout Int?,
        currentQueueIndex: inout Int?,
        from dict: [String: Any]
    ) {
        if let stateString = dict["state"] as? String {
            playerState = PlayerState(rawValue: stateString)
        }
        duration = parseDuration(from: dict)
        currentQueueIndex = parseQueueIndex(from: dict)
    }

    private static func extractPlayModeFields(
        shuffle: inout Bool?,
        repeatMode: inout RepeatMode?,
        from dict: [String: Any]
    ) {
        let mode = parsePlayMode(from: dict)
        shuffle = mode.shuffle
        repeatMode = mode.repeatMode
    }

    /// Path→event apply; immutable config used from single event pipeline. nonisolated(unsafe) until typed Decodable replaces [String: Any].
    private static nonisolated(unsafe) let pathApply: [(String, Apply)] = [
        (APIPath.physicalSource.path, { e, d in
            if let sourceString = d["kefPhysicalSource"] as? String {
                e.source = PhysicalSource(rawValue: sourceString)
            }
        }),
        (APIPath.volume.path, { e, d in e.volume = d["i32_"] as? Int }),
        (APIPath.deviceName.path, { e, d in e.deviceName = d["string_"] as? String }),
        (APIPath.mute.path, { e, d in
            e.mute = (d["bool_"] as? Bool) ?? (d["bool_"] as? Int).map { $0 != 0 } ?? (d["i32_"] as? Int).map { $0 != 0 }
        }),
        (playModePath.path, { e, d in extractPlayModeFields(shuffle: &e.shuffle, repeatMode: &e.repeatMode, from: d) }),
        (playerDataPath.path, { e, d in
            extractPlayerDataFields(playerState: &e.playerState, duration: &e.duration, currentQueueIndex: &e.currentQueueIndex, from: d)
        }),
        (playTimePath.path, { e, d in e.playTime = d["i64_"] as? Int }),
    ]

    static func parseEvents(pathToItemValue: [String: Any]) -> SpeakerEvents {
        var events = SpeakerEvents()
        var other: [String: Any] = [:]
        for (path, itemValue) in pathToItemValue {
            guard let dict = itemValue as? [String: Any] else {
                other[path] = itemValue
                continue
            }
            if let apply = pathApply.first(where: { $0.0 == path })?.1 {
                apply(&events, dict)
                if path == playerDataPath.path { other[playerDataPath.path] = dict }
            } else {
                other[path] = dict
            }
        }
        events.other = other
        return events
    }
}
