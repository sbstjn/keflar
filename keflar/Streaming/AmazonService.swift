import Foundation
import os

/// Amazon Music implementation of StreamingServiceOperations. Uses Airable proxy paths per SPECS §2.3 (linkService_amazon); track IDs are opaque (e.g. base64), not numeric.
actor AmazonService: StreamingServiceOperations {
    let service = AudioService.amazon
    private let client: any SpeakerClientProtocol
    private let proxyResolver: AirableProxyResolver
    private let stateSynchronizer: StateSynchronizer

    init(client: any SpeakerClientProtocol, proxyResolver: AirableProxyResolver, stateSynchronizer: StateSynchronizer) {
        self.client = client
        self.proxyResolver = proxyResolver
        self.stateSynchronizer = stateSynchronizer
    }

    private func resolveBase() async throws -> String {
        let knownBase = await proxyBaseFromState()
        do {
            let base = try await proxyResolver.resolve(service: service, playlistId: "", knownBase: knownBase)
            Logger.streaming.debug("Amazon resolveBase success")
            return base
        } catch {
            Logger.streaming.error("Amazon resolveBase failed: \(error.localizedDescription, privacy: .private)")
            throw error
        }
    }

    private func proxyBaseFromState() async -> String? {
        let state = await stateSynchronizer.currentState()
        guard let raw = state.typedData[playerDataPath]?.value else { return nil }
        let playerData = PlayerDataDTO(dict: raw)
        return playerData.path.flatMap { proxyBaseFromTrackRolesPath($0) }
    }

    /// Amazon Music does not expose add/remove favorite in the official app; throws so callers can hide favorites UI.
    func addFavorite(trackId: String, returnPath: String?) async throws {
        throw SpeakerConnectError.invalidSource("Amazon Music does not support add to favorites")
    }

    /// Amazon Music does not expose add/remove favorite in the official app; throws so callers can hide favorites UI.
    func removeFavorite(trackId: String, returnPath: String?) async throws {
        throw SpeakerConnectError.invalidSource("Amazon Music does not support remove from favorites")
    }

    /// Amazon Music does not expose favorites in the official app; throws so callers can hide favorites UI.
    func isFavorite(trackId: String) async throws -> Bool {
        throw SpeakerConnectError.invalidSource("Amazon Music does not support favorites")
    }
}
