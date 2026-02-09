import Foundation
import os

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
    /// Grace period for connection loss; when nil, library defaults are used.
    public var policy: ConnectionPolicy?
    /// Request timeout (seconds) per request during connection. When nil, default URLSession timeouts are used.
    public var timeout: TimeInterval?
    /// Streaming services to enable (default: [.tidal, .deezer, .amazon]). Register all services you plan to use.
    public var services: [AudioService]

    public init(
        awaitInitialState: Bool = true,
        policy: ConnectionPolicy? = nil,
        timeout: TimeInterval? = nil,
        services: [AudioService] = [.tidal, .deezer, .amazon]
    ) {
        self.awaitInitialState = awaitInitialState
        self.policy = policy
        self.timeout = timeout
        self.services = services
    }

    public static let `default` = ConnectionConfig()
}

/// Returns a streaming service implementation for the given AudioService, or nil if not supported.
private func makeStreamingService(
    for service: AudioService,
    client: any SpeakerClientProtocol,
    proxyResolver: AirableProxyResolver,
    stateSynchronizer: StateSynchronizer
) -> (any StreamingServiceOperations)? {
    if service == .tidal {
        return TidalService(client: client, proxyResolver: proxyResolver, stateSynchronizer: stateSynchronizer)
    }
    if service == .deezer {
        return DeezerService(client: client, proxyResolver: proxyResolver, stateSynchronizer: stateSynchronizer)
    }
    if service == .amazon {
        return AmazonService(client: client, proxyResolver: proxyResolver, stateSynchronizer: stateSynchronizer)
    }
    return nil
}

/// Unified entry point for keflar library. Provides static methods for probing and connecting to KEF speakers.
public enum Keflar {
    /// Probe a speaker at the given host; returns SpeakerProbe if reachable (releasetext + optional deviceName; no queue subscription or state).
    public static func probe(host: String) async throws -> SpeakerProbe {
        Logger.speaker.debug("probe start host=\(host, privacy: .private)")
        do {
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
            Logger.speaker.info("probe success model=\(model) version=\(version)")
            return SpeakerProbe(host: host, model: model, version: version, name: name)
        } catch {
            Logger.speaker.error("probe failed: \(error.localizedDescription, privacy: .private)")
            throw error
        }
    }

    /// Connect to a speaker at the given host; returns the connected Speaker instance.
    public static func connect(to host: String, config: ConnectionConfig = .default) async throws -> Speaker {
        Logger.speaker.debug("connect start host=\(host, privacy: .private)")
        let session: URLSession
        if let connectTimeout = config.timeout {
            let urlConfig = URLSessionConfiguration.default
            urlConfig.timeoutIntervalForRequest = connectTimeout
            session = URLSession(configuration: urlConfig)
        } else {
            session = .shared
        }
        let base = DefaultSpeakerClient(host: host, session: session, requestTimeout: config.timeout)
        let client: any SpeakerClientProtocol = base
        do {
            let first = try await client.getData(path: APIPath.releasetext.path)
            guard let releaseText = first["string_"] as? String else {
                let preview = String(describing: first)
                let truncated = preview.count > 500 ? String(preview.prefix(500)) + "..." : preview
                throw SpeakerConnectError.invalidJSON(responsePreview: "releasetext: expected object with string_; body: \(truncated)")
            }
            let parts = releaseText.split(separator: "_").map(String.init)
            let model = parts.first ?? ""
            let version = parts.dropFirst().first ?? ""

            let queueId = try await client.modifyQueue()
            let (stateStream, stateContinuation) = AsyncStream.makeStream(of: SpeakerState.self)
            let stateSynchronizer = StateSynchronizer(continuation: stateContinuation)
            let transport = DefaultSpeakerTransport(client: client)
            let proxyResolver = AirableProxyResolver(client: client, stateSynchronizer: stateSynchronizer)
            let playlistManager = DefaultPlaylistManager(
                client: client,
                proxyResolver: proxyResolver,
                stateSynchronizer: stateSynchronizer
            )

            let serviceRegistry = ServiceRegistry()
            for service in config.services {
                if let impl = makeStreamingService(
                    for: service,
                    client: client,
                    proxyResolver: proxyResolver,
                    stateSynchronizer: stateSynchronizer
                ) {
                    await serviceRegistry.register(service: impl)
                }
            }

            let speaker = await MainActor.run {
                Speaker(
                    model: model,
                    version: version,
                    client: client,
                    transport: transport,
                    playlistManager: playlistManager,
                    serviceRegistry: serviceRegistry,
                    queueId: queueId,
                    stateSynchronizer: stateSynchronizer,
                    stateStream: stateStream,
                    connectionPolicy: config.policy
                )
            }
            Logger.speaker.info("Connected to \(model) v\(version)")
            if config.awaitInitialState {
                await fetchInitialStateWithSynchronizer(client: client, stateSynchronizer: stateSynchronizer)
            } else {
                Task(name: "Keflar.fetchInitialState") {
                    await fetchInitialStateWithSynchronizer(client: client, stateSynchronizer: stateSynchronizer)
                }
            }
            return speaker
        } catch {
            Logger.speaker.error("connect failed: \(error.localizedDescription, privacy: .private)")
            throw error
        }
    }
}
