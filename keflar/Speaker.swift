import Foundation
import Observation

// Speaker class relies on modular components:
// - Models/: SpeakerState, SpeakerEvents, CurrentSong, etc.
// - Parsers/: parseCurrentSong, parseDuration, etc.
// - State/: StateApplier, EventParser, mergeEvents
// - Infrastructure/StateSynchronization/: StateStore, fetchInitialState
// - EventStream/: EventPollState
// - Utilities/: Constants, AirableProxyHelpers
// - Transport/: SpeakerClientProtocol, SpeakerTransport, DefaultSpeakerClient

/// Sendable box for AsyncStream so Task closure can capture it without data-race.
private struct SendableStreamBox: @unchecked Sendable {
    let stream: AsyncStream<SpeakerEvents>
}

/// Holds the event-drive task so deinit can cancel it from a nonisolated context (Speaker is @MainActor).
private final class EventDriveTaskBox: @unchecked Sendable {
    var task: Task<Void, Never>?
}

// MARK: - SpeakerControl (internal)

/// Encapsulates control API (transport, play mode, playlist). Speaker delegates control methods to this type.
@MainActor
private final class SpeakerControl {
    private let transport: any SpeakerTransport
    private let client: any SpeakerClientProtocol
    private let stateHolder: StateSynchronizer
    private let playlistManager: any PlaylistManager
    private var getState: () -> SpeakerState

    init(
        transport: any SpeakerTransport,
        client: any SpeakerClientProtocol,
        stateSynchronizer: StateSynchronizer,
        playlistManager: any PlaylistManager,
        getState: @escaping () -> SpeakerState
    ) {
        self.transport = transport
        self.client = client
        self.stateHolder = stateSynchronizer
        self.playlistManager = playlistManager
        self.getState = getState
    }

    func configureGetState(_ getState: @escaping () -> SpeakerState) {
        self.getState = getState
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

    func setShuffle(_ on: Bool) async throws {
        let state = getState()
        let repeatMode = state.repeatMode ?? .off
        let mode = playModeString(shuffle: on, repeatMode: repeatMode)
        try await client.setDataWithBody(path: playModePath.path, role: "value", value: SetPlayModeRequest(mode: mode))
    }

    func setRepeat(_ mode: RepeatMode) async throws {
        let state = getState()
        let shuffleOn = state.shuffle ?? false
        let modeString = playModeString(shuffle: shuffleOn, repeatMode: mode)
        try await client.setDataWithBody(path: playModePath.path, role: "value", value: SetPlayModeRequest(mode: modeString))
    }

    func play() async throws { try await transport.play() }
    func pause() async throws { try await transport.pause() }
    func playNext() async throws { try await transport.playNext() }
    func playPrevious() async throws { try await transport.playPrevious() }
    func seekTo(playTimeMs: Int) async throws { try await transport.seekTo(playTimeMs: playTimeMs) }

    func playPlaylist(service: AudioService, playlistId: String) async throws {
        try await playlistManager.playPlaylist(service: service, playlistId: playlistId)
    }

    func playNext(track: QueueTrack) async throws {
        try await playlistManager.playNext(track: track)
    }

    func addToEndOfQueue(track: QueueTrack) async throws {
        try await playlistManager.addToEndOfQueue(track: track)
    }

    func refreshPlayerData() async throws {
        let data = try await client.getData(path: playerDataPath.path)
        await stateHolder.applyUpdate(path: playerDataPath.path, dict: data)
    }

    func fetchPlayQueue(from startIndex: Int, to endIndex: Int) async throws -> PlayQueueResult {
        try await playlistManager.fetchPlayQueue(from: startIndex, to: endIndex)
    }

    func playQueueItem(at index: Int, track: QueueTrack) async throws {
        try await playlistManager.playQueueItem(at: index, track: track)
    }

    func hasServiceConfiguration(_ service: AudioService) async throws -> Bool {
        try await playlistManager.hasServiceConfiguration(service)
    }

    private func playModeString(shuffle: Bool, repeatMode: RepeatMode) -> String {
        if shuffle {
            switch repeatMode {
            case .off: return "shuffle"
            case .one: return "shuffleRepeatOne"
            case .all: return "shuffleRepeatAll"
            }
        }
        switch repeatMode {
        case .off: return "normal"
        case .one: return "repeatOne"
        case .all: return "repeatAll"
        }
    }
}

/// Owns the Task that consumes the internal connection event stream. Cancels the task on deinit.
private final class ConnectionEventCoordinator: @unchecked Sendable {
    private var task: Task<Void, Never>?

