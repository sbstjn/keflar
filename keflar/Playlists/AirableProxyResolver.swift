import Foundation

/// Resolves Airable proxy base URL (e.g. "https://{proxy}.airable.io") for a streaming service. Tries strategies in order and caches by service.
actor AirableProxyResolver {
    private let client: any SpeakerClientProtocol
    private let stateHolder: SpeakerStateHolder
    private var cachedProxies: [AudioService: String] = [:]

    init(client: any SpeakerClientProtocol, stateHolder: SpeakerStateHolder) {
        self.client = client
        self.stateHolder = stateHolder
    }

    /// Resolve proxy base; use knownBase when already available from shadow state to avoid extra calls.
    func resolve(service: AudioService, playlistId: String, knownBase: String?) async throws -> String {
        if let base = knownBase, !base.isEmpty {
            cachedProxies[service] = base
            return base
        }
        if let cached = cachedProxies[service] { return cached }
        if let base = try await resolveViaLinkService(service: service) {
            cachedProxies[service] = base
            return base
        }
        if let base = try await resolveViaShorthand(service: service, playlistId: playlistId) {
            cachedProxies[service] = base
            return base
        }
        if let base = try await resolveViaPlayQueue() {
            cachedProxies[service] = base
            return base
        }
        throw SpeakerConnectError.invalidSource("Airable proxy resolution failed for \(service.id)")
    }

    private func resolveViaLinkService(service: AudioService) async throws -> String? {
        let path = "airable:\(service.linkServicePath)"
        let response = try await client.getRows(path: path, from: 0, to: 19)
        guard let redirect = response["rowsRedirect"] as? String, !redirect.isEmpty else { return nil }
        return proxyBaseFromLinkServiceRedirect(redirect)
    }

    private func resolveViaShorthand(service: AudioService, playlistId: String) async throws -> String? {
        let shorthandPath = "airable:\(service.playlistPathComponent)/\(playlistId)"
        let response = try await client.getRows(path: shorthandPath, from: 0, to: 50)
        if let redirect = response["rowsRedirect"] as? String, !redirect.isEmpty,
           let base = proxyBaseFromTrackRolesPath(redirect) {
            return base
        }
        if let rows = response["rows"] as? [[String: Any]], let first = rows.first,
           let base = proxyBaseFromQueueRow(first) {
            return base
        }
        if let rows = response["rows"] as? [[String: Any]], let first = rows.first {
            let track = (first["value"] as? [String: Any]) ?? (first["itemValue"] as? [String: Any]) ?? first
            if let path = track["path"] as? String, path.contains("airable.io"), let base = proxyBaseFromTrackRolesPath(path) {
                return base
            }
        }
        return nil
    }

    private func resolveViaPlayQueue() async throws -> String? {
        let data = try await client.getData(path: playerDataPath.path)
        await stateHolder.updateState(path: playerDataPath.path, dict: SendableDict(value: data))
        let playerData = PlayerDataDTO(dict: data)
        if let path = playerData.path, let base = proxyBaseFromTrackRolesPath(path) {
            return base
        }
        let response = try await client.getRows(path: playQueuePath.path, from: 0, to: 1)
        guard let rows = response["rows"] as? [[String: Any]], let first = rows.first else { return nil }
        return proxyBaseFromQueueRow(first)
    }
}
