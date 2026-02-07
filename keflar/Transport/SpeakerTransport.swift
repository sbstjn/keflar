import Foundation

// MARK: - Protocol

/// Transport for control and settings: volume, mute, source, play/pause/seek. Sendable so it can be held across isolation boundaries.
protocol SpeakerTransport: Sendable {
    func play() async throws
    func pause() async throws
    func playNext() async throws
    func playPrevious() async throws
    func seekTo(playTimeMs: Int) async throws
    func setVolume(_ volume: Int) async throws
    func setMute(_ muted: Bool) async throws
    func setSource(_ source: PhysicalSource) async throws
}

// MARK: - Default Implementation

actor DefaultSpeakerTransport: SpeakerTransport {
    private let client: any SpeakerClientProtocol

    init(client: any SpeakerClientProtocol) {
        self.client = client
    }

    func setVolume(_ volume: Int) async throws {
        try await client.setDataWithBody(path: APIPath.volume.path, role: "value", value: SetVolumeRequest(volume: volume))
    }

    func setMute(_ muted: Bool) async throws {
        try await client.setDataWithBody(path: APIPath.mute.path, role: "value", value: SetMuteRequest(muted: muted))
    }

    func setSource(_ source: PhysicalSource) async throws {
        try await client.setDataWithBody(path: APIPath.physicalSource.path, role: "value", value: SetPhysicalSourceRequest(source: source.rawValue))
    }

    func play() async throws {
        try await client.setDataWithBody(path: APIPath.playerControl.path, role: "activate", value: PlayerControlRequest.play())
    }

    func pause() async throws {
        try await client.setDataWithBody(path: APIPath.playerControl.path, role: "activate", value: PlayerControlRequest.pause())
    }

    func playNext() async throws {
        try await client.setDataWithBody(path: APIPath.playerControl.path, role: "activate", value: PlayerControlRequest.next())
    }

    func playPrevious() async throws {
        try await client.setDataWithBody(path: APIPath.playerControl.path, role: "activate", value: PlayerControlRequest.previous())
    }

    func seekTo(playTimeMs: Int) async throws {
        try await client.setDataWithBody(path: APIPath.playerControl.path, role: "activate", value: PlayerControlRequest.seek(playTimeMs: playTimeMs))
    }
}