    func hold(_ t: Task<Void, Never>) {
        task = t
    }

    deinit {
        task?.cancel()
    }
}

// MARK: - Speaker (connected instance)

/// Connected speaker that shadows the device; state is updated from initial getData and from the event stream.
///
/// **Architecture:** Speaker is the presentation layer of the three-layer architecture, wrapping domain aggregates:
/// - SpeakerDevice: Hardware control (power, source, volume, mute)
/// - PlaybackSession: Playback control (play, pause, seek, queue management)
/// - StreamingServices: Multi-service browse/favorites (via ServiceRegistry)
///
/// The library subscribes to the device event queue and long-polls automatically; events are merged into `state` internally. Observe `state` (or `$state`) for updates; no need to consume an event stream from the app.
///
/// **SwiftUI Integration:** `Speaker` is `@Observable`. Use `@State` where the instance is owned, or `let` / `@Bindable` when passed to child views. State updates are automatically dispatched to the main thread for UI rendering.
///
/// **Concurrency:** `Speaker` is not `Sendable`. Use one instance per connection from a single isolation context (e.g. main thread). Do not pass across actor boundaries or share between concurrent tasks.
@MainActor
@Observable
public final class Speaker {
    public let model: String
    public let version: String
    /// Accumulated shadow state of the remote device; updated from event batches and initial getData.
    public private(set) var state: SpeakerState

    /// Volume/mute slice. Observe for volume UI to reduce re-renders when only playback changes.
    public private(set) var volumeState: VolumeState = VolumeState()

    /// Playback slice (playerState, playTime, duration, shuffle, repeat). Observe for playback UI to reduce re-renders when only volume changes.
    public private(set) var playbackState: PlaybackStateSlice = PlaybackStateSlice()

    /// Event-stream connection health. Use for "Reconnecting…" or routing to device picker when `.disconnected`.
    public private(set) var connectionState: ConnectionState = .connected

    /// Connection events (reconnecting, recovered, disconnected). Consume with `for await event in speaker.connectionEvents`.
    public let connectionEvents: AsyncStream<ConnectionEvent>

    private let control: SpeakerControl
    private let device: SpeakerDevice
    private let playback: PlaybackSession
    private let client: any SpeakerClientProtocol
    private let stateHolder: StateSynchronizer
    private let pollState: EventPollState
    private let events: AsyncStream<SpeakerEvents>
    private let eventDriveTaskBox = EventDriveTaskBox()
    private let connectionCoordinator = ConnectionEventCoordinator()
    private let serviceRegistry: ServiceRegistry

