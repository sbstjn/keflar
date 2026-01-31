import Foundation

/// One item from getRows(playContext): action or container for the current track.
public struct PlayContextItem: Sendable {
    public let type: PlayContextItemType
    public let path: String
    public let title: String
    public let id: String?

    public init(type: PlayContextItemType, path: String, title: String, id: String?) {
        self.type = type
        self.path = path
        self.title = title
        self.id = id
    }
}

/// Parsed getRows(playContext) response: list of items plus convenience accessors for like/favorite.
public struct PlayContextActions: Sendable {
    public let items: [PlayContextItem]

    public init(items: [PlayContextItem]) {
        self.items = items
    }

    /// True if current track is in service favorites (e.g. TIDAL); derived from presence of favorite.remove action.
    public var isLiked: Bool {
        items.contains { $0.id == tidalActionFavoriteRemove }
    }

    /// Path to invoke to add current track to favorites; nil if already liked or not available.
    public var favoriteInsertPath: String? {
        items.first { $0.id == tidalActionFavoriteInsert }?.path
    }

    /// Path to invoke to remove current track from favorites; nil if not liked or not available.
    public var favoriteRemovePath: String? {
        items.first { $0.id == tidalActionFavoriteRemove }?.path
    }

    /// Path for "Add to playlist" container; getRows(path) for playlist list. Nil if not available.
    public var playlistChoosePath: String? {
        items.first { $0.id == tidalActionPlaylistInsert }?.path
    }
}
