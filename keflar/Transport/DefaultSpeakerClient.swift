import Foundation

// MARK: - Constants

/// Event subscription paths and types for modifyQueue. Derived from KEF event API; cross-checked against pykefcontrol (https://github.com/N0ciple/pykefcontrol).
private let eventSubscribePaths: [[String: String]] = [
    ["path": "settings:/mediaPlayer/playMode", "type": "itemWithValue"],
    ["path": "playlists:pq/getitems", "type": "rows"],
    ["path": "notifications:/display/queue", "type": "rows"],
    ["path": "settings:/kef/host/maximumVolume", "type": "itemWithValue"],
    ["path": "player:volume", "type": "itemWithValue"],
    ["path": "player:player/data", "type": "itemWithValue"],
    ["path": "player:player/data/playTime", "type": "itemWithValue"],
    ["path": "kef:fwupgrade/info", "type": "itemWithValue"],
    ["path": "settings:/kef/host/volumeStep", "type": "itemWithValue"],
    ["path": "settings:/kef/host/volumeLimit", "type": "itemWithValue"],
    ["path": "settings:/mediaPlayer/mute", "type": "itemWithValue"],
    ["path": "settings:/kef/host/speakerStatus", "type": "itemWithValue"],
    ["path": "settings:/kef/play/physicalSource", "type": "itemWithValue"],
    ["path": "kef:speedTest/status", "type": "itemWithValue"],
    ["path": "network:info", "type": "itemWithValue"],
    ["path": "kef:eqProfile", "type": "itemWithValue"],
    ["path": "settings:/kef/host/modelName", "type": "itemWithValue"],
    ["path": "settings:/version", "type": "itemWithValue"],
    ["path": "settings:/deviceName", "type": "itemWithValue"],
]

private let defaultRequestTimeout: TimeInterval = 10
private let longRequestTimeout: TimeInterval = 15
private let maxErrorPreviewLength = 500
private let maxPathLength = 2048
private let maxRequestBodySize = 1_000_000
private let maxGetRowsRange = 1000

// MARK: - Default HTTP Client

/// Default HTTP client for the KEF speaker API; builds URLs from host and session.
struct DefaultSpeakerClient: SpeakerClientProtocol, Sendable {
    let host: String
    let session: URLSession

    init(host: String, session: URLSession = .shared) {
        self.host = host
        self.session = session
    }

