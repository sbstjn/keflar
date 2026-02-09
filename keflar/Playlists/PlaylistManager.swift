import Foundation
import os

// MARK: - Protocol

/// Playlist and queue operations: play service playlist, fetch queue, add track to queue, check service configuration. Sendable for use across isolation boundaries.
protocol PlaylistManager: Sendable {
    func playPlaylist(service: AudioService, playlistId: String) async throws
    func fetchPlayQueue(from startIndex: Int, to endIndex: Int) async throws -> PlayQueueResult
    /// Same as fetchPlayQueue but also returns raw row dicts for use with playQueueItem(at:track:). Order of rawRows matches result.items.
    func fetchPlayQueueWithRaw(from startIndex: Int, to endIndex: Int) async throws -> PlayQueueWithRawResult
    /// Add one track to play immediately after the current track. `track` must be the full track row (e.g. from fetchPlayQueue rows or getRows); path must contain `/track`.
    func playNext(track: QueueTrack) async throws
    /// Append one track to the end of the play queue. `track` must be the full track row (e.g. from fetchPlayQueue rows or getRows); path must contain `/track`.
    func addToEndOfQueue(track: QueueTrack) async throws
    /// Start playback at the given queue index. `track` must be the full queue row from fetchPlayQueue for that index (path e.g. playlists:item/N).
    func playQueueItem(at index: Int, track: QueueTrack) async throws
    func hasServiceConfiguration(_ service: AudioService) async throws -> Bool
}

// MARK: - Default Implementation

actor DefaultPlaylistManager: PlaylistManager {
    private let client: any SpeakerClientProtocol
    private let proxyResolver: AirableProxyResolver
    private let stateSynchronizer: StateSynchronizer

    init(client: any SpeakerClientProtocol, proxyResolver: AirableProxyResolver, stateSynchronizer: StateSynchronizer) {
        self.client = client
        self.proxyResolver = proxyResolver
        self.stateSynchronizer = stateSynchronizer
    }

    func playPlaylist(service: AudioService, playlistId: String) async throws {
        Logger.streaming.debug("playPlaylist start service=\(service.id) playlistId=\(playlistId, privacy: .private)")
        do {
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
            try await sendPlayAtQueueIndex(0, trackRoles: firstTrack)
            Logger.streaming.debug("playPlaylist success service=\(service.id)")
        } catch {
            Logger.streaming.error("playPlaylist failed: \(error.localizedDescription, privacy: .private)")
            throw error
        }
    }

    func fetchPlayQueue(from startIndex: Int, to endIndex: Int) async throws -> PlayQueueResult {
        let response = try await client.getRows(path: playQueuePath.path, from: startIndex, to: endIndex)
        return parsePlayQueue(from: response)
    }

    func fetchPlayQueueWithRaw(from startIndex: Int, to endIndex: Int) async throws -> PlayQueueWithRawResult {
        let response = try await client.getRows(path: playQueuePath.path, from: startIndex, to: endIndex)
        let rawRows = response["rows"] as? [[String: Any]] ?? []
        return PlayQueueWithRawResult(result: parsePlayQueue(from: response), rawRows: rawRows)
    }

    func playNext(track: QueueTrack) async throws {
        try await addTrackToQueue(track, mode: "afterCurrent")
    }

    func addToEndOfQueue(track: QueueTrack) async throws {
        try await addTrackToQueue(track, mode: "append")
    }

    func playQueueItem(at index: Int, track: QueueTrack) async throws {
        guard index >= 0 else {
            throw SpeakerConnectError.invalidResponseStructure
        }
        try await sendPlayAtQueueIndex(index, trackRoles: track.raw)
    }

    private func sendPlayAtQueueIndex(_ index: Int, trackRoles: [String: Any]) async throws {
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
            "trackRoles": trackRoles,
            "index": index,
            "mediaRoles": queueMediaRoles,
        ]
        try await client.setDataWithBody(path: APIPath.playerControl.path, role: "activate", value: AnyEncodableValue(value: playValue))
    }

    private func addTrackToQueue(_ track: QueueTrack, mode: String) async throws {
        guard let resolved = resolveTrackFromRow(track.raw) else {
            throw SpeakerConnectError.invalidResponseStructure
        }
        let items: [[String: Any]] = [["nsdkRoles": try nsdkRolesJSONString(from: resolved)]]
        try await client.setDataWithBody(path: APIPath.plAddExternalItems.path, role: "activate", value: AnyEncodableValue(value: ["mode": mode, "plid": "0", "items": items]))
    }

    func hasServiceConfiguration(_ service: AudioService) async throws -> Bool {
        let path = "airable:\(service.linkServicePath)"
        let response = try await client.getRows(path: path, from: 0, to: 19)
        guard let redirect = response["rowsRedirect"] as? String, !redirect.isEmpty else { return false }
        return proxyBaseFromLinkServiceRedirect(redirect) != nil
    }

    private func proxyBaseFromState() async -> String? {
        let state = await stateSynchronizer.currentState()
        guard let raw = state.typedData[playerDataPath]?.value else { return nil }
        let playerData = PlayerDataDTO(dict: raw)
        return playerData.path.flatMap { proxyBaseFromTrackRolesPath($0) }
    }
}
