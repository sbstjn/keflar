import Foundation

/// Registry for streaming services. Supports multiple concurrent services (Tidal, Spotify, etc.).
/// Register services at initialization; lookup by AudioService.id at runtime.
public actor ServiceRegistry {
    private var services: [String: any StreamingServiceOperations] = [:]

    public init() {}

    /// Register a streaming service. If a service with the same ID exists, it will be replaced.
    public func register(service: any StreamingServiceOperations) async {
        services[service.service.id] = service
    }

    /// Lookup a streaming service by ID. Returns nil if not registered.
    public func service(for id: String) async -> (any StreamingServiceOperations)? {
        services[id]
    }

    /// Lookup a streaming service by AudioService. Convenience for service(for: audioService.id).
    public func service(for audioService: AudioService) async -> (any StreamingServiceOperations)? {
        services[audioService.id]
    }

    /// List all registered services as AudioService instances.
    public func availableServices() async -> [AudioService] {
        services.values.map { $0.service }
    }
}