    init(
        model: String,
        version: String,
        client: any SpeakerClientProtocol,
        transport: any SpeakerTransport,
        playlistManager: any PlaylistManager,
        serviceRegistry: ServiceRegistry,
        queueId: String?,
        stateSynchronizer: StateSynchronizer,
        stateStream: AsyncStream<SpeakerState>,
        pollTimeout: TimeInterval = defaultPollTimeout,
        connectionPolicy: ConnectionPolicy? = nil
    ) {
        self.model = model
        self.version = version
        self.stateHolder = stateSynchronizer
        self.serviceRegistry = serviceRegistry
        self.state = SpeakerState()
        self.client = client
        let graceMinFailures = connectionPolicy?.graceMinFailures ?? connectionGraceMinFailures
        let graceDuration = connectionPolicy?.graceDuration ?? connectionGraceDuration
        let (internalConnectionStream, internalConnectionContinuation) = AsyncStream.makeStream(of: ConnectionEvent.self)
        let (publicConnectionStream, publicConnectionContinuation) = AsyncStream.makeStream(of: ConnectionEvent.self)
        self.connectionEvents = publicConnectionStream
        self.control = SpeakerControl(
            transport: transport,
            client: client,
            stateSynchronizer: stateSynchronizer,
            playlistManager: playlistManager,
            getState: { SpeakerState() }
        )
        let hardwareControl = HardwareControl(transport: transport)
        self.device = SpeakerDevice(hardwareControl: hardwareControl, getState: { SpeakerState() })
        let playbackControl = PlaybackControl(transport: transport, client: client, getState: { SpeakerState() })
        let queueManager = QueueManager(playlistManager: playlistManager)
        self.playback = PlaybackSession(playbackControl: playbackControl, queueManager: queueManager, getState: { SpeakerState() })
        self.pollState = EventPollState(
            client: client,
            queueId: queueId,
            pollTimeout: pollTimeout,
            stateSynchronizer: stateSynchronizer,
            graceMinFailures: graceMinFailures,
            graceDuration: graceDuration,
            connectionEventContinuation: internalConnectionContinuation
        )
        self.events = AsyncStream(unfolding: { [pollState] in
            await pollState.pollOnce()
        })
        let streamBox = SendableStreamBox(stream: self.events)
        self.eventDriveTaskBox.task = Task(name: "Speaker.eventDrive") {
            for await _ in streamBox.stream {}
        }
        let connectionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await event in internalConnectionStream {
                switch event {
                case .reconnecting: self.connectionState = .reconnecting
                case .disconnected: self.connectionState = .disconnected
                case .recovered: self.connectionState = .connected
                }
                publicConnectionContinuation.yield(event)
            }
            publicConnectionContinuation.finish()
        }
        connectionCoordinator.hold(connectionTask)

        control.configureGetState { [weak self] in self?.state ?? SpeakerState() }
        device.configureGetState { [weak self] in self?.state ?? SpeakerState() }
        playback.configureGetState { [weak self] in self?.state ?? SpeakerState() }

        Task { @MainActor [weak self] in
            guard let self else { return }
            for await newState in stateStream {
                self.state = newState
                
                // Update slices to reduce SwiftUI re-render scope
                let v = VolumeState(volume: newState.volume, mute: newState.mute)
                if v != self.volumeState { self.volumeState = v }
                
                let p = PlaybackStateSlice(
                    playerState: newState.playerState,
                    playTime: newState.playTime,
                    duration: newState.duration,
                    currentQueueIndex: newState.currentQueueIndex,
                    shuffle: newState.shuffle,
                    repeatMode: newState.repeatMode
                )
                if p != self.playbackState { self.playbackState = p }
            }
        }
    }

    deinit {
        eventDriveTaskBox.task?.cancel()
    }

    // MARK: - Setters

    /// Set physical source / power.
    public func setSource(_ source: PhysicalSource) async throws {
        try await device.setSource(source)
    }

    /// Power on the speaker (same as setSource(.powerOn)).
    public func powerOn() async throws {
        try await setSource(.powerOn)
    }

    /// Shut down the speaker (same as setSource(.standby)).
    public func shutdown() async throws {
        try await setSource(.standby)
    }

    /// Set volume 0–100. 0 is mute.
    public func setVolume(_ volume: Int) async throws {
        try await device.setVolume(volume)
    }

    /// Set mute on/off via settings:/mediaPlayer/mute.
    public func setMute(_ muted: Bool) async throws {
        try await device.setMute(muted)
    }

    /// Set shuffle on/off via settings:/mediaPlayer/playMode. Preserves current repeat when turning shuffle off; turning shuffle on sends "shuffle" (device single-field: repeat off).
    public func setShuffle(_ on: Bool) async throws {
        try await playback.setShuffle(on)
    }

    /// Set repeat mode via settings:/mediaPlayer/playMode. Preserves shuffle when setting repeat off; setting repeat on sends shuffleRepeatOne/shuffleRepeatAll (device single-field: shuffle off).
    public func setRepeat(_ mode: RepeatMode) async throws {
        try await playback.setRepeat(mode)
    }

    // MARK: - Transport (player:player/control, POST setData)

    /// Start playback (control "play"). On many devices bare "play" can clear the queue or start from default; for toggle/resume use `pause()` instead (device treats "pause" as play↔pause toggle).
    public func play() async throws {
        try await playback.play()
    }

