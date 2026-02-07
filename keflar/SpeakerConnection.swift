import Foundation
import os

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

/// Configuration for connecting to a speaker.
public struct ConnectionConfig: Sendable {
    /// If true (default), waits for initial getData (parallel requests) so the returned Speaker has fresh state immediately.
    public var awaitInitialState: Bool
    /// If true, wraps the client in a counter so you can read HTTP request counts via `speaker.getRequestCounts()`.
    public var requestCounting: Bool
    /// Grace period for connection loss; when nil, library defaults are used.
    public var policy: ConnectionPolicy?
    /// Request timeout (seconds) per request during connection. When nil, default URLSession timeouts are used.
    public var timeout: TimeInterval?
    
    public init(
        awaitInitialState: Bool = true,
        requestCounting: Bool = false,
        policy: ConnectionPolicy? = nil,
        timeout: TimeInterval? = nil
    ) {
        self.awaitInitialState = awaitInitialState
        self.requestCounting = requestCounting
        self.policy = policy
        self.timeout = timeout
    }
    
    public static let `default` = ConnectionConfig()
}

/// Unified entry point for keflar library. Provides static methods for probing and connecting to KEF speakers.
public enum Keflar {
    /// Probe a speaker at the given host; returns SpeakerProbe if reachable (releasetext + optional deviceName; no queue subscription or state).
    public static func probe(host: String) async throws -> SpeakerProbe {
        let client = DefaultSpeakerClient(host: host, session: .shared)
        async let releasetextTask = client.getData(path: APIPath.releasetext.path)
        async let deviceNameTask = client.getData(path: APIPath.deviceName.path)
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

    /// Connect to a speaker at the given host; returns the connected Speaker instance.
    public static func connect(to host: String, config: ConnectionConfig = .default) async throws -> Speaker {
        let session: URLSession
        if let connectTimeout = config.timeout {
            let urlConfig = URLSessionConfiguration.default
            urlConfig.timeoutIntervalForRequest = connectTimeout
            session = URLSession(configuration: urlConfig)
        } else {
            session = .shared
        }
        let base = DefaultSpeakerClient(host: host, session: session, requestTimeout: config.timeout)
        let client: any SpeakerClientProtocol = config.requestCounting ? CountingSpeakerClient(wrapping: base) : base
        let refresherBox = RefresherBox()
        let refreshingClient = StateRefreshingClient(wrapping: client, refresher: refresherBox)
        let first = try await refreshingClient.getData(path: APIPath.releasetext.path)
        guard let releaseText = first["string_"] as? String else {
            let preview = String(describing: first)
            let truncated = preview.count > 500 ? String(preview.prefix(500)) + "..." : preview
            throw SpeakerConnectError.invalidJSON(responsePreview: "releasetext: expected object with string_; body: \(truncated)")
        }
        let parts = releaseText.split(separator: "_").map(String.init)
        let model = parts.first ?? ""
        let version = parts.dropFirst().first ?? ""

        let queueId = try await refreshingClient.modifyQueue()
        let (stateStream, stateContinuation) = AsyncStream.makeStream(of: SpeakerState.self)
        let stateHolder = SpeakerStateHolder(continuation: stateContinuation)
        let transport = DefaultSpeakerTransport(client: refreshingClient)
        let proxyResolver = AirableProxyResolver(client: refreshingClient, stateHolder: stateHolder)
        let playlistManager = DefaultPlaylistManager(
            client: refreshingClient,
            proxyResolver: proxyResolver,
            stateHolder: stateHolder
        )
        let speaker = await MainActor.run {
            Speaker(
                model: model,
                version: version,
                client: refreshingClient,
                transport: transport,
                playlistManager: playlistManager,
                queueId: queueId,
                stateHolder: stateHolder,
                stateStream: stateStream,
                connectionPolicy: config.policy
            )
        }
        refresherBox.speaker = speaker
        Logger.keflar.info("Connected to \(model) v\(version)")
        if config.awaitInitialState {
            await fetchInitialState(client: refreshingClient, stateHolder: stateHolder)
        } else {
            let ctx = SendableFetchContext(client: refreshingClient, stateHolder: stateHolder)
            Task(name: "SpeakerConnection.fetchInitialState") { await fetchInitialState(client: ctx.client, stateHolder: ctx.stateHolder) }
        }
        return speaker
    }
}

/// Entry point; connect() returns a Speaker that shadows the device.
/// @deprecated Use `Keflar.connect(to:config:)` and `Keflar.probe(host:)` instead.
public struct SpeakerConnection {
    public var host: String

    public init(host: String) {
        self.host = host
    }

    /// Probe the speaker; returns SpeakerProbe if reachable (releasetext + optional deviceName; no queue subscription or state).
    /// @deprecated Use `Keflar.probe(host:)` instead.
    public func probe() async throws -> SpeakerProbe {
        try await Keflar.probe(host: host)
    }

    /// Connect to the speaker; returns the connected Speaker instance.
    /// @deprecated Use `Keflar.connect(to:config:)` instead.
    public func connect(config: ConnectionConfig = .default) async throws -> Speaker {
        try await Keflar.connect(to: host, config: config)
    }
}
