import Foundation

/// Operations common to streaming services (Tidal, Deezer, Amazon). Implementations are service-specific (paths, proxy resolution).
/// Browse (playlists, tracks, mixes, playlist tracks) is documented in SPECS for later unified implementation; not in protocol for now.
public protocol StreamingServiceOperations: Sendable {
    var service: AudioService { get }

    /// Add track to service favorites.
    func addFavorite(trackId: String, returnPath: String?) async throws
    /// Remove track from service favorites.
    func removeFavorite(trackId: String, returnPath: String?) async throws
    /// Whether the track is in the user's favorites.
    func isFavorite(trackId: String) async throws -> Bool
}
