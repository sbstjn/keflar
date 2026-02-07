import Foundation
import Observation

// Speaker class relies on modular components:
// - Models/: SpeakerState, SpeakerEvents, CurrentSong, etc.
// - Parsers/: parseCurrentSong, parseDuration, etc.
// - State/: StateApplier, EventParser, mergeEvents, SpeakerStateHolder, fetchInitialState
// - EventStream/: EventPollState
// - Utilities/: Constants, AirableProxyHelpers
// - Transport/: SpeakerClientProtocol, SpeakerTransport, DefaultSpeakerClient

/// Sendable box for AsyncStream so Task closure can capture it without data-race.
private struct SendableStreamBox: @unchecked Sendable {
    let stream: AsyncStream<SpeakerEvents>
}

/// Holds a weak reference to Speaker so StateRefreshingClient can trigger state refresh after setData without capturing Speaker in init. Set by SpeakerConnection after creating the Speaker.
final class RefresherBox: @unchecked Sendable {
    weak var speaker: Speaker?
}

/// Holds the event-drive task so deinit can cancel it from a nonisolated context (Speaker is @MainActor).
private final class EventDriveTaskBox: @unchecked Sendable {
    var task: Task<Void, Never>?
}

/// Wraps a SpeakerClientProtocol and invokes state refresh on the RefresherBox's speaker after every successful setDataWithBody. Ensures UI state updates after any API write without per-handler calls.
final class StateRefreshingClient: SpeakerClientProtocol, @unchecked Sendable {
    private let wrapped: any SpeakerClientProtocol
    private let refresher: RefresherBox

    init(wrapping wrapped: any SpeakerClientProtocol, refresher: RefresherBox) {
        self.wrapped = wrapped
        self.refresher = refresher
    }

    func getData(path: String) async throws -> [String: Any] { try await wrapped.getData(path: path) }

    func setDataWithBody<E: Encodable>(path: String, role: String, value: E) async throws {
        try await wrapped.setDataWithBody(path: path, role: role, value: value)
        Task { @MainActor in await refresher.speaker?.refreshStateAfterControlAction() }
    }

    func getRows(path: String, from: Int, to: Int) async throws -> [String: Any] {
        try await wrapped.getRows(path: path, from: from, to: to)
    }

    func modifyQueue() async throws -> String { try await wrapped.modifyQueue() }

    func pollQueue(queueId: String, timeout: TimeInterval) async throws -> [[String: Any]] {
        try await wrapped.pollQueue(queueId: queueId, timeout: timeout)
    }

    func getRequestCounts() async -> RequestCounts? { await wrapped.getRequestCounts() }
}

// MARK: - SpeakerControl (internal)

/// Encapsulates control API (transport, play mode, playlist). Speaker delegates control methods to this type.
@MainActor
private final class SpeakerControl {
    private let transport: any SpeakerTransport
    private let client: any SpeakerClientProtocol
    private let stateHolder: SpeakerStateHolder
    private let playlistManager: any PlaylistManager
    private var getState: () -> SpeakerState

