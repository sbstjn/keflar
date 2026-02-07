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

    /// User-facing message for this reason.
    public var userFacingMessage: String {
        switch self {
        case .timeout: return "Request timed out."
        case .notConnectedToInternet: return "Device is not connected to the internet."
        case .cannotFindHost: return "Speaker host could not be found."
        case .connectionLost: return "Network connection was lost."
        case .other(let description): return description
        }
    }
}

extension SpeakerConnectError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid speaker URL. Ensure the host is a valid IP address or hostname."
        case .invalidResponseStructure:
            return "Unexpected response from speaker. The device may be incompatible or offline."
        case .invalidJSON(let responsePreview):
            return "Invalid JSON from speaker. \(responsePreview)"
        case .invalidSource(let message):
            return "Invalid source or configuration: \(message)"
        case .connectionUnavailable(let reason):
            return "Connection failed: \(reason.userFacingMessage)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .invalidURL:
            return "Check that your speaker's IP address is correct (e.g., 192.168.1.100)."
        case .invalidResponseStructure:
            return "Ensure the speaker is on and running the latest firmware."
        case .invalidJSON:
            return "Retry the operation. If it persists, the speaker may need a restart."
        case .invalidSource:
            return nil
        case .connectionUnavailable(.notConnectedToInternet):
            return "Verify your device is connected to the same network as the speaker."
        case .connectionUnavailable(.timeout), .connectionUnavailable(.cannotFindHost):
            return "Confirm the speaker is powered on and the host address is correct."
        case .connectionUnavailable(.connectionLost), .connectionUnavailable(.other):
            return "Check your network connection and retry."
        }
    }
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

/// Event from event stream; maps to ConnectionState. Consume via `Speaker.connectionEvents`.
public enum ConnectionEvent: Sendable {
    case reconnecting
    case disconnected
    case recovered
}

/// Player state from the speaker's media player.
///
/// Represents the current playback status of the speaker.
@frozen public enum PlayerState: String, Sendable {
    /// Media is currently playing.
    case playing
    /// Media is paused.
    case paused
    /// Media is stopped or no media loaded.
    case stopped
    
    /// Whether the player is actively playing media.
    public var isPlaying: Bool {
        self == .playing
    }
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