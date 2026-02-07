import Foundation
import os

/// Applies getData/event payloads to SpeakerState. Single responsibility: state updates only.
enum StateApplier {
    private typealias Apply = (inout SpeakerState, [String: Any]) -> Void

    private struct PathApply {
        let path: String
        let apiPath: APIPath
        let apply: Apply
    }

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

    private static func extractPlayModeFields(
        shuffle: inout Bool?,
        repeatMode: inout RepeatMode?,
        from dict: [String: Any]
    ) {
        let mode = parsePlayMode(from: dict)
        shuffle = mode.shuffle
        repeatMode = mode.repeatMode
    }

    /// Path→state apply; immutable config used from single state pipeline. nonisolated(unsafe) until typed Decodable replaces [String: Any].
    private static nonisolated(unsafe) let pathAppliers: [PathApply] = [
        PathApply(path: APIPath.physicalSource.path, apiPath: .physicalSource, apply: { s, d in s.source = d["kefPhysicalSource"] as? String }),
        PathApply(path: APIPath.volume.path, apiPath: .volume, apply: { s, d in s.volume = d["i32_"] as? Int }),
        PathApply(path: APIPath.speakerStatus.path, apiPath: .speakerStatus, apply: { s, d in s.speakerStatus = d["kefSpeakerStatus"] as? String }),
        PathApply(path: APIPath.deviceName.path, apiPath: .deviceName, apply: { s, d in s.deviceName = d["string_"] as? String }),
        PathApply(path: APIPath.mute.path, apiPath: .mute, apply: { s, d in s.mute = d["bool_"] as? Bool }),
        PathApply(path: APIPath.macAddress.path, apiPath: .macAddress, apply: { s, d in s.macAddress = d["string_"] as? String }),
        PathApply(path: playModePath.path, apiPath: playModePath, apply: { s, d in extractPlayModeFields(shuffle: &s.shuffle, repeatMode: &s.repeatMode, from: d) }),
        PathApply(path: playerDataPath.path, apiPath: playerDataPath, apply: { s, d in
            extractPlayerDataFields(playerState: &s.playerState, duration: &s.duration, currentQueueIndex: &s.currentQueueIndex, from: d)
        }),
        PathApply(path: playTimePath.path, apiPath: playTimePath, apply: { s, d in s.playTime = d["i64_"] as? Int }),
    ]

    private static let stateLog = Logger(subsystem: "com.sbstjn.keflar", category: "State")

    static func applyToState(path: String, dict: [String: Any], state: inout SpeakerState) {
        if let spec = pathAppliers.first(where: { $0.path == path }) {
            spec.apply(&state, dict)
            if path == APIPath.physicalSource.path {
                let applied = state.source ?? "nil"
                let known = applied != "nil" && PhysicalSource(rawValue: applied) != nil
                stateLog.info("applyToState physicalSource raw=\(String(describing: dict)) applied source=\(applied) known=\(known)")
            }
            state.typedData[spec.apiPath] = SendableDict(value: dict)
        } else {
            state.typedData[APIPath.from(path)] = SendableDict(value: dict)
        }
    }
}