    init(
        transport: any SpeakerTransport,
        client: any SpeakerClientProtocol,
        stateHolder: SpeakerStateHolder,
        playlistManager: any PlaylistManager,
        getState: @escaping () -> SpeakerState
    ) {
        self.transport = transport
        self.client = client
        self.stateHolder = stateHolder
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

    func refreshPlayerData() async throws {
        let data = try await client.getData(path: playerDataPath.path)
        await stateHolder.updateState(path: playerDataPath.path, dict: SendableDict(value: data))
    }

    func refreshStateAfterControlAction() async {
        async let d = client.getData(path: playerDataPath.path)
        async let p = client.getData(path: playTimePath.path)
        async let v = client.getData(path: APIPath.volume.path)
        async let m = client.getData(path: APIPath.mute.path)
        async let pm = client.getData(path: playModePath.path)
        let data = try? await d
        let playTime = try? await p
        let volume = try? await v
        let mute = try? await m
        let playMode = try? await pm
        if let data {
            await stateHolder.updateState(path: playerDataPath.path, dict: SendableDict(value: data))
        }
        if let playTime {
            await stateHolder.updateState(path: playTimePath.path, dict: SendableDict(value: playTime))
        }
        if let volume {
            await stateHolder.updateState(path: APIPath.volume.path, dict: SendableDict(value: volume))
        }
        if let mute {
            await stateHolder.updateState(path: APIPath.mute.path, dict: SendableDict(value: mute))
        }
        if let playMode {
            await stateHolder.updateState(path: playModePath.path, dict: SendableDict(value: playMode))
        }
    }

    func fetchPlayQueue(from startIndex: Int, to endIndex: Int) async throws -> PlayQueueResult {
        try await playlistManager.fetchPlayQueue(from: startIndex, to: endIndex)
    }

    func hasServiceConfiguration(_ service: AudioService) async throws -> Bool {
        try await playlistManager.hasServiceConfiguration(service)
    }

    func getRequestCounts() async -> RequestCounts? {
        await client.getRequestCounts()
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
    private let client: any SpeakerClientProtocol
    private let stateHolder: SpeakerStateHolder
    private let pollState: EventPollState
    private let events: AsyncStream<SpeakerEvents>
    private let eventDriveTaskBox = EventDriveTaskBox()
    private let connectionCoordinator = ConnectionEventCoordinator()

    init(
        model: String,
        version: String,
        client: any SpeakerClientProtocol,
        transport: any SpeakerTransport,
        playlistManager: any PlaylistManager,
        queueId: String?,
        stateHolder: SpeakerStateHolder,
        stateStream: AsyncStream<SpeakerState>,
        pollTimeout: TimeInterval = defaultPollTimeout,
        connectionPolicy: ConnectionPolicy? = nil
    ) {
        self.model = model
        self.version = version
        self.stateHolder = stateHolder
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
            stateHolder: stateHolder,
            playlistManager: playlistManager,
            getState: { SpeakerState() }
        )
        self.pollState = EventPollState(
            client: client,
            queueId: queueId,
            pollTimeout: pollTimeout,
            stateHolder: stateHolder,
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

        Task { @MainActor [weak self] in
            guard let self else { return }
            for await newState in stateStream {
                self.state = newState
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
        try await control.setSource(source)
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
        try await control.setVolume(volume)
    }

    /// Set mute on/off via settings:/mediaPlayer/mute.
    public func setMute(_ muted: Bool) async throws {
        try await control.setMute(muted)
    }

    /// Set shuffle on/off via settings:/mediaPlayer/playMode. Preserves current repeat when turning shuffle off; turning shuffle on sends "shuffle" (device single-field: repeat off).
    public func setShuffle(_ on: Bool) async throws {
        try await control.setShuffle(on)
    }

    /// Set repeat mode via settings:/mediaPlayer/playMode. Preserves shuffle when setting repeat off; setting repeat on sends shuffleRepeatOne/shuffleRepeatAll (device single-field: shuffle off).
    public func setRepeat(_ mode: RepeatMode) async throws {
        try await control.setRepeat(mode)
    }

    // MARK: - Transport (player:player/control, POST setData)

    /// Start playback (control "play"). On many devices bare "play" can clear the queue or start from default; for toggle/resume use `pause()` instead (device treats "pause" as play↔pause toggle).
    public func play() async throws {
        try await control.play()
    }

    /// Pause or resume (control "pause"). Device typically treats this as a toggle: playing → paused, paused → playing. Use for both pause and resume to avoid queue clear.
    public func pause() async throws {
        try await control.pause()
    }

    /// Skip to next track. If the device does not auto-resume, call play() afterward.
    public func playNext() async throws {
        try await control.playNext()
    }

    /// Skip to previous track. If the device does not auto-resume, call play() afterward.
    public func playPrevious() async throws {
        try await control.playPrevious()
    }

    /// Seek to position in current track (playback position in milliseconds). Uses player:player/control with control "seekTime" and value "time" (ms), per official app.
    public func seekTo(playTimeMs: Int) async throws {
        try await control.seekTo(playTimeMs: playTimeMs)
    }

    /// Play streaming service playlist by ID.
    /// - Parameters:
    ///   - service: Streaming service (e.g., `.tidal`, future `.spotify`).
    ///   - playlistId: Playlist UUID (e.g., from https://tidal.com/playlist/{id}).
    /// - Throws: SpeakerConnectError if service not configured or playlist unavailable.
    public func playPlaylist(service: AudioService, playlistId: String) async throws {
        try await control.playPlaylist(service: service, playlistId: playlistId)
    }

    /// Play Tidal playlist by UUID (e.g. from https://tidal.com/playlist/a1696225-3c8e-4333-99a1-a77afa213f24). Convenience wrapper for `playPlaylist(service: .tidal, playlistId:)`.
    public func playTidalPlaylist(playlistId: String) async throws {
        try await playPlaylist(service: .tidal, playlistId: playlistId)
    }

    /// Airable proxy base URL (e.g. `https://{proxy}.airable.io`) from shadow state trackRoles.path; nil if never played.
    public var airableProxyBase: String? {
        cachedPlayerData?.path.flatMap { proxyBaseFromTrackRolesPath($0) }
    }

    /// Check if streaming service is configured on the speaker (user linked).
    public func hasServiceConfiguration(_ service: AudioService) async throws -> Bool {
        try await control.hasServiceConfiguration(service)
    }

    /// Whether Tidal is configured on the speaker (user linked). Convenience wrapper for `hasServiceConfiguration(.tidal)`.
    public func hasTidalConfiguration() async throws -> Bool {
        try await hasServiceConfiguration(.tidal)
    }

    // MARK: - Getters (player state)

    /// Whether the speaker is currently playing. Uses shadow state (`player:player/data` fetched on connect and from event stream).
    public func isPlaying() -> Bool {
        state.playerState == "playing"
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

    /// Refresh cached player data from the device (getData player:player/data). Use when shadow state may be stale (e.g. after track change) so currentSong and playback state are up to date.
    public func refreshPlayerData() async throws {
        try await control.refreshPlayerData()
    }

    /// After a control/setData action, refetch player data, playTime, volume, mute and playMode from the device and push to state. Called from StateRefreshingClient after every successful setDataWithBody.
    func refreshStateAfterControlAction() async {
        await control.refreshStateAfterControlAction()
    }

    // MARK: - Play queue

    /// Fetch the currently playing queue from the speaker. Range limited by client (e.g. max 1000 items per call). Returns items in the requested range and total queue length (rowsCount) when provided by the API.
    public func fetchPlayQueue(from startIndex: Int = 0, to endIndex: Int = 999) async throws -> PlayQueueResult {
        try await control.fetchPlayQueue(from: startIndex, to: endIndex)
    }

    /// When connected with `countRequests: true`, returns counts of HTTP requests by endpoint type; otherwise nil.
    public func getRequestCounts() async -> RequestCounts? {
        await control.getRequestCounts()
    }
}

