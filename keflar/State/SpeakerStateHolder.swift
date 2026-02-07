import Foundation

/// Sendable box for SpeakerState so it can be passed into @MainActor Task from nonisolated callbacks.
struct SendableState: @unchecked Sendable {
    let value: SpeakerState
}

/// Holder for mutable speaker state; actor-isolated so state is only modified from one context.
/// State updates are pushed to the optional continuation (consumed by Speaker on MainActor).
actor SpeakerStateHolder {
    private var state = SpeakerState()
    private let continuation: AsyncStream<SpeakerState>.Continuation?

    init(continuation: AsyncStream<SpeakerState>.Continuation? = nil) {
        self.continuation = continuation
    }

    /// Apply an updater to state and push the new state to the continuation if set.
    func updateState(_ updater: @Sendable (SpeakerState) -> SpeakerState) {
        state = updater(state)
        continuation?.yield(state)
    }

    /// Apply a single path's dict to state (StateApplier) and push. Use for getData-style updates.
    func updateState(path: String, dict: SendableDict) {
        state = StateApplier.applyToState(path: path, dict: dict.value, state: state)
        continuation?.yield(state)
    }

    /// Apply multiple path updates and yield once. Use for initial state fetch to avoid N UI re-renders.
    func updateStateBatch(pathDicts: [(String, SendableDict)]) {
        for (path, dict) in pathDicts {
            state = StateApplier.applyToState(path: path, dict: dict.value, state: state)
        }
        continuation?.yield(state)
    }

    /// Push current state to the continuation. Use after multiple direct updates if not using updateState.
    func notifyStateChanged() {
        continuation?.yield(state)
    }

    /// Read current state (copy).
    func currentState() -> SpeakerState {
        state
    }
}

/// Sendable box for [String: Any] so it can be passed into actor methods and task group.
struct SendableDict: @unchecked Sendable { let value: [String: Any] }

/// Fetch initial state by making parallel getData requests for all initial paths.
func fetchInitialState(client: any SpeakerClientProtocol, stateHolder: SpeakerStateHolder) async {
    var results: [(String, [String: Any])] = []
    await withTaskGroup(of: (String, SendableDict?).self) { group in
        for apiPath in initialGetDataPaths {
            let pathString = apiPath.path
            group.addTask {
                do {
                    let dict = try await client.getData(path: pathString)
                    return (pathString, SendableDict(value: dict))
                } catch {
                    return (pathString, nil)
                }
            }
        }
        for await result in group {
            if let box = result.1 { results.append((result.0, box.value)) }
        }
    }
    let batch = results.map { ($0.0, SendableDict(value: $0.1)) }
    await stateHolder.updateStateBatch(pathDicts: batch)
}
