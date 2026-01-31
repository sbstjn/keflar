import Foundation

/// Streaming audio service supported via Airable proxy (Tidal, Spotify, Qobuz, etc.).
///
/// Public API exposes the service identifier (`id`) and static instances (e.g. `.tidal`). Path properties are `internal` so the library can use them for proxy resolution and playlist/track paths without exposing implementation details in the public API surface.
public struct AudioService: Sendable, Hashable {
    /// Service identifier (e.g., "tidal", "spotify").
    public let id: String
    /// LinkService path for proxy resolution (e.g., "linkService_tidal").
    internal let linkServicePath: String
    /// Path component for playlists (e.g., "tidal/playlist", "spotify/playlist").
    internal let playlistPathComponent: String
    /// Path component for tracks (e.g., "tidal/track", "spotify/track").
    internal let trackPathComponent: String

    private init(id: String, linkServicePath: String, playlistPathComponent: String, trackPathComponent: String) {
        self.id = id
        self.linkServicePath = linkServicePath
        self.playlistPathComponent = playlistPathComponent
        self.trackPathComponent = trackPathComponent
    }

    /// Tidal streaming service.
    public static let tidal = AudioService(
        id: "tidal",
        linkServicePath: "linkService_tidal",
        playlistPathComponent: "tidal/playlist",
        trackPathComponent: "tidal/track"
    )
}
