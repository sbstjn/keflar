import Foundation

// MARK: - Response DTOs

/// Typed accessor for getData(path: "player:player/data") response.
/// DTO suffix denotes a data-transfer view over an untyped dict: type-safe access to state, trackRoles, path; raw dict for parsers.
public struct PlayerDataDTO {
    public let state: String?
    public let trackRoles: [String: Any]?
    public let path: String?
    public let raw: [String: Any]

    public init(dict: [String: Any]) {
        state = dict["state"] as? String
        let tr = dict["trackRoles"] as? [String: Any]
        trackRoles = tr
        path = tr?["path"] as? String
        raw = dict
    }
}

/// Parsed response from event/modifyQueue API (queue ID string, optionally wrapped in JSON array).
public struct ModifyQueueResponse: Sendable {
    public let queueId: String

    /// Parses raw JSON: queue ID as a string, or array whose second element is the queue ID string. Strips surrounding `{}` if present.
    public init?(json: Any) {
        if let str = json as? String {
            let trimmed = str.count > 2 && str.first == "{" && str.last == "}" ? String(str.dropFirst().dropLast()) : str
            queueId = trimmed
            return
        }
        if let arr = json as? [Any], arr.count > 1, let middle = arr[1] as? String {
            let trimmed = middle.count > 2 && middle.first == "{" && middle.last == "}" ? String(middle.dropFirst().dropLast()) : middle
            queueId = trimmed
            return
        }
        return nil
    }
}

// MARK: - Protocol

/// Transport abstraction for KEF speaker API; enables injection and testing without a real device.
protocol SpeakerClientProtocol: Sendable {
    func getData(path: String) async throws -> [String: Any]
    /// POST setData with JSON body (path, role, value). Value is encoded as JSON for the "value" field.
    func setDataWithBody<E: Encodable>(path: String, role: String, value: E) async throws
    func getRows(path: String, from: Int, to: Int) async throws -> [String: Any]
    /// Browse (getRows) with typed result. Handles rowsRedirect by following once and returning redirectedFrom.
    func browse(path: String, from: Int, to: Int) async throws -> BrowseResult
    func modifyQueue() async throws -> String
    func pollQueue(queueId: String, timeout: TimeInterval) async throws -> [[String: Any]]
}
