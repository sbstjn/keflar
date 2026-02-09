import Foundation
import os

// MARK: - Centralized loggers (single source of truth)
// Subsystem: com.sbstjn.keflar. Categories: speaker, network, eventPoll, resilience, streaming, state.
// Levels: debug (requests, timings, retries), info (lifecycle), error (failures in addition to throw).
// Privacy: use \(value, privacy: .private) for host, path, payloads; .public for non-sensitive enums/ids.

extension Logger {
    private static let subsystem = "com.sbstjn.keflar"

    /// Speaker lifecycle: probe, connect, disconnect.
    static let speaker = Logger(subsystem: subsystem, category: "speaker")
    /// Backward compatibility alias for speaker.
    static let keflar = speaker

    /// HTTP and transport: getData, setData, getRows, modifyQueue, pollQueue.
    static let network = Logger(subsystem: subsystem, category: "network")

    /// Event queue subscribe/poll, reconnecting, recovered, disconnected.
    static let eventPoll = Logger(subsystem: subsystem, category: "eventPoll")

    /// Circuit breaker and retry policy.
    static let resilience = Logger(subsystem: subsystem, category: "resilience")

    /// Proxy resolution, browse, play playlist, fetch queue.
    static let streaming = Logger(subsystem: subsystem, category: "streaming")

    /// State apply/batch (optional, debug-only).
    static let state = Logger(subsystem: subsystem, category: "state")
}

// MARK: - Request context

/// Minimal request context for structured logging: correlation ID and optional path. Use with OSLog interpolation (e.g. correlationId=\.public, path=\.private) for request/response and duration.
struct RequestLogContext: Sendable {
    let correlationId: String
    let path: String?

    init(path: String? = nil) {
        self.correlationId = UUID().uuidString
        self.path = path
    }
}
