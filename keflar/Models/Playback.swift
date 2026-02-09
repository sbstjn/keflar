import Foundation

/// Repeat mode for playback via settings:/mediaPlayer/playMode.
///
/// Use with `Speaker.setRepeat(_:)` to control repeat behavior.
@frozen public enum RepeatMode: Sendable {
    /// No repeat (play through queue once).
    case off
    /// Repeat current song indefinitely.
    case one
    /// Repeat entire queue/playlist.
    case all
}

/// Resource entry for the current track (codec, bitrate, URI). Informational only; speaker selects quality.
public struct TrackResource: Sendable {
    public let mimeType: String?
    public let codec: String?
    public let bitRate: Int?
    public let uri: String?

    public init(mimeType: String? = nil, codec: String? = nil, bitRate: Int? = nil, uri: String? = nil) {
        self.mimeType = mimeType
        self.codec = codec
        self.bitRate = bitRate
        self.uri = uri
    }
}

/// Current song info from `player:player/data` → trackRoles / mediaData.metaData (shadow state).
public struct CurrentSong: Sendable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var albumArtist: String?
    public var coverURL: String?
    public var serviceID: String?
    /// Track duration in ms (`player:player/data` → status.duration).
    public var duration: Int?
    /// Service-specific track ID (e.g. Tidal numeric ID) for favorites and actions. Parsed from trackRoles.id.
    public var trackId: String?
    /// Context path for actions (e.g. add to playlist, favorite). Use with getRows to discover available actions.
    public var contextPath: String?
    /// Quality tiers reported by the service (e.g. ["low", "high", "lossless", "hires"]). Informational only.
    public var availableQualities: [String]?
    /// Available resources (codec, bitrate, URI) for the current track. Informational only.
    public var resources: [TrackResource]?

    public init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        albumArtist: String? = nil,
        coverURL: String? = nil,
        serviceID: String? = nil,
        duration: Int? = nil,
        trackId: String? = nil,
        contextPath: String? = nil,
        availableQualities: [String]? = nil,
        resources: [TrackResource]? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.coverURL = coverURL
        self.serviceID = serviceID
        self.duration = duration
        self.trackId = trackId
        self.contextPath = contextPath
        self.availableQualities = availableQualities
        self.resources = resources
    }
}

/// Audio codec/quality info from `player:player/data` → trackRoles.mediaData.activeResource and metaData.serviceID (shadow state).
/// Equivalent to Python `get_audio_codec_information()`; no extra request — uses cached player data from initial getData and event stream.
public struct AudioCodecInfo: Sendable {
    public var codec: String?
    public var sampleFrequency: Int?
    public var streamSampleRate: Int?
    public var streamChannels: String?
    public var nrAudioChannels: Int?
    public var bitsPerSample: Int?
    public var serviceID: String?

    public init(
        codec: String? = nil,
        sampleFrequency: Int? = nil,
        streamSampleRate: Int? = nil,
        streamChannels: String? = nil,
        nrAudioChannels: Int? = nil,
        bitsPerSample: Int? = nil,
        serviceID: String? = nil
    ) {
        self.codec = codec
        self.sampleFrequency = sampleFrequency
        self.streamSampleRate = streamSampleRate
        self.streamChannels = streamChannels
        self.nrAudioChannels = nrAudioChannels
        self.bitsPerSample = bitsPerSample
        self.serviceID = serviceID
    }
}
