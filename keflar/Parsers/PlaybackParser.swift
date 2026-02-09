import Foundation

/// Parse current song from cached player:player/data. JSON shape cross-checked against pykefcontrol reference. Internal for testing.
func parseCurrentSong(from playerData: [String: Any]) -> CurrentSong {
    let trackRoles = playerData["trackRoles"] as? [String: Any] ?? [:]
    let metaData = (trackRoles["mediaData"] as? [String: Any])?["metaData"] as? [String: Any] ?? [:]
    let artist = metaData["artist"] as? String
    let albumArtist = metaData["albumArtist"] as? String
    let context = trackRoles["context"] as? [String: Any]
    let contextPath = context?["path"] as? String
    let qualityArray = trackRoles["quality"] as? [String]
    let resourcesArray = (trackRoles["mediaData"] as? [String: Any])?["resources"] as? [[String: Any]]
    let resources: [TrackResource]? = resourcesArray?.map { r in
        TrackResource(
            mimeType: r["mimeType"] as? String,
            codec: r["codec"] as? String,
            bitRate: r["bitRate"] as? Int,
            uri: r["uri"] as? String
        )
    }
    let coverURL: String? = (trackRoles["icon"] as? String)
        ?? ((trackRoles["images"] as? [String: Any])?["images"] as? [[String: Any]])?.first?["url"] as? String
    return CurrentSong(
        title: trackRoles["title"] as? String,
        artist: artist,
        album: metaData["album"] as? String,
        albumArtist: albumArtist ?? artist,
        coverURL: coverURL,
        serviceID: metaData["serviceID"] as? String,
        duration: parseDuration(from: playerData),
        trackId: parseTrackId(from: trackRoles["id"]),
        contextPath: contextPath,
        availableQualities: qualityArray,
        resources: resources
    )
}

/// Extract numeric/service track ID from trackRoles.id (e.g. "airable://tidal/track/150850051" -> "150850051").
private func parseTrackId(from idValue: Any?) -> String? {
    guard let id = idValue as? String else { return nil }
    let parts = id.split(separator: "/")
    return parts.last.map(String.init)
}

/// Parse audio codec/quality info from player:player/data. JSON shape cross-checked against pykefcontrol reference. Internal for testing.
func parseAudioCodecInfo(from playerData: [String: Any]) -> AudioCodecInfo {
    let trackRoles = playerData["trackRoles"] as? [String: Any] ?? [:]
    let mediaData = trackRoles["mediaData"] as? [String: Any] ?? [:]
    let activeResource = mediaData["activeResource"] as? [String: Any] ?? [:]
    let metaData = mediaData["metaData"] as? [String: Any] ?? [:]
    return AudioCodecInfo(
        codec: activeResource["codec"] as? String,
        sampleFrequency: activeResource["sampleFrequency"] as? Int,
        streamSampleRate: activeResource["streamSampleRate"] as? Int,
        streamChannels: activeResource["streamChannels"] as? String,
        nrAudioChannels: activeResource["nrAudioChannels"] as? Int,
        bitsPerSample: activeResource["bitsPerSample"] as? Int,
        serviceID: metaData["serviceID"] as? String
    )
}
