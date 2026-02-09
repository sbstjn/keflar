import Foundation
@testable import keflar

/// Sendable state holder for tests. Allows state updates while maintaining thread-safety.
final class TestStateHolder: @unchecked Sendable {
    var state: SpeakerState
    
    init(state: SpeakerState) {
        self.state = state
    }
    
    @Sendable func getState() -> SpeakerState {
        state
    }
}
