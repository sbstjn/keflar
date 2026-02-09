import Foundation
import os

/// Circuit breaker states for protecting against cascading failures.
enum CircuitState {
    case closed      // Normal operation
    case open        // Failing, reject requests
    case halfOpen    // Testing if recovered
}

/// Simple circuit breaker for speaker communication.
actor CircuitBreaker {
    private var state: CircuitState = .closed
    private var failureCount: Int = 0
    private var lastFailureTime: Date?
    private let failureThreshold: Int
    private let timeout: TimeInterval
    private let halfOpenRetryDelay: TimeInterval

    init(failureThreshold: Int = 5, timeout: TimeInterval = 30, halfOpenRetryDelay: TimeInterval = 5) {
        self.failureThreshold = failureThreshold
        self.timeout = timeout
        self.halfOpenRetryDelay = halfOpenRetryDelay
    }

    /// Check if operation should be allowed. Throws if circuit is open.
    func allowRequest() throws {
        switch state {
        case .closed:
            return
        case .open:
            if let last = lastFailureTime, Date().timeIntervalSince(last) > halfOpenRetryDelay {
                state = .halfOpen
                Logger.resilience.info("circuit breaker open→halfOpen")
                return
            }
            throw SpeakerConnectError.connectionUnavailable(.other(description: "Circuit breaker open"))
        case .halfOpen:
            return
        }
    }

    /// Record successful operation.
    func recordSuccess() {
        if state == .halfOpen {
            state = .closed
            Logger.resilience.info("circuit breaker halfOpen→closed")
        }
        failureCount = 0
        lastFailureTime = nil
    }

    /// Record failed operation.
    func recordFailure() {
        failureCount += 1
        lastFailureTime = Date()

        if failureCount >= failureThreshold {
            state = .open
            Logger.resilience.info("circuit breaker closed→open failureCount=\(self.failureCount)")
        }
    }

    /// Reset circuit to closed state.
    func reset() {
        state = .closed
        failureCount = 0
        lastFailureTime = nil
    }
}
