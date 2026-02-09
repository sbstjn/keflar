import Foundation

/// Coordinates all state updates: from API calls, event batches, and direct modifications.
/// Single source of truth for state update logic.
actor StateSynchronizer {
    private var state = SpeakerState()
    private let continuation: AsyncStream<SpeakerState>.Continuation?

    init(continuation: AsyncStream<SpeakerState>.Continuation? = nil) {
        self.continuation = continuation
    }

    /// Apply a single path's dict to state (uses StateApplier) and yield.
    func applyUpdate(path: String, dict: [String: Any]) {
        state = StateApplier.applyToState(path: path, dict: dict, state: state)
        continuation?.yield(state)
    }

    /// Apply multiple path updates in batch and yield once.
    func applyBatch(pathDicts: [(String, [String: Any])]) {
        for (path, dict) in pathDicts {
            state = StateApplier.applyToState(path: path, dict: dict, state: state)
        }
        continuation?.yield(state)
    }

    /// Apply event batch (uses mergeEvents from StateMerge) and yield.
    func processEvents(_ events: SpeakerEvents) {
        state = mergeEvents(events, into: state)
        continuation?.yield(state)
    }

    /// Apply custom state updater and yield.
    func updateState(_ updater: @Sendable (SpeakerState) -> SpeakerState) {
        state = updater(state)
        continuation?.yield(state)
    }

    /// Get current state snapshot.
    func currentState() -> SpeakerState {
        state
    }

    /// Observe state changes as AsyncStream.
    func stateStream() -> AsyncStream<SpeakerState> {
        AsyncStream { continuation in
            continuation.yield(state)
        }
    }
}
