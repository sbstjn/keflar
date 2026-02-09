import Foundation
import os

private let mergeLog = Logger(subsystem: "com.sbstjn.keflar", category: "State")

/// Known physical sources for logging.
private let knownSources: Set<PhysicalSource> = Set(PhysicalSource.allCases)

/// Merge event batch into accumulated speaker state, returning new state.
func mergeEvents(_ batch: SpeakerEvents, into state: SpeakerState) -> SpeakerState {
    let oldSource = state.source
    
    var newTypedData = state.typedData
    for (k, v) in batch.other {
        newTypedData[APIPath.from(k)] = SendableDict(value: (v as? [String: Any]) ?? [:])
    }
    
    let newState = SpeakerState(
        source: batch.source ?? state.source,
        volume: batch.volume ?? state.volume,
        mute: batch.mute ?? state.mute,
        deviceName: batch.deviceName ?? state.deviceName,
        playerState: batch.playerState ?? state.playerState,
        playTime: batch.playTime ?? state.playTime,
        duration: batch.duration ?? state.duration,
        currentQueueIndex: batch.currentQueueIndex ?? state.currentQueueIndex,
        shuffle: batch.shuffle ?? state.shuffle,
        repeatMode: batch.repeatMode ?? state.repeatMode,
        typedData: newTypedData
    )
    
    if let newSource = batch.source, newSource != oldSource {
        let known = knownSources.contains(newSource)
        mergeLog.info("source switched from \(oldSource?.rawValue ?? "nil") to \(newSource.rawValue) known=\(known)")
    }
    
    return newState
}
