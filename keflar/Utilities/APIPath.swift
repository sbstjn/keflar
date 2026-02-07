import Foundation

/// Type-safe API path for the KEF speaker. Use known cases or `.custom(String)` for dynamic paths (e.g. airable:..., playlists:item/N).
@frozen
public enum APIPath: Sendable, Hashable {
    case playerData
    case playTime
    case playerControl
    case playQueue
    case playMode
    case volume
    case physicalSource
    case speakerStatus
    case deviceName
    case mute
    case macAddress
    case releasetext
    case plClear
    case plAddExternalItems
    case custom(String)

    /// String value sent to the API.
    public var path: String {
        switch self {
        case .playerData: return "player:player/data"
        case .playTime: return "player:player/data/playTime"
        case .playerControl: return "player:player/control"
        case .playQueue: return "playlists:pq/getitems"
        case .playMode: return "settings:/mediaPlayer/playMode"
        case .volume: return "player:volume"
        case .physicalSource: return "settings:/kef/play/physicalSource"
        case .speakerStatus: return "settings:/kef/host/speakerStatus"
        case .deviceName: return "settings:/deviceName"
        case .mute: return "settings:/mediaPlayer/mute"
        case .macAddress: return "settings:/system/primaryMacAddress"
        case .releasetext: return "settings:/releasetext"
        case .plClear: return "playlists:pl/clear"
        case .plAddExternalItems: return "playlists:pl/addexternalitems"
        case .custom(let s): return s
        }
    }

    /// Parses a path string from the API into APIPath (known case or .custom).
    public static func from(_ pathString: String) -> APIPath {
        switch pathString {
        case "player:player/data": return .playerData
        case "player:player/data/playTime": return .playTime
        case "player:player/control": return .playerControl
        case "playlists:pq/getitems": return .playQueue
        case "settings:/mediaPlayer/playMode": return .playMode
        case "player:volume": return .volume
        case "settings:/kef/play/physicalSource": return .physicalSource
        case "settings:/kef/host/speakerStatus": return .speakerStatus
        case "settings:/deviceName": return .deviceName
        case "settings:/mediaPlayer/mute": return .mute
        case "settings:/system/primaryMacAddress": return .macAddress
        case "settings:/releasetext": return .releasetext
        case "playlists:pl/clear": return .plClear
        case "playlists:pl/addexternalitems": return .plAddExternalItems
        default: return .custom(pathString)
        }
    }
}
