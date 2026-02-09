import Foundation
import os

/// Retry policy with exponential backoff.
struct RetryPolicy: Sendable {
    let maxAttempts: Int
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval
    let jitter: Bool

    init(maxAttempts: Int = 3, baseDelay: TimeInterval = 0.5, maxDelay: TimeInterval = 5.0, jitter: Bool = true) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.jitter = jitter
    }

    /// Calculate delay for given attempt (0-indexed).
    func delay(for attempt: Int) -> TimeInterval {
        let exponential = baseDelay * pow(2.0, Double(attempt))
        let capped = min(exponential, maxDelay)
        if jitter {
            let jitterAmount = capped * 0.25
            return capped + Double.random(in: -jitterAmount...jitterAmount)
        }
        return capped
    }

    /// Execute operation with retry.
    func execute<T>(_ operation: () async throws -> T) async throws -> T {
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt < maxAttempts - 1 {
                    let delayTime = delay(for: attempt)
                    Logger.resilience.debug("retry attempt=\(attempt + 1) delaySeconds=\(delayTime)")
                    try? await Task.sleep(nanoseconds: UInt64(delayTime * 1_000_000_000))
                }
            }
        }
        throw lastError ?? SpeakerConnectError.connectionUnavailable(.other(description: "Max retries exceeded"))
    }
}
