//
//  BrowseTests.swift
//  keflarTests
//

import Foundation
import Testing
@testable import keflar

struct BrowseTests {

    @Test func parseBrowseResultEmpty() {
        let result = parseBrowseResult(from: [:])
        #expect(result.rows.isEmpty)
        #expect(result.totalCount == nil)
        #expect(result.redirectedFrom == nil)
    }

    @Test func parseBrowseResultWithRowsAndCount() {
        let response: [String: Any] = [
            "rows": [
                ["id": "p1", "path": "airable:https://x.airable.io/pl/1", "title": "Playlist 1", "type": "container"],
                ["title": "Track A", "type": "audio"],
            ],
            "rowsCount": 100,
        ]
        let result = parseBrowseResult(from: response)
        #expect(result.rows.count == 2)
        #expect(result.rows[0].id == "p1")
        #expect(result.rows[0].title == "Playlist 1")
        #expect(result.rows[0].path == "airable:https://x.airable.io/pl/1")
        #expect(result.rows[1].title == "Track A")
        #expect(result.totalCount == 100)
    }

    @Test func parseBrowseRowFromValueWrapper() {
        let row: [String: Any] = [
            "value": [
                "id": "airable://tidal/track/123",
                "path": "airable:https://x.airable.io/id/tidal/track/123",
                "title": "Song",
                "type": "audio",
            ],
        ]
        let parsed = parseBrowseRow(from: row)
        #expect(parsed.id == "airable://tidal/track/123")
        #expect(parsed.title == "Song")
        #expect(parsed.type == "audio")
    }

    @Test func parseBrowseResultWithRedirect() {
        let response: [String: Any] = [
            "rows": [],
            "rowsRedirect": "airable:https://proxy.airable.io/tidal",
        ]
        let result = parseBrowseResult(from: response)
        #expect(result.redirectedFrom == "airable:https://proxy.airable.io/tidal")
    }

    @Test func mockClientBrowseRecordsCallAndReturnsStub() async throws {
        let mock = MockSpeakerClient()
        let row = BrowseRow(id: "pl-1", path: "path/1", title: "My List", type: "container", icon: nil)
        mock.stubBrowse(result: BrowseResult(rows: [row], totalCount: 1, redirectedFrom: nil))
        let result = try await mock.browse(path: "airable:https://x.airable.io/tidal/my/playlists", from: 0, to: 19)
        #expect(result.rows.count == 1)
        #expect(result.rows[0].title == "My List")
        #expect(mock.browseCalls.count == 1)
        #expect(mock.browseCalls[0].path.contains("tidal/my/playlists"))
    }
}