    /// Pause or resume (control "pause"). Device typically treats this as a toggle: playing → paused, paused → playing. Use for both pause and resume to avoid queue clear.
    public func pause() async throws {
        try await playback.pause()
    }

    /// Skip to next track. If the device does not auto-resume, call play() afterward.
    public func playNext() async throws {
        try await playback.playNext()
    }

    /// Skip to previous track. If the device does not auto-resume, call play() afterward.
    public func playPrevious() async throws {
        try await playback.playPrevious()
    }

    /// Seek to position in current track (playback position in milliseconds). Uses player:player/control with control "seekTime" and value "time" (ms), per official app.
    public func seekTo(playTimeMs: Int) async throws {
        try await playback.seekTo(playTimeMs: playTimeMs)
    }

    /// Play streaming service playlist by ID.
    /// - Parameters:
    ///   - service: Streaming service (e.g., `.tidal`, future `.spotify`).
    ///   - playlistId: Playlist UUID (e.g., from https://tidal.com/playlist/{id}).
    /// - Throws: SpeakerConnectError if service not configured or playlist unavailable.
    public func playPlaylist(service: AudioService, playlistId: String) async throws {
        try await playback.playPlaylist(service: service, playlistId: playlistId)
    }

    /// Check if streaming service is configured on the speaker (user linked).
    public func hasServiceConfiguration(_ service: AudioService) async throws -> Bool {
        try await playback.hasServiceConfiguration(service)
    }

    // MARK: - Getters (player state)

    /// Whether the speaker is currently playing. Uses shadow state (`player:player/data` fetched on connect and from event stream).
    public func isPlaying() -> Bool {
        state.playerState == .playing
    }

    /// Shuffle on/off. Uses shadow state (settings:/mediaPlayer/playMode). Nil until first getData/event.
    public var shuffle: Bool? {
        state.shuffle
    }

    /// Repeat mode (off / one / all). Uses shadow state (settings:/mediaPlayer/playMode). Nil until first getData/event.
    public var repeatMode: RepeatMode? {
        state.repeatMode
    }

    /// Track duration in ms. Uses shadow state (`player:player/data` → status.duration). Nil until first getData/event.
    public var trackDuration: Int? {
        state.duration
    }

    /// Zero-based index of current track in queue. Uses shadow state (`player:player/data` → trackRoles.value.i32_). Nil when not playing from queue.
    public var currentQueueIndex: Int? {
        state.currentQueueIndex
    }

    /// Cached player data (single path `player:player/data` requested once on connect, then updated from event stream).
    private var cachedPlayerData: PlayerDataDTO? {
        state.typedData[playerDataPath].map { PlayerDataDTO(dict: $0.value) }
    }

    /// Current song (title, artist, album, etc.). Uses shadow state; no extra request.
    public var currentSong: CurrentSong? {
        cachedPlayerData.map { parseCurrentSong(from: $0.raw) }
    }

    /// Audio codec/quality info (codec, sample rates, channels, serviceID). Uses shadow state only — no extra getData; same source as `currentSong` and `isPlaying`.
    public var audioCodecInfo: AudioCodecInfo? {
        cachedPlayerData.map { parseAudioCodecInfo(from: $0.raw) }
    }

    /// True when the current playback source is a known streaming service (Tidal, Deezer, Amazon Music). False for AirPlay, Bluetooth, or unknown. Use to show or hide shuffle, repeat, and queue UI; transport (prev/play/next) works for all sources.
    public var hasStreamingServicePlayback: Bool {
        AudioService.from(serviceID: audioCodecInfo?.serviceID ?? currentSong?.serviceID) != nil
    }

    /// Refresh cached player data from the device (getData player:player/data). Use when shadow state may be stale (e.g. after track change) so currentSong and playback state are up to date.
    public func refreshPlayerData() async throws {
        try await control.refreshPlayerData()
    }

    // MARK: - Play queue

