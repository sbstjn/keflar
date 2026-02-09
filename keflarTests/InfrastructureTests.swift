import XCTest
@testable import keflar

final class InfrastructureTests: XCTestCase {
    
    // MARK: - Circuit Breaker Tests
    
    func testCircuitBreakerAllowsRequestsWhenClosed() async throws {
        let breaker = CircuitBreaker(failureThreshold: 3)
        try await breaker.allowRequest()
        try await breaker.allowRequest()
        try await breaker.allowRequest()
    }
    
    func testCircuitBreakerOpensAfterThresholdFailures() async throws {
        let breaker = CircuitBreaker(failureThreshold: 3, halfOpenRetryDelay: 10)
        
        await breaker.recordFailure()
        await breaker.recordFailure()
        await breaker.recordFailure()
        
        do {
            try await breaker.allowRequest()
            XCTFail("Expected circuit to be open")
        } catch let error as SpeakerConnectError {
            guard case .connectionUnavailable = error else {
                XCTFail("Expected connectionUnavailable error")
                return
            }
        }
    }
    
    func testCircuitBreakerResetsOnSuccess() async throws {
        let breaker = CircuitBreaker(failureThreshold: 3)
        
        await breaker.recordFailure()
        await breaker.recordFailure()
        await breaker.recordSuccess()
        
        try await breaker.allowRequest()
    }
    
    func testCircuitBreakerHalfOpenAfterDelay() async throws {
        let breaker = CircuitBreaker(failureThreshold: 2, halfOpenRetryDelay: 0.1)
        
        await breaker.recordFailure()
        await breaker.recordFailure()
        
        do {
            try await breaker.allowRequest()
            XCTFail("Expected circuit to be open")
        } catch {}
        
        try await Task.sleep(nanoseconds: 150_000_000)
        
        try await breaker.allowRequest()
    }
    
    // MARK: - Retry Policy Tests
    
    func testRetryPolicySucceedsOnFirstAttempt() async throws {
        let policy = RetryPolicy(maxAttempts: 3)
        var attempts = 0
        
        let result = try await policy.execute {
            attempts += 1
            return "success"
        }
        
        XCTAssertEqual(result, "success")
        XCTAssertEqual(attempts, 1)
    }
    
    func testRetryPolicyRetriesOnFailure() async throws {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0.01, jitter: false)
        var attempts = 0
        
        let result = try await policy.execute {
            attempts += 1
            if attempts < 3 {
                throw SpeakerConnectError.invalidURL
            }
            return "success"
        }
        
        XCTAssertEqual(result, "success")
        XCTAssertEqual(attempts, 3)
    }
    
    func testRetryPolicyThrowsAfterMaxAttempts() async throws {
        let policy = RetryPolicy(maxAttempts: 2, baseDelay: 0.01)
        var attempts = 0
        
        do {
            _ = try await policy.execute {
                attempts += 1
                throw SpeakerConnectError.invalidURL
            }
            XCTFail("Expected error to be thrown")
        } catch let error as SpeakerConnectError {
            guard case .invalidURL = error else {
                XCTFail("Expected invalidURL error")
                return
            }
        }
        
        XCTAssertEqual(attempts, 2)
    }
    
    func testRetryPolicyExponentialBackoff() {
        let policy = RetryPolicy(maxAttempts: 5, baseDelay: 1.0, maxDelay: 10.0, jitter: false)
        
        XCTAssertEqual(policy.delay(for: 0), 1.0)
        XCTAssertEqual(policy.delay(for: 1), 2.0)
        XCTAssertEqual(policy.delay(for: 2), 4.0)
        XCTAssertEqual(policy.delay(for: 3), 8.0)
        XCTAssertEqual(policy.delay(for: 4), 10.0)
    }
}
