import Foundation
import os

/// Tidal implementation of StreamingServiceOperations. Uses Airable proxy paths and favorite action URLs.
actor TidalService: StreamingServiceOperations {
    let service = AudioService.tidal
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
            Logger.streaming.debug("Tidal resolveBase success")
            return base
        } catch {
            Logger.streaming.error("Tidal resolveBase failed: \(error.localizedDescription, privacy: .private)")
            throw error
        }
    }

    private func proxyBaseFromState() async -> String? {
        let state = await stateSynchronizer.currentState()
        guard let raw = state.typedData[playerDataPath]?.value else { return nil }
        let playerData = PlayerDataDTO(dict: raw)
        return playerData.path.flatMap { proxyBaseFromTrackRolesPath($0) }
    }

    func addFavorite(trackId: String, returnPath: String?) async throws {
        let base = try await resolveBase()
        let r = returnPath ?? "%2Ftidal%2Fmy%2Ftracks"
        let path = "airable:action:\(base)/actions/\(service.favoritesPathComponent)/track/\(trackId)/favorites/insert?r=\(r)"
        try await client.setDataWithBody(path: path, role: "activate", value: true)
    }

    func removeFavorite(trackId: String, returnPath: String?) async throws {
        let base = try await resolveBase()
        let r = returnPath ?? "%2Ftidal%2Fmy%2Ftracks"
        let path = "airable:action:\(base)/actions/\(service.favoritesPathComponent)/track/\(trackId)/favorites/remove?r=\(r)"
        try await client.setDataWithBody(path: path, role: "activate", value: true)
    }

    /// May perform multiple getRows (library + context). Best used for current or recently browsed context; can be slow for large libraries.
    func isFavorite(trackId: String) async throws -> Bool {
        let base = try await resolveBase()
        let path = "airable:\(base)/tidal/my/tracks"
        var response = try await client.getRows(path: path, from: 0, to: 99)
        if let redirect = response["rowsRedirect"] as? String, !redirect.isEmpty {
            response = try await client.getRows(path: redirect, from: 0, to: 99)
        }
        guard let rows = response["rows"] as? [[String: Any]] else { return false }
        for row in rows {
            let candidate = (row["value"] as? [String: Any]) ?? (row["itemValue"] as? [String: Any]) ?? row
            let rowId = (candidate["id"] as? String) ?? (row["id"] as? String) ?? ""
            let rowTrackId = rowId.split(separator: "/").last.map(String.init)
            guard rowTrackId == trackId else { continue }
            let context = (candidate["context"] as? [String: Any]) ?? (row["context"] as? [String: Any])
            guard let contextPath = context?["path"] as? String else { return false }
            let contextResponse = try await client.getRows(path: contextPath, from: 0, to: 19)
            guard let contextRows = contextResponse["rows"] as? [[String: Any]] else { return false }
            for ctxRow in contextRows {
                let ctxId = (ctxRow["id"] as? String) ?? ""
                let ctxPath = (ctxRow["path"] as? String) ?? ""
                if ctxId.contains("favorite.remove") || ctxPath.contains("favorites/remove") {
                    return true
                }
            }
            return false
        }
        return false
    }
}
