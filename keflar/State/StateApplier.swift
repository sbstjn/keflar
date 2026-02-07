import Foundation
import os

/// Applies getData/event payloads to SpeakerState. Single responsibility: state updates only.
enum StateApplier {
    private typealias Apply = (SpeakerState, [String: Any]) -> SpeakerState

    private struct PathApply {
        let path: String
        let apiPath: APIPath
        let apply: Apply
    }

    private static func extractPlayerDataFields(
        from dict: [String: Any]
    ) -> (playerState: PlayerState?, duration: Int?, currentQueueIndex: Int?) {
        let playerState = (dict["state"] as? String).flatMap { PlayerState(rawValue: $0) }
        let duration = parseDuration(from: dict)
        let currentQueueIndex = parseQueueIndex(from: dict)
        return (playerState, duration, currentQueueIndex)
    }

    private static func extractPlayModeFields(
        from dict: [String: Any]
    ) -> (shuffle: Bool?, repeatMode: RepeatMode?) {
        let mode = parsePlayMode(from: dict)
        return (mode.shuffle, mode.repeatMode)
    }

    /// Path→state apply; immutable config used from single state pipeline. nonisolated(unsafe) until typed Decodable replaces [String: Any].
    private static nonisolated(unsafe) let pathAppliers: [PathApply] = [
        PathApply(path: APIPath.physicalSource.path, apiPath: .physicalSource, apply: { state, d in
            let source = (d["kefPhysicalSource"] as? String).flatMap { PhysicalSource(rawValue: $0) }
            var updated = state.typedData
            updated[.physicalSource] = SendableDict(value: d)
            return state.with(source: source, typedData: updated)
        }),
        PathApply(path: APIPath.volume.path, apiPath: .volume, apply: { state, d in
            let volume = d["i32_"] as? Int
            var updated = state.typedData
            updated[.volume] = SendableDict(value: d)
            return state.with(volume: volume, typedData: updated)
        }),
        PathApply(path: APIPath.deviceName.path, apiPath: .deviceName, apply: { state, d in
            let deviceName = d["string_"] as? String
            var updated = state.typedData
            updated[.deviceName] = SendableDict(value: d)
            return state.with(deviceName: deviceName, typedData: updated)
        }),
        PathApply(path: APIPath.mute.path, apiPath: .mute, apply: { state, d in
            let mute = d["bool_"] as? Bool
            var updated = state.typedData
            updated[.mute] = SendableDict(value: d)
            return state.with(mute: mute, typedData: updated)
        }),
        PathApply(path: playModePath.path, apiPath: playModePath, apply: { state, d in
            let (shuffle, repeatMode) = extractPlayModeFields(from: d)
            var updated = state.typedData
            updated[playModePath] = SendableDict(value: d)
            return state.with(shuffle: shuffle, repeatMode: repeatMode, typedData: updated)
        }),
        PathApply(path: playerDataPath.path, apiPath: playerDataPath, apply: { state, d in
            let (playerState, duration, currentQueueIndex) = extractPlayerDataFields(from: d)
            var updated = state.typedData
            updated[playerDataPath] = SendableDict(value: d)
            return state.with(playerState: playerState, duration: duration, currentQueueIndex: currentQueueIndex, typedData: updated)
        }),
        PathApply(path: playTimePath.path, apiPath: playTimePath, apply: { state, d in
            let playTime = d["i64_"] as? Int
            var updated = state.typedData
            updated[playTimePath] = SendableDict(value: d)
            return state.with(playTime: playTime, typedData: updated)
        }),
    ]

    private static let stateLog = Logger(subsystem: "com.sbstjn.keflar", category: "State")

    static func applyToState(path: String, dict: [String: Any], state: SpeakerState) -> SpeakerState {
        if let spec = pathAppliers.first(where: { $0.path == path }) {
            let newState = spec.apply(state, dict)
            if path == APIPath.physicalSource.path {
                let applied = newState.source?.rawValue ?? "nil"
                let known = newState.source != nil
                stateLog.info("applyToState physicalSource raw=\(String(describing: dict)) applied source=\(applied) known=\(known)")
            }
            return newState
        } else {
            var updated = state.typedData
            updated[APIPath.from(path)] = SendableDict(value: dict)
            return state.with(typedData: updated)
        }
    }
}
