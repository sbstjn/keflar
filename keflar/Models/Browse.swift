import Foundation

/// Result of a browse (getRows) request for streaming content (playlists, tracks, mixes).
public struct BrowseResult: Sendable {
    /// Parsed rows in the requested index range.
    public let rows: [BrowseRow]
    /// Total number of items (from getRows response rowsCount). Nil if not provided.
    public let totalCount: Int?
    /// Path used after following rowsRedirect; nil if no redirect occurred.
    public let redirectedFrom: String?

    public init(rows: [BrowseRow], totalCount: Int? = nil, redirectedFrom: String? = nil) {
        self.rows = rows
        self.totalCount = totalCount
        self.redirectedFrom = redirectedFrom
    }
}

/// A single row from a browse (getRows) response. Common fields are typed (id, path, title, type, icon).
public struct BrowseRow: Sendable {
    public let id: String?
    public let path: String?
    public let title: String?
    public let type: String?
    public let icon: String?

    public init(id: String? = nil, path: String? = nil, title: String? = nil, type: String? = nil, icon: String? = nil) {
        self.id = id
        self.path = path
        self.title = title
        self.type = type
        self.icon = icon
    }
}
