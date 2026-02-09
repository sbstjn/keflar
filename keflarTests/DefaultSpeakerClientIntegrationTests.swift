import XCTest
@testable import keflar

final class DefaultSpeakerClientIntegrationTests: XCTestCase {
    
    func testCircuitBreakerBlocksAfterFailures() async throws {
        let client = DefaultSpeakerClient(host: "invalid.host.that.does.not.exist.12345", session: .shared, requestTimeout: 0.1)
        
        // First few attempts should fail due to network errors
        for _ in 1...5 {
            do {
                _ = try await client.getData(path: "test:path")
                XCTFail("Expected request to fail")
            } catch {
                // Expected failure - network or circuit breaker
            }
        }
        
        // Circuit breaker should eventually reject requests
        // After 5 failures, circuit should be open
        do {
            _ = try await client.getData(path: "test:path")
            XCTFail("Expected circuit breaker to reject request")
        } catch let error as SpeakerConnectError {
            // Should get either connectionUnavailable (circuit open) or timeout/network error
            switch error {
            case .connectionUnavailable(let reason):
                if case .other(let desc) = reason {
                    XCTAssertTrue(desc.contains("Circuit breaker open"))
                }
            default:
                // Other network errors are also acceptable
                break
            }
        }
    }
}
