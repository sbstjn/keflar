import Foundation

/// Queue operations: fetch queue, play playlist, check service config.
actor QueueManager {
    private let playlistManager: any PlaylistManager

    init(playlistManager: any PlaylistManager) {
        self.playlistManager = playlistManager
    }

    func fetchPlayQueue(from startIndex: Int, to endIndex: Int) async throws -> PlayQueueResult {
        try await playlistManager.fetchPlayQueue(from: startIndex, to: endIndex)
    }

    func fetchPlayQueueWithRaw(from startIndex: Int, to endIndex: Int) async throws -> PlayQueueWithRawResult {
        try await playlistManager.fetchPlayQueueWithRaw(from: startIndex, to: endIndex)
    }

    func playPlaylist(service: AudioService, playlistId: String) async throws {
        try await playlistManager.playPlaylist(service: service, playlistId: playlistId)
    }

    func hasServiceConfiguration(_ service: AudioService) async throws -> Bool {
        try await playlistManager.hasServiceConfiguration(service)
    }
}
