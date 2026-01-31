import Foundation

/// Sendable box for SpeakerState so it can be passed into @MainActor Task from nonisolated callbacks.
struct SendableState: @unchecked Sendable {
    let value: SpeakerState
}

/// Holder for mutable speaker state; shared between Speaker and EventPollState.
/// Marked @unchecked Sendable so it can be passed into MainActor.run when creating Speaker.
final class SpeakerStateHolder: @unchecked Sendable {
    var state = SpeakerState()
    
    /// Callback invoked whenever state is updated; used by Speaker to publish changes to @Published property.
    var onStateChange: ((SendableState) -> Void)?
    
    /// Notify observers that state has changed. Call after direct mutations to state properties.
    func notifyStateChanged() {
        onStateChange?(SendableState(value: state))
    }
}

/// Sendable box for [String: Any] so task group can return it. Caller must use only from one context.
private struct SendableDict: @unchecked Sendable { let value: [String: Any] }

/// Fetch initial state by making parallel getData requests for all initial paths.
func fetchInitialState(client: any SpeakerClientProtocol, stateHolder: SpeakerStateHolder) async {
    var results: [(String, [String: Any])] = []
    await withTaskGroup(of: (String, SendableDict?).self) { group in
        for path in initialGetDataPaths {
            group.addTask {
                do {
                    let dict = try await client.getData(path: path)
                    return (path, SendableDict(value: dict))
                } catch {
                    return (path, nil)
                }
            }
        }
        for await result in group {
            if let box = result.1 { results.append((result.0, box.value)) }
        }
    }
    for (path, dict) in results {
        StateReducer.applyToState(path: path, dict: dict, state: &stateHolder.state)
    }
    stateHolder.notifyStateChanged()
}