    /// Fetch the currently playing queue from the speaker. Range limited by client (e.g. max 1000 items per call). Returns items in the requested range and total queue length (rowsCount) when provided by the API.
    public func fetchPlayQueue(from startIndex: Int = 0, to endIndex: Int = 999) async throws -> PlayQueueResult {
        try await playback.fetchPlayQueue(from: startIndex, to: endIndex)
    }

    /// Fetch the play queue and raw row dicts. Use rawRows with playQueueItem(at:track:) when the user taps a queue row. Order of rawRows matches result.items.
    public func fetchPlayQueueWithRaw(from startIndex: Int = 0, to endIndex: Int = 999) async throws -> PlayQueueWithRawResult {
        try await playback.fetchPlayQueueWithRaw(from: startIndex, to: endIndex)
    }

    /// Start playback at the given queue index. `track` must be the full queue row for that index (e.g. rawRows[i] from fetchPlayQueueWithRaw where result.items[i].index is the index).
    public func playQueueItem(at index: Int, track: [String: Any]) async throws {
        try await control.playQueueItem(at: index, track: QueueTrack(track))
    }

    /// Add one track to play immediately after the current track. `track` must be the full track row (path containing `/track`), e.g. from getRows (browse/playlist/queue) or player trackRoles. Works for Tidal, Deezer, Amazon Music.
    public func playNext(track: [String: Any]) async throws {
        try await control.playNext(track: QueueTrack(track))
    }

    /// Append one track to the end of the play queue. `track` must be the full track row (path containing `/track`), e.g. from getRows (browse/playlist/queue) or player trackRoles. Works for Tidal, Deezer, Amazon Music.
    public func addToEndOfQueue(track: [String: Any]) async throws {
        try await control.addToEndOfQueue(track: QueueTrack(track))
    }

    // MARK: - Streaming (favorites only; browse in SPECS for later)

    /// Add track to favorites. `trackId` must be the service identifier (e.g., from currentSong.trackId or browse row id), not arbitrary input.
    /// - Parameters:
    ///   - service: Streaming service (e.g., `.tidal`, future `.spotify`).
    ///   - trackId: Service-specific track identifier.
    ///   - returnPath: Optional return path for API navigation.
    /// - Throws: `SpeakerConnectError.invalidSource` if service not configured.
    public func addToFavorites(service: AudioService, trackId: String, returnPath: String? = nil) async throws {
        guard let svc = await serviceRegistry.service(for: service) else {
            throw SpeakerConnectError.invalidSource("Service \(service.id) not configured")
        }
        try await svc.addFavorite(trackId: trackId, returnPath: returnPath)
    }

    /// Remove track from favorites. `trackId` must be the service identifier (e.g., from currentSong.trackId or browse row id), not arbitrary input.
    /// - Parameters:
    ///   - service: Streaming service (e.g., `.tidal`, future `.spotify`).
    ///   - trackId: Service-specific track identifier.
    ///   - returnPath: Optional return path for API navigation.
    /// - Throws: `SpeakerConnectError.invalidSource` if service not configured.
    public func removeFromFavorites(service: AudioService, trackId: String, returnPath: String? = nil) async throws {
        guard let svc = await serviceRegistry.service(for: service) else {
            throw SpeakerConnectError.invalidSource("Service \(service.id) not configured")
        }
        try await svc.removeFavorite(trackId: trackId, returnPath: returnPath)
    }

    /// Whether the track is in the user's favorites. Requires track to appear in service's tracks browse.
    /// - Parameters:
    ///   - service: Streaming service (e.g., `.tidal`, future `.spotify`).
    ///   - trackId: Service-specific track identifier.
    /// - Returns: `true` if track is favorited, `false` otherwise.
    /// - Throws: `SpeakerConnectError.invalidSource` if service not configured.
    public func isFavorited(service: AudioService, trackId: String) async throws -> Bool {
        guard let svc = await serviceRegistry.service(for: service) else {
            throw SpeakerConnectError.invalidSource("Service \(service.id) not configured")
        }
        return try await svc.isFavorite(trackId: trackId)
    }

    /// Get available streaming services registered with this speaker.
    /// - Returns: Array of configured services (e.g., `[.tidal]`).
    public func availableServices() async -> [AudioService] {
        await serviceRegistry.availableServices()
    }
}

