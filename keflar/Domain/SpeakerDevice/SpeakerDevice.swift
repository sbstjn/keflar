import Foundation

/// Aggregate root for speaker hardware: connection state, physical controls (source, volume, mute).
@MainActor
public final class SpeakerDevice: @unchecked Sendable {
    private let hardwareControl: HardwareControl
    private var getState: () -> SpeakerState

    init(hardwareControl: HardwareControl, getState: @escaping () -> SpeakerState) {
        self.hardwareControl = hardwareControl
        self.getState = getState
    }

    public func configureGetState(_ getState: @escaping () -> SpeakerState) {
        self.getState = getState
    }

    // MARK: - State (from shadow state)

    public var source: PhysicalSource? { getState().source }
    public var volume: Int? { getState().volume }
    public var isMuted: Bool? { getState().mute }

    // MARK: - Control

    public func setSource(_ source: PhysicalSource) async throws {
        try await hardwareControl.setSource(source)
    }

    public func setVolume(_ volume: Int) async throws {
        try await hardwareControl.setVolume(volume)
    }

    public func setMute(_ muted: Bool) async throws {
        try await hardwareControl.setMute(muted)
    }
}
