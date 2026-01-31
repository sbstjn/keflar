import Foundation

// Single path→state/events mapping. One table drives both applyToState and parseEvents. Internal for testing.
enum StateReducer {
    private typealias StateApply = (inout SpeakerState, [String: Any]) -> Void
    private typealias EventApply = (inout SpeakerEvents, [String: Any]) -> Void

    private struct PathSpec {
        let path: String
        let stateApply: StateApply
        let eventApply: EventApply
    }

    /// Extract player data fields (playerState, duration, currentQueueIndex) from player:player/data dict.
    private static func extractPlayerDataFields(
        playerState: inout String?,
        duration: inout Int?,
        currentQueueIndex: inout Int?,
        from dict: [String: Any]
    ) {
        playerState = dict["state"] as? String
        duration = parseDuration(from: dict)
        currentQueueIndex = parseQueueIndex(from: dict)
    }

    /// Extract play mode fields (shuffle, repeatMode) from settings:/mediaPlayer/playMode dict.
    private static func extractPlayModeFields(
        shuffle: inout Bool?,
        repeatMode: inout RepeatMode?,
        from dict: [String: Any]
    ) {
        let mode = parsePlayMode(from: dict)
        shuffle = mode.shuffle
        repeatMode = mode.repeatMode
    }

    /// Path→payload key mapping per device API; cross-checked against pykefcontrol. Reducer is used from a single event/state pipeline.
    private static nonisolated(unsafe) let pathSpecs: [PathSpec] = [
        PathSpec(path: "settings:/kef/play/physicalSource", stateApply: { s, d in s.source = d["kefPhysicalSource"] as? String }, eventApply: { e, d in e.source = d["kefPhysicalSource"] as? String }),
        PathSpec(path: "player:volume", stateApply: { s, d in s.volume = d["i32_"] as? Int }, eventApply: { e, d in e.volume = d["i32_"] as? Int }),
        PathSpec(path: "settings:/kef/host/speakerStatus", stateApply: { s, d in s.speakerStatus = d["kefSpeakerStatus"] as? String }, eventApply: { e, d in e.speakerStatus = d["kefSpeakerStatus"] as? String }),
        PathSpec(path: "settings:/deviceName", stateApply: { s, d in s.deviceName = d["string_"] as? String }, eventApply: { e, d in e.deviceName = d["string_"] as? String }),
        PathSpec(path: "settings:/mediaPlayer/mute", stateApply: { s, d in s.mute = d["bool_"] as? Bool }, eventApply: { e, d in e.mute = d["bool_"] as? Bool }),
        PathSpec(path: "settings:/system/primaryMacAddress", stateApply: { s, d in s.macAddress = d["string_"] as? String }, eventApply: { e, _ in }),
        PathSpec(
            path: playModePath,
            stateApply: { s, d in extractPlayModeFields(shuffle: &s.shuffle, repeatMode: &s.repeatMode, from: d) },
            eventApply: { e, d in extractPlayModeFields(shuffle: &e.shuffle, repeatMode: &e.repeatMode, from: d) }
        ),
        PathSpec(
            path: playerDataPath,
            stateApply: { s, d in
                extractPlayerDataFields(playerState: &s.playerState, duration: &s.duration, currentQueueIndex: &s.currentQueueIndex, from: d)
                s.other[playerDataPath] = d
            },
            eventApply: { e, d in
                extractPlayerDataFields(playerState: &e.playerState, duration: &e.duration, currentQueueIndex: &e.currentQueueIndex, from: d)
            }
        ),
        PathSpec(path: playTimePath, stateApply: { s, d in s.playTime = d["i64_"] as? Int }, eventApply: { e, d in e.playTime = d["i64_"] as? Int }),
    ]

    static func applyToState(path: String, dict: [String: Any], state: inout SpeakerState) {
        if let spec = pathSpecs.first(where: { $0.path == path }) {
            spec.stateApply(&state, dict)
        } else {
            state.other[path] = dict
        }
    }

    static func parseEvents(pathToItemValue: [String: Any]) -> SpeakerEvents {
        var events = SpeakerEvents()
        var other: [String: Any] = [:]
        for (path, itemValue) in pathToItemValue {
            guard let dict = itemValue as? [String: Any] else {
                other[path] = itemValue
                continue
            }
            if let spec = pathSpecs.first(where: { $0.path == path }) {
                spec.eventApply(&events, dict)
                if spec.path == playerDataPath { other[playerDataPath] = dict }
            } else {
                other[path] = dict
            }
        }
        events.other = other
        return events
    }
}
