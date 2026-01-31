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