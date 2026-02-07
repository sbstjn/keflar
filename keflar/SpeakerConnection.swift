import Foundation

/// Sendable box so background fetch Task can capture client and stateHolder without Sendable errors.
private struct SendableFetchContext: @unchecked Sendable {
    let client: any SpeakerClientProtocol
    let stateHolder: SpeakerStateHolder
}

/// Result of a reachability probe: host, model, version, and optional device name.
public struct SpeakerProbe: Sendable {
    public let host: String
    public let model: String
    public let version: String
    public let name: String?

    public init(host: String, model: String, version: String, name: String? = nil) {
        self.host = host
        self.model = model
        self.version = version
        self.name = name
    }
}

/// Entry point; connect() returns a Speaker that shadows the device.
public struct SpeakerConnection {
    public var host: String

    public init(host: String) {
        self.host = host
    }

    /// Probe the speaker; returns SpeakerProbe if reachable (releasetext + optional deviceName; no queue subscription or state).
    public func probe() async throws -> SpeakerProbe {
        let client = DefaultSpeakerClient(host: host, session: .shared)
        async let releasetextTask = client.getData(path: "settings:/releasetext")
        async let deviceNameTask = client.getData(path: "settings:/deviceName")
        let first = try await releasetextTask
        guard let releaseText = first["string_"] as? String else {
            let preview = String(describing: first)
            let truncated = preview.count > 500 ? String(preview.prefix(500)) + "..." : preview
            throw SpeakerConnectError.invalidJSON(responsePreview: "releasetext: expected object with string_; body: \(truncated)")
        }
        let parts = releaseText.split(separator: "_").map(String.init)
        let model = parts.first ?? ""
        let version = parts.dropFirst().first ?? ""
        let nameDict = try? await deviceNameTask
        let name = nameDict?["string_"] as? String
        return SpeakerProbe(host: host, model: model, version: version, name: name)
    }

    /// Connect to the speaker; returns the connected Speaker instance.
    /// - Parameters:
    ///   - awaitInitialState: If true (default), waits for initial getData (parallel requests) so the returned Speaker has fresh state immediately; avoids waiting for the event long-poll (slower). If false, returns immediately and state fills in as fetchInitialState completes in the background.
    ///   - countRequests: If true, wraps the client in a counter so you can read HTTP request counts via `speaker.getRequestCounts()`.
    ///   - connectionPolicy: Optional grace period for connection loss; when nil, library defaults are used.
    public func connect(awaitInitialState: Bool = true, countRequests: Bool = false, connectionPolicy: ConnectionPolicy? = nil) async throws -> Speaker {
        let base = DefaultSpeakerClient(host: host, session: .shared)
        let client: any SpeakerClientProtocol = countRequests ? CountingSpeakerClient(wrapping: base) : base
        let refresherBox = RefresherBox()
        let refreshingClient = StateRefreshingClient(wrapping: client, refresher: refresherBox)
        let first = try await refreshingClient.getData(path: "settings:/releasetext")
        guard let releaseText = first["string_"] as? String else {
            let preview = String(describing: first)
            let truncated = preview.count > 500 ? String(preview.prefix(500)) + "..." : preview
            throw SpeakerConnectError.invalidJSON(responsePreview: "releasetext: expected object with string_; body: \(truncated)")
        }
        let parts = releaseText.split(separator: "_").map(String.init)
        let model = parts.first ?? ""
        let version = parts.dropFirst().first ?? ""

        let queueId = try await refreshingClient.modifyQueue()
        let stateHolder = SpeakerStateHolder()
        let speaker = await MainActor.run {
            Speaker(model: model, version: version, client: refreshingClient, queueId: queueId, stateHolder: stateHolder, connectionPolicy: connectionPolicy)
        }
        refresherBox.speaker = speaker
        if awaitInitialState {
            await fetchInitialState(client: refreshingClient, stateHolder: stateHolder)
        } else {
            let ctx = SendableFetchContext(client: refreshingClient, stateHolder: stateHolder)
            Task(name: "SpeakerConnection.fetchInitialState") { await fetchInitialState(client: ctx.client, stateHolder: ctx.stateHolder) }
        }
        return speaker
    }
}
