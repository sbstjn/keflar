import Foundation

/// Streaming audio service supported via Airable proxy (Tidal, Deezer, etc.).
///
/// Public API exposes the service identifier (`id`) and static instances (e.g. `.tidal`).
/// Path properties are `internal` so the library can use them for proxy resolution and playlist/track paths
/// without exposing implementation details in the public API surface.
public struct AudioService: Sendable, Hashable {
    /// Service identifier (e.g., "tidal", "deezer").
    public let id: String
    /// LinkService path for proxy resolution (e.g., "linkService_tidal").
    internal let linkServicePath: String
    /// Path component for playlists (e.g., "tidal/playlist", "deezer/playlist").
    internal let playlistPathComponent: String
    /// Path component for tracks (e.g., "tidal/track", "deezer/track").
    internal let trackPathComponent: String
    /// Path segment for favorites actions (e.g., "tidal" in actions/tidal/track/.../favorites/insert).
    internal let favoritesPathComponent: String

    private init(
        id: String,
        linkServicePath: String,
        playlistPathComponent: String,
        trackPathComponent: String,
        favoritesPathComponent: String
    ) {
        self.id = id
        self.linkServicePath = linkServicePath
        self.playlistPathComponent = playlistPathComponent
        self.trackPathComponent = trackPathComponent
        self.favoritesPathComponent = favoritesPathComponent
    }

    /// Tidal streaming service.
    public static let tidal = AudioService(
        id: "tidal",
        linkServicePath: "linkService_tidal",
        playlistPathComponent: "tidal/playlist",
        trackPathComponent: "tidal/track",
        favoritesPathComponent: "tidal"
    )

    /// Deezer streaming service.
    public static let deezer = AudioService(
        id: "deezer",
        linkServicePath: "linkService_deezer",
        playlistPathComponent: "deezer/playlist",
        trackPathComponent: "deezer/track",
        favoritesPathComponent: "deezer"
    )

    /// Amazon Music streaming service (Airable; metaData.serviceID is "amazonmusic" on device).
    public static let amazon = AudioService(
        id: "amazon",
        linkServicePath: "linkService_amazon",
        playlistPathComponent: "amazon/playlist",
        trackPathComponent: "amazon/track",
        favoritesPathComponent: "amazon"
    )

    /// Resolve AudioService from device serviceID (e.g. currentSong.serviceID). Returns nil for unknown IDs.
    /// Device may send "amazonmusic"; maps to .amazon.
    public static func from(serviceID: String?) -> AudioService? {
        guard let id = serviceID, !id.isEmpty else { return nil }
        switch id {
        case "tidal": return .tidal
        case "deezer": return .deezer
        case "amazon", "amazonmusic": return .amazon
        default: return nil
        }
    }

    /// Normalized service ID for registry lookup. Device may return "amazonmusic"; we use "amazon" in the registry.
    internal static func normalizedServiceID(_ raw: String?) -> String? {
        guard let raw = raw, !raw.isEmpty else { return nil }
        if raw == "amazonmusic" { return "amazon" }
        return raw
    }
}
