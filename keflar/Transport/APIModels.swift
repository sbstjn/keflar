import Foundation

// MARK: - getData Response Types (Decodable)

/// Response for player:player/data.
public struct PlayerDataResponse: Codable, Sendable {
    public let state: String?
    public let status: PlayerDataStatus?
    public let trackRoles: TrackRoles?
    public let serviceID: String?

    public struct PlayerDataStatus: Codable, Sendable {
        public let duration: Int?
        public let position: Int?
    }

    public struct TrackRoles: Codable, Sendable {
        public let path: String?
        public let title: String?
        public let icon: String?
        public let mediaData: MediaData?
        public let value: IndexValue?
    }

    public struct MediaData: Codable, Sendable {
        public let metaData: MetaData?
        public let activeResource: ActiveResource?
    }

    public struct MetaData: Codable, Sendable {
        public let title: String?
        public let artist: String?
        public let album: String?
        public let albumArtist: String?
        public let serviceID: String?
    }

    public struct ActiveResource: Codable, Sendable {
        public let codec: String?
        public let sampleFrequency: Int?
        public let streamSampleRate: Int?
        public let streamChannels: String?
        public let nrAudioChannels: Int?
        public let bitsPerSample: Int?
    }

    public struct IndexValue: Codable, Sendable {
        public let i32_: Int?
    }
}

/// Response for player:volume.
public struct VolumeResponse: Codable, Sendable {
    public let i32_: Int?
}

/// Response for settings:/kef/play/physicalSource.
public struct PhysicalSourceResponse: Codable, Sendable {
    public let kefPhysicalSource: String?
}

/// Response for settings:/kef/host/speakerStatus.
public struct SpeakerStatusResponse: Codable, Sendable {
    public let kefSpeakerStatus: String?
}

/// Response for settings:/deviceName and settings:/system/primaryMacAddress.
public struct StringValueResponse: Codable, Sendable {
    public let string_: String?
}

/// Response for settings:/mediaPlayer/mute.
public struct MuteResponse: Codable, Sendable {
    public let bool_: Bool?
}

/// Response for settings:/mediaPlayer/playMode.
public struct PlayModeResponse: Codable, Sendable {
    public let type: String?
    public let playerPlayMode: String?
}

/// Response for player:player/data/playTime.
public struct PlayTimeResponse: Codable, Sendable {
    public let i64_: Int?
}

// MARK: - setData Request Types (Encodable)

/// Request body for player:volume (role "value").
public struct SetVolumeRequest: Codable, Sendable {
    public let type: String
    public let i32_: Int

    public init(volume: Int) {
        self.type = "i32_"
        self.i32_ = min(max(volume, 0), 100)
    }
}

/// Request body for settings:/kef/play/physicalSource (role "value").
public struct SetPhysicalSourceRequest: Codable, Sendable {
    public let type: String
    public let kefPhysicalSource: String

    public init(source: String) {
        self.type = "kefPhysicalSource"
        self.kefPhysicalSource = source
    }
}

/// Request body for settings:/mediaPlayer/mute (role "value").
public struct SetMuteRequest: Codable, Sendable {
    public let type: String
    public let bool_: Bool

    public init(muted: Bool) {
        self.type = "bool_"
        self.bool_ = muted
    }
}

/// Request body for settings:/mediaPlayer/playMode (role "value").
public struct SetPlayModeRequest: Codable, Sendable {
    public let type: String
    public let playerPlayMode: String

    public init(mode: String) {
        self.type = "playerPlayMode"
        self.playerPlayMode = mode
    }
}

/// Request body for player:player/control (role "activate").
public struct PlayerControlRequest: Codable, Sendable {
    public let control: String
    public let time: Int?

    public init(control: String, time: Int? = nil) {
        self.control = control
        self.time = time
    }

    public static func play() -> PlayerControlRequest {
        PlayerControlRequest(control: "play")
    }

    public static func pause() -> PlayerControlRequest {
        PlayerControlRequest(control: "pause")
    }

    public static func next() -> PlayerControlRequest {
        PlayerControlRequest(control: "next")
    }

    public static func previous() -> PlayerControlRequest {
        PlayerControlRequest(control: "previous")
    }

    public static func seek(playTimeMs: Int) -> PlayerControlRequest {
        PlayerControlRequest(control: "seekTime", time: playTimeMs)
    }
}

/// Request body for playlists:pl/clear (role "activate").
public struct ClearQueueRequest: Codable, Sendable {
    public let plid: Int

    public init(plid: Int = 0) {
        self.plid = plid
    }
}

// MARK: - Dynamic / Any value for setData body

struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Encodes a [String: Any] dictionary as JSON for setData value. Use for complex request bodies that don't have a dedicated Codable type.
/// Marked @unchecked Sendable: value is only read during encoding and not shared across isolation boundaries.
struct AnyEncodableValue: Encodable, @unchecked Sendable {
    let value: [String: Any]

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        for (keyStr, val) in value {
            guard let key = DynamicCodingKey(stringValue: keyStr) else { continue }
            try container.encode(AnyCodable(val), forKey: key)
        }
    }
}

// MARK: - getRows Response Types

/// Response for getRows (rows + optional rowsCount, rowsRedirect).
public struct GetRowsResponse: Codable {
    public let rows: [[String: AnyCodable]]?
    public let rowsCount: Int?
    public let rowsRedirect: String?

    enum CodingKeys: String, CodingKey {
        case rows
        case rowsCount
        case rowsRedirect
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rows = try container.decodeIfPresent([[String: AnyCodable]].self, forKey: .rows)
        rowsCount = try container.decodeIfPresent(Int.self, forKey: .rowsCount)
        rowsRedirect = try container.decodeIfPresent(String.self, forKey: .rowsRedirect)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(rows, forKey: .rows)
        try container.encodeIfPresent(rowsCount, forKey: .rowsCount)
        try container.encodeIfPresent(rowsRedirect, forKey: .rowsRedirect)
    }
}

/// Type-erased Codable for flexible JSON values (e.g. getRows rows). Not Sendable (value is Any).
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let singleContainer = try decoder.singleValueContainer()
        if singleContainer.decodeNil() {
            value = NSNull()
        } else if let bool = try? singleContainer.decode(Bool.self) {
            value = bool
        } else if let int = try? singleContainer.decode(Int.self) {
            value = int
        } else if let double = try? singleContainer.decode(Double.self) {
            value = double
        } else if let string = try? singleContainer.decode(String.self) {
            value = string
        } else if let array = try? singleContainer.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? singleContainer.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(in: singleContainer, debugDescription: "AnyCodable cannot decode value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "AnyCodable cannot encode value"))
        }
    }
}
