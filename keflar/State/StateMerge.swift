import Foundation

private typealias MergeApplier = (SpeakerEvents, inout SpeakerState) -> Void

/// Single source of truth for which event fields are merged into state. Add new fields here only.
/// Safe: immutable config; mergeEvents is called by a single consumer (event poll loop).
private nonisolated(unsafe) let mergeAppliers: [MergeApplier] = [
    { batch, state in if let v = batch.source { state.source = v } },
    { batch, state in if let v = batch.volume { state.volume = v } },
    { batch, state in if let v = batch.mute { state.mute = v } },
    { batch, state in if let v = batch.speakerStatus { state.speakerStatus = v } },
    { batch, state in if let v = batch.deviceName { state.deviceName = v } },
    { batch, state in if let v = batch.playerState { state.playerState = v } },
    { batch, state in if let v = batch.playTime { state.playTime = v } },
    { batch, state in if let v = batch.duration { state.duration = v } },
    { batch, state in if let v = batch.currentQueueIndex { state.currentQueueIndex = v } },
    { batch, state in if let v = batch.shuffle { state.shuffle = v } },
    { batch, state in if let v = batch.repeatMode { state.repeatMode = v } },
]

/// Merge event batch into accumulated speaker state.
func mergeEvents(_ batch: SpeakerEvents, into state: inout SpeakerState) {
    for apply in mergeAppliers { apply(batch, &state) }
    for (k, v) in batch.other { state.other[k] = v }
}
