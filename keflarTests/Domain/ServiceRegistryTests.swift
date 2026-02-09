import XCTest
@testable import keflar

/// Tests for ServiceRegistry: registration, lookup, and availability checking.
final class ServiceRegistryTests: XCTestCase {

    // MARK: - register(service:)

    func testRegisterServiceMakesItAvailable() async {
        let registry = ServiceRegistry()
        let mockService = MockStreamingService(audioService: .tidal, title: "Test")
        await registry.register(service: mockService)
        
        let retrieved = await registry.service(for: "tidal")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.service.id, "tidal")
    }

    func testRegisterReplacesExistingServiceWithSameId() async {
        let registry = ServiceRegistry()
        let service1 = MockStreamingService(audioService: .tidal, title: "Original")
        let service2 = MockStreamingService(audioService: .tidal, title: "Replacement")
        
        await registry.register(service: service1)
        await registry.register(service: service2)
        
        let retrieved = await registry.service(for: "tidal") as? MockStreamingService
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.title, "Replacement")
    }

    // MARK: - service(for: String)

    func testServiceForIdReturnsRegisteredService() async {
        let registry = ServiceRegistry()
        let mockService = MockStreamingService(audioService: .tidal)
        await registry.register(service: mockService)
        
        let retrieved = await registry.service(for: "tidal")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.service.id, "tidal")
    }

    func testServiceForIdReturnsNilWhenNotRegistered() async {
        let registry = ServiceRegistry()
        let retrieved = await registry.service(for: "non-existent")
        XCTAssertNil(retrieved)
    }

    // MARK: - service(for: AudioService)

    func testServiceForAudioServiceReturnsRegisteredService() async {
        let registry = ServiceRegistry()
        let mockService = MockStreamingService(audioService: .tidal)
        await registry.register(service: mockService)
        
        let retrieved = await registry.service(for: .tidal)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.service.id, "tidal")
    }

    func testServiceForAudioServiceReturnsNilWhenNotRegistered() async {
        let registry = ServiceRegistry()
        let retrieved = await registry.service(for: .tidal)
        XCTAssertNil(retrieved)
    }

    // MARK: - availableServices()

    func testAvailableServicesReturnsEmptyArrayWhenNoneRegistered() async {
        let registry = ServiceRegistry()
        let services = await registry.availableServices()
        XCTAssertTrue(services.isEmpty)
    }

    func testAvailableServicesReturnsRegisteredService() async {
        let registry = ServiceRegistry()
        let mockService = MockStreamingService(audioService: .tidal)
        await registry.register(service: mockService)
        
        let services = await registry.availableServices()
        XCTAssertEqual(services.count, 1)
        XCTAssertEqual(services.first?.id, "tidal")
    }

    func testAvailableServicesReflectsRegistrationChanges() async {
        let registry = ServiceRegistry()
        var services = await registry.availableServices()
        XCTAssertTrue(services.isEmpty)
        
        let mockService = MockStreamingService(audioService: .tidal)
        await registry.register(service: mockService)
        services = await registry.availableServices()
        XCTAssertEqual(services.count, 1)
    }

    // MARK: - hasService(for:)

    func testHasServiceReturnsTrueForRegisteredService() async {
        let registry = ServiceRegistry()
        let mockService = MockStreamingService(audioService: .tidal)
        await registry.register(service: mockService)
        
        let service = await registry.service(for: "tidal")
        XCTAssertNotNil(service)
    }

    func testHasServiceReturnsFalseForUnregisteredService() async {
        let registry = ServiceRegistry()
        let service = await registry.service(for: "spotify")
        XCTAssertNil(service)
    }

    func testHasServiceReturnsTrueAfterRegistration() async {
        let registry = ServiceRegistry()
        var service = await registry.service(for: "tidal")
        XCTAssertNil(service)
        
        let mockService = MockStreamingService(audioService: .tidal)
        await registry.register(service: mockService)
        service = await registry.service(for: "tidal")
        XCTAssertNotNil(service)
    }

    // MARK: - Concurrent Operations

    func testConcurrentLookups() async {
        let registry = ServiceRegistry()
        let mockService = MockStreamingService(audioService: .tidal)
        await registry.register(service: mockService)
        
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let retrieved = await registry.service(for: "tidal")
                    return retrieved != nil
                }
            }
            
            var allSucceeded = true
            for await result in group {
                if !result {
                    allSucceeded = false
                }
            }
            XCTAssertTrue(allSucceeded)
        }
    }

    // MARK: - Edge Cases

    func testServiceReplacementUpdatesRegistry() async {
        let registry = ServiceRegistry()
        let service1 = MockStreamingService(audioService: .tidal, title: "Original")
        let service2 = MockStreamingService(audioService: .tidal, title: "Replacement")
        
        await registry.register(service: service1)
        await registry.register(service: service2)
        
        let services = await registry.availableServices()
        XCTAssertEqual(services.count, 1)
        
        let retrieved = await registry.service(for: "tidal") as? MockStreamingService
        XCTAssertEqual(retrieved?.title, "Replacement")
    }
}

// MARK: - Mock Streaming Service

struct MockStreamingService: StreamingServiceOperations {
    let service: AudioService
    let title: String

    init(audioService: AudioService, title: String = "Mock Service") {
        self.service = audioService
        self.title = title
    }

    func addFavorite(trackId: String, returnPath: String?) async throws {}

    func removeFavorite(trackId: String, returnPath: String?) async throws {}

    func isFavorite(trackId: String) async throws -> Bool {
        false
    }
}
