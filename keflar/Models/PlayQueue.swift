import Foundation

/// Sendable wrapper for a track payload passed into queue operations (play next, add to end). Use when calling from a different isolation domain than the playlist manager. The payload must be the full track row (e.g. from getRows or trackRoles); only use data from device API responses (strings, numbers, nested collections).
public struct QueueTrack: @unchecked Sendable {
    public let raw: [String: Any]

    public init(_ raw: [String: Any]) {
        self.raw = raw
    }
}

/// One item in the speaker's play queue (getRows `playlists:pq/getitems`).
public struct PlayQueueItem: Sendable {
    /// Zero-based index in the queue.
    public let index: Int
    /// Queue item id (e.g. "1", "2"); matches path playlists:item/N.
    public let id: String
    public let title: String?
    public let artist: String?
    public let album: String?
    public let coverURL: String?
    public let serviceID: String?

    public init(index: Int, id: String, title: String? = nil, artist: String? = nil, album: String? = nil, coverURL: String? = nil, serviceID: String? = nil) {
        self.index = index
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.coverURL = coverURL
        self.serviceID = serviceID
    }
}

/// Result of fetching the play queue: items in the requested range and total queue length from the API (rowsCount).
public struct PlayQueueResult: Sendable {
    /// Items in the requested index range (may be fewer if queue is shorter).
    public let items: [PlayQueueItem]
    /// Total number of items in the queue (from getRows response rowsCount). Nil if not provided by the API.
    public let totalCount: Int?

    public init(items: [PlayQueueItem], totalCount: Int? = nil) {
        self.items = items
        self.totalCount = totalCount
    }
}

/// Result of fetchPlayQueueWithRaw: parsed items plus raw row dicts for use with playQueueItem(at:track:). Order of rawRows matches result.items.
public struct PlayQueueWithRawResult: @unchecked Sendable {
    public let result: PlayQueueResult
    public let rawRows: [[String: Any]]

    public init(result: PlayQueueResult, rawRows: [[String: Any]]) {
        self.result = result
        self.rawRows = rawRows
    }
}
