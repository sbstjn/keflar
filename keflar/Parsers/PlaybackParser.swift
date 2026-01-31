import Foundation

/// Parse current song from cached player:player/data. JSON shape cross-checked against pykefcontrol reference. Internal for testing.
func parseCurrentSong(from playerData: [String: Any]) -> CurrentSong {
    let trackRoles = playerData["trackRoles"] as? [String: Any] ?? [:]
    let metaData = (trackRoles["mediaData"] as? [String: Any])?["metaData"] as? [String: Any] ?? [:]
    let artist = metaData["artist"] as? String
    let albumArtist = metaData["albumArtist"] as? String
    return CurrentSong(
        title: trackRoles["title"] as? String,
        artist: artist,
        album: metaData["album"] as? String,
        albumArtist: albumArtist ?? artist,
        coverURL: trackRoles["icon"] as? String,
        serviceID: metaData["serviceID"] as? String,
        duration: parseDuration(from: playerData)
    )
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
