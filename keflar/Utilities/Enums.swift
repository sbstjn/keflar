import Foundation

/// Errors that can occur when connecting to or communicating with the speaker.
public enum SpeakerConnectError: Error {
    /// Failed to construct URL for API endpoint.
    case invalidURL
    /// API response structure doesn't match expected format.
    case invalidResponseStructure
    /// JSON parsing failed; includes response preview for debugging.
    case invalidJSON(responsePreview: String)
    /// Invalid source, path, or parameter; includes error message.
    case invalidSource(String)
    /// Network/transport failure (timeout, no connectivity, host unreachable).
    case connectionUnavailable(TransportFailureReason)
}

/// Reason for a transport/connection failure; allows apps to show specific messages.
public enum TransportFailureReason: Sendable {
    case timeout
    case notConnectedToInternet
    case cannotFindHost
    case connectionLost
    case other(description: String)
}

/// Observable connection health for the event stream. Apps can show "Reconnecting…" or route away when disconnected.
public enum ConnectionState: Sendable {
    case connected
    case reconnecting
    case disconnected
}

/// Optional connection grace-period policy; when nil, library defaults are used.
/// Typical range: 3–5 failures over 10–15 seconds to tolerate brief hiccups without delaying disconnect on real network loss.
public struct ConnectionPolicy: Sendable {
    public var graceMinFailures: Int
    public var graceDuration: TimeInterval

    public init(graceMinFailures: Int = 3, graceDuration: TimeInterval = 12) {
        self.graceMinFailures = graceMinFailures
        self.graceDuration = graceDuration
    }
}

/// Internal event from event stream to Speaker; maps to ConnectionState.
enum ConnectionEvent: Sendable {
    case reconnecting
    case disconnected
    case recovered
}

/// Type-safe physical source / power state for the speaker.
/// 
/// Use with `Speaker.setSource(_:)` to switch inputs or power state.
@frozen public enum PhysicalSource: String, CaseIterable, Sendable {
    /// WiFi streaming input (network audio).
    case wifi
    /// Bluetooth input.
    case bluetooth
    /// TV/HDMI input.
    case tv
    /// Optical (TOSLINK) input.
    case optic
    /// Coaxial (S/PDIF) input.
    case coaxial
    /// Analog (RCA/3.5mm) input.
    case analog
    /// Power off / standby mode.
    case standby
    /// Power on (transitions from standby to last active source).
    case powerOn
}

/// Type of a play-context row from getRows(playContext): direct action or container (sub-context).
@frozen public enum PlayContextItemType: Sendable {
    /// Single-step action; invoke with setData(path, role: activate).
    case action
    /// Sub-context; use getRows(path) for next level (e.g. playlist list).
    case container
}