import Foundation

/// Hardware control: source, volume, mute. Delegates to speaker transport.
struct HardwareControl: Sendable {
    private let transport: any SpeakerTransport

    init(transport: any SpeakerTransport) {
        self.transport = transport
    }

    func setSource(_ source: PhysicalSource) async throws {
        try await transport.setSource(source)
    }

    func setVolume(_ volume: Int) async throws {
        try await transport.setVolume(volume)
    }

    func setMute(_ muted: Bool) async throws {
        try await transport.setMute(muted)
    }
}
