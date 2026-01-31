import Foundation

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