    private func makeURL(apiPath: String, queryItems: [URLQueryItem]?) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.path = apiPath
        components.queryItems = queryItems
        return components.url
    }

    private func makeRequest(url: URL, method: String = "GET", body: Data? = nil, timeout: TimeInterval = defaultRequestTimeout) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }

    private func errorPreview(from data: Data) -> String {
        String(data: data.prefix(maxErrorPreviewLength), encoding: .utf8) ?? ""
    }

    private func validatePath(_ path: String) throws {
        if path.isEmpty {
            throw SpeakerConnectError.invalidSource("path must not be empty")
        }
        if path.count > maxPathLength {
            throw SpeakerConnectError.invalidSource("path must not exceed \(maxPathLength) characters")
        }
    }

    private func validateGetRowsRange(from: Int, to: Int) throws {
        if from < 0 || to < from {
            throw SpeakerConnectError.invalidSource("getRows: from (\(from)) and to (\(to)) must satisfy 0 <= from <= to")
        }
        if to - from > maxGetRowsRange {
            throw SpeakerConnectError.invalidSource("getRows: range (to - from) must not exceed \(maxGetRowsRange)")
        }
    }

    func getData(path: String) async throws -> [String: Any] {
        try validatePath(path)
        guard let url = makeURL(apiPath: "/api/getData", queryItems: [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "roles", value: "value"),
        ]) else {
            throw SpeakerConnectError.invalidURL
        }
        let request = makeRequest(url: url, timeout: defaultRequestTimeout)
        let (data, _) = try await session.data(for: request)
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        } catch {
            throw SpeakerConnectError.invalidJSON(responsePreview: "getData(\(path)): \(error.localizedDescription); body: \(errorPreview(from: data))")
        }
        guard let arr = json as? [[String: Any]], let first = arr.first else {
            throw SpeakerConnectError.invalidJSON(responsePreview: "getData(\(path)): expected non-empty array; body: \(errorPreview(from: data))")
        }
        return first
    }

    func setData(path: String, value: String) async throws {
        try validatePath(path)
        guard let url = makeURL(apiPath: "/api/setData", queryItems: [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "roles", value: "value"),
            URLQueryItem(name: "value", value: value),
        ]) else {
            throw SpeakerConnectError.invalidURL
        }
        let request = makeRequest(url: url, timeout: defaultRequestTimeout)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SpeakerConnectError.invalidJSON(responsePreview: "setData status \(http.statusCode); body: \(errorPreview(from: data))")
        }
    }

    func setDataWithBody(path: String, role: String, value: SendableBody) async throws {
        try validatePath(path)
        guard let url = makeURL(apiPath: "/api/setData", queryItems: nil) else {
            throw SpeakerConnectError.invalidURL
        }
        let body: [String: Any] = ["path": path, "role": role, "value": value.value]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        if bodyData.count > maxRequestBodySize {
            throw SpeakerConnectError.invalidSource("setData body must not exceed \(maxRequestBodySize) bytes")
        }
        let request = makeRequest(url: url, method: "POST", body: bodyData, timeout: longRequestTimeout)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SpeakerConnectError.invalidJSON(responsePreview: "setData status \(http.statusCode); body: \(errorPreview(from: data))")
        }
    }

    func getRows(path: String, from: Int, to: Int) async throws -> [String: Any] {
        try validatePath(path)
        try validateGetRowsRange(from: from, to: to)
        guard let url = makeURL(apiPath: "/api/getRows", queryItems: [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "from", value: String(from)),
            URLQueryItem(name: "to", value: String(to)),
            URLQueryItem(name: "roles", value: "@all"),
        ]) else {
            throw SpeakerConnectError.invalidURL
        }
        let request = makeRequest(url: url, timeout: longRequestTimeout)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SpeakerConnectError.invalidJSON(responsePreview: "getRows status \(http.statusCode); body: \(errorPreview(from: data))")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SpeakerConnectError.invalidResponseStructure
        }
        return json
    }

    func modifyQueue() async throws -> String {
        guard let url = makeURL(apiPath: "/api/event/modifyQueue", queryItems: nil) else {
            throw SpeakerConnectError.invalidURL
        }
        let body: [String: Any] = [
            "subscribe": eventSubscribePaths,
            "unsubscribe": [] as [String],
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            throw SpeakerConnectError.invalidResponseStructure
        }
        let request = makeRequest(url: url, method: "POST", body: bodyData, timeout: longRequestTimeout)
        let (data, _) = try await session.data(for: request)
        let preview = errorPreview(from: data)
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        } catch {
            throw SpeakerConnectError.invalidJSON(responsePreview: "modifyQueue: \(error.localizedDescription); body: \(preview)")
        }
        guard let response = ModifyQueueResponse(json: json) else {
            throw SpeakerConnectError.invalidJSON(responsePreview: "modifyQueue: invalid response shape (expected queue ID string or array with queue ID); body: \(preview)")
        }
        return response.queueId
    }

    func pollQueue(queueId: String, timeout: TimeInterval) async throws -> [[String: Any]] {
        guard let url = makeURL(apiPath: "/api/event/pollQueue", queryItems: [
            URLQueryItem(name: "queueId", value: queueId),
            URLQueryItem(name: "timeout", value: String(Int(timeout))),
        ]) else {
            throw SpeakerConnectError.invalidURL
        }
        let request = makeRequest(url: url, timeout: timeout + 0.5)
        let (data, _) = try await session.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SpeakerConnectError.invalidResponseStructure
        }
        return json
    }

    func getRequestCounts() async -> RequestCounts? { nil }
}
