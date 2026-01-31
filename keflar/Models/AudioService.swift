import Foundation

/// Streaming audio service supported via Airable proxy (Tidal, Spotify, Qobuz, etc.).
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
