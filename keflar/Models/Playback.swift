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

    public init(title: String? = nil, artist: String? = nil, album: String? = nil, albumArtist: String? = nil, coverURL: String? = nil, serviceID: String? = nil, duration: Int? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.coverURL = coverURL
        self.serviceID = serviceID
        self.duration = duration
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

    public init(codec: String? = nil, sampleFrequency: Int? = nil, streamSampleRate: Int? = nil, streamChannels: String? = nil, nrAudioChannels: Int? = nil, bitsPerSample: Int? = nil, serviceID: String? = nil) {
        self.codec = codec
        self.sampleFrequency = sampleFrequency
        self.streamSampleRate = streamSampleRate
        self.streamChannels = streamChannels
        self.nrAudioChannels = nrAudioChannels
        self.bitsPerSample = bitsPerSample
        self.serviceID = serviceID
    }
}
