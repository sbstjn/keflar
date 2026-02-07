//
//  MockPlaylistManager.swift
//  keflarTests
//

import Foundation
@testable import keflar

/// Mock PlaylistManager for unit tests. Stubs playlist and queue operations.
final class MockPlaylistManager: PlaylistManager, @unchecked Sendable {
    func playPlaylist(service: AudioService, playlistId: String) async throws {}

    func fetchPlayQueue(from startIndex: Int, to endIndex: Int) async throws -> PlayQueueResult {
        PlayQueueResult(items: [], totalCount: nil)
    }

    func hasServiceConfiguration(_ service: AudioService) async throws -> Bool {
        true
    }
}
