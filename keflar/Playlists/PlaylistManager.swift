import Foundation

// MARK: - Protocol

/// Playlist and queue operations: play service playlist, fetch queue, check service configuration. Sendable for use across isolation boundaries.
protocol PlaylistManager: Sendable {
    func playPlaylist(service: AudioService, playlistId: String) async throws
    func fetchPlayQueue(from startIndex: Int, to endIndex: Int) async throws -> PlayQueueResult
    func hasServiceConfiguration(_ service: AudioService) async throws -> Bool
}

// MARK: - Default Implementation

actor DefaultPlaylistManager: PlaylistManager {
    private let client: any SpeakerClientProtocol
    private let proxyResolver: AirableProxyResolver
    private let stateHolder: SpeakerStateHolder

    init(client: any SpeakerClientProtocol, proxyResolver: AirableProxyResolver, stateHolder: SpeakerStateHolder) {
        self.client = client
        self.proxyResolver = proxyResolver
        self.stateHolder = stateHolder
    }

    func playPlaylist(service: AudioService, playlistId: String) async throws {
        let knownBase = await proxyBaseFromState()
        let base = try await proxyResolver.resolve(service: service, playlistId: playlistId, knownBase: knownBase)
        let playlistPath = "airable:\(base)/id/\(service.playlistPathComponent)/\(playlistId)"
        var response = try await client.getRows(path: playlistPath, from: 0, to: 50)
        if let redirect = response["rowsRedirect"] as? String, !redirect.isEmpty {
            response = try await client.getRows(path: redirect, from: 0, to: 50)
        }
        guard let rows = response["rows"] as? [[String: Any]], !rows.isEmpty else {
            throw SpeakerConnectError.invalidResponseStructure
        }
        let tracks = rows.compactMap { resolveTrackFromRow($0) }
        guard !tracks.isEmpty else {
            throw SpeakerConnectError.invalidResponseStructure
        }
        try await client.setDataWithBody(path: APIPath.plClear.path, role: "activate", value: ClearQueueRequest())
        let items: [[String: Any]] = try tracks.map { track in
            ["nsdkRoles": try nsdkRolesJSONString(from: track)]
        }
        try await client.setDataWithBody(path: APIPath.plAddExternalItems.path, role: "activate", value: AnyEncodableValue(value: ["mode": "append", "plid": "0", "items": items]))
        guard let firstTrack = resolveFirstTrack(from: rows) else {
            throw SpeakerConnectError.invalidResponseStructure
        }
        let queueMediaRoles: [String: Any] = [
            "type": "container",
            "path": "playlists:pq/getitems",
            "containerType": "none",
            "title": "PlayQueue tracks",
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "mediaData": ["metaData": ["playLogicPath": "playlists:playlogic"]],
        ]
        let playValue: [String: Any] = [
            "control": "play",
            "type": "itemInContainer",
            "trackRoles": firstTrack,
            "index": 0,
            "mediaRoles": queueMediaRoles,
        ]
        try await client.setDataWithBody(path: APIPath.playerControl.path, role: "activate", value: AnyEncodableValue(value: playValue))
    }

    func fetchPlayQueue(from startIndex: Int, to endIndex: Int) async throws -> PlayQueueResult {
        let response = try await client.getRows(path: playQueuePath.path, from: startIndex, to: endIndex)
        return parsePlayQueue(from: response)
    }

    func hasServiceConfiguration(_ service: AudioService) async throws -> Bool {
        let path = "airable:\(service.linkServicePath)"
        let response = try await client.getRows(path: path, from: 0, to: 19)
        guard let redirect = response["rowsRedirect"] as? String, !redirect.isEmpty else { return false }
        return proxyBaseFromLinkServiceRedirect(redirect) != nil
    }

    private func proxyBaseFromState() async -> String? {
        let state = await stateHolder.currentState()
        guard let raw = state.typedData[playerDataPath]?.value else { return nil }
        let playerData = PlayerDataDTO(dict: raw)
        return playerData.path.flatMap { proxyBaseFromTrackRolesPath($0) }
    }
}
