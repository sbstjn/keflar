import Foundation
import Combine

// Speaker class relies on modular components:
// - Models/: SpeakerState, SpeakerEvents, CurrentSong, etc.
// - Parsers/: parseCurrentSong, parseDuration, etc.
// - State/: StateReducer, mergeEvents, SpeakerStateHolder, fetchInitialState
// - EventStream/: EventPollState
// - Utilities/: Constants, AirableProxyHelpers
// - Transport/: SpeakerClientProtocol, DefaultSpeakerClient

/// Sendable box for AsyncStream so Task closure can capture it without data-race.
private struct SendableStreamBox: @unchecked Sendable {
    let stream: AsyncStream<SpeakerEvents>
}

/// Holds the connection-event handler so EventPollState callback does not capture Speaker before init completes.
private final class ConnectionEventBox: @unchecked Sendable {
    var handler: (@Sendable (ConnectionEvent) -> Void)?
    func trigger(_ event: ConnectionEvent) { handler?(event) }
}

/// Holds a weak reference to Speaker so StateRefreshingClient can trigger state refresh after setData without capturing Speaker in init. Set by SpeakerConnection after creating the Speaker.
final class RefresherBox: @unchecked Sendable {
    weak var speaker: Speaker?
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

    func setDataWithBody(path: String, role: String, value: SendableBody) async throws {
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

// MARK: - Speaker (connected instance)

/// Connected speaker that shadows the device; state is updated from initial getData and from the event stream.
///
/// The library subscribes to the device event queue and long-polls automatically; events are merged into `state` internally. Observe `state` (or `$state`) for updates; no need to consume an event stream from the app.
///
/// **SwiftUI Integration:** `Speaker` conforms to `ObservableObject` with `@Published` state. SwiftUI views can observe state changes using `@StateObject` or `@ObservedObject`. State updates are automatically dispatched to the main thread for UI rendering.
///
/// **Concurrency:** `Speaker` is not `Sendable`. Use a single `Speaker` instance from one isolation context (e.g. one actor or the main thread). Do not pass it across actor boundaries or share it between concurrent tasks. Create one instance per connection and call its methods from the same context that holds the reference.
@MainActor
public final class Speaker: ObservableObject {
    public let model: String
    public let version: String
    /// Accumulated shadow state of the remote device; updated from event batches and initial getData. Published for SwiftUI observation.
    @Published public private(set) var state: SpeakerState

    /// Cached like/favorite actions for the current track; refetched when track changes and after setLiked. Nil when idle or no context.
    @Published public private(set) var playContextActions: PlayContextActions?

    /// Event-stream connection health. Use for "Reconnecting…" or routing to device picker when `.disconnected`.
    @Published public private(set) var connectionState: ConnectionState = .connected

    private let client: any SpeakerClientProtocol
    private let stateHolder: SpeakerStateHolder
    private let pollState: EventPollState
    private let events: AsyncStream<SpeakerEvents>
    private var eventDriveTask: Task<Void, Never>?
    private var lastPlayContextTrackKey: String?

    init(
        model: String,
        version: String,
        client: any SpeakerClientProtocol,
        queueId: String?,
        stateHolder: SpeakerStateHolder? = nil,
        pollTimeout: TimeInterval = defaultPollTimeout,
        connectionPolicy: ConnectionPolicy? = nil
    ) {
        self.model = model
        self.version = version
        let holder = stateHolder ?? SpeakerStateHolder()
        self.stateHolder = holder
        self.state = holder.state
        self.client = client
        let graceMinFailures = connectionPolicy?.graceMinFailures ?? connectionGraceMinFailures
        let graceDuration = connectionPolicy?.graceDuration ?? connectionGraceDuration
        let connectionEventBox = ConnectionEventBox()
        self.pollState = EventPollState(
            client: client,
            queueId: queueId,
            pollTimeout: pollTimeout,
            stateHolder: holder,
            graceMinFailures: graceMinFailures,
            graceDuration: graceDuration,
            onConnectionEvent: { [weak connectionEventBox] event in
                Task { @MainActor in connectionEventBox?.trigger(event) }
            }
        )
        self.events = AsyncStream(unfolding: { [pollState] in
            await pollState.pollOnce()
        })
        let streamBox = SendableStreamBox(stream: self.events)
        self.eventDriveTask = Task(name: "Speaker.eventDrive") {
            for await _ in streamBox.stream {}
        }
        connectionEventBox.handler = { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                switch event {
                case .reconnecting: self.connectionState = .reconnecting
                case .disconnected: self.connectionState = .disconnected
                case .recovered: self.connectionState = .connected
                }
            }
        }

        // Set up callback to publish state changes on main actor; refetch play context when track changes
        holder.onStateChange = { [weak self] box in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.state = box.value
                self.refreshPlayContextIfTrackChanged()
            }
        }
    }

    /// Compute a key that changes when the current track changes (for play context refetch).
    private func playContextTrackKey(from state: SpeakerState) -> String {
        let raw = state.other[playerDataPath] as? [String: Any]
        let path = raw.flatMap { extractPlayContextPath(from: $0) }
        let songTitle = raw.flatMap { parseCurrentSong(from: $0).title }
        return path ?? songTitle ?? "\(state.currentQueueIndex ?? -1)"
    }

    /// Refetch play context when track key changes; clear when idle.
    private func refreshPlayContextIfTrackChanged() {
        let key = playContextTrackKey(from: state)
        if key == lastPlayContextTrackKey { return }
        lastPlayContextTrackKey = key

        let raw = state.other[playerDataPath] as? [String: Any]
        let song = raw.map { parseCurrentSong(from: $0) }
        let isIdle = (song?.title == nil && song?.artist == nil) && (state.playerState != "playing")
        if isIdle {
            playContextActions = nil
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let actions = try? await self.fetchPlayContextActions()
            self.playContextActions = actions
        }
    }

    deinit {
        eventDriveTask?.cancel()
    }

    // MARK: - Setters

    /// Set physical source / power.
    public func setSource(_ source: PhysicalSource) async throws {
        let value: [String: Any] = ["type": "kefPhysicalSource", "kefPhysicalSource": source.rawValue]
        try await client.setDataWithBody(path: "settings:/kef/play/physicalSource", role: "value", value: SendableBody(value: value))
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
        let clamped = min(max(volume, 0), 100)
        let value: [String: Any] = ["type": "i32_", "i32_": clamped]
        try await client.setDataWithBody(path: "player:volume", role: "value", value: SendableBody(value: value))
    }

    /// Set mute on/off via settings:/mediaPlayer/mute.
    public func setMute(_ muted: Bool) async throws {
        let value: [String: Any] = ["type": "bool_", "bool_": muted]
        try await client.setDataWithBody(path: "settings:/mediaPlayer/mute", role: "value", value: SendableBody(value: value))
    }

    /// Set shuffle on/off via settings:/mediaPlayer/playMode. Preserves current repeat when turning shuffle off; turning shuffle on sends "shuffle" (device single-field: repeat off).
    public func setShuffle(_ on: Bool) async throws {
        let repeatMode = state.repeatMode ?? .off
        let mode = playModeString(shuffle: on, repeatMode: repeatMode)
        try await client.setDataWithBody(
            path: playModePath,
            role: "value",
            value: SendableBody(value: ["type": "playerPlayMode", "playerPlayMode": mode])
        )
    }

    /// Set repeat mode via settings:/mediaPlayer/playMode. Preserves shuffle when setting repeat off; setting repeat on sends shuffleRepeatOne/shuffleRepeatAll (device single-field: shuffle off).
    public func setRepeat(_ mode: RepeatMode) async throws {
        let shuffleOn = state.shuffle ?? false
        let modeString = playModeString(shuffle: shuffleOn, repeatMode: mode)
        try await client.setDataWithBody(
            path: playModePath,
            role: "value",
            value: SendableBody(value: ["type": "playerPlayMode", "playerPlayMode": modeString])
        )
    }

    /// Compute playerPlayMode string from shuffle and repeat. Device has a single field. When shuffle is off the official app sends repeatOne/repeatAll; when shuffle is on it sends shuffleRepeatOne/shuffleRepeatAll (see logs 002-play-pause).
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

    // MARK: - Transport (player:player/control, POST setData)

    /// Start playback (control "play"). On many devices bare "play" can clear the queue or start from default; for toggle/resume use `pause()` instead (device treats "pause" as play↔pause toggle).
    public func play() async throws {
        try await client.setDataWithBody(path: playerControlPath, role: "activate", value: SendableBody(value: ["control": "play"]))
    }

    /// Pause or resume (control "pause"). Device typically treats this as a toggle: playing → paused, paused → playing. Use for both pause and resume to avoid queue clear.
    public func pause() async throws {
        try await client.setDataWithBody(path: playerControlPath, role: "activate", value: SendableBody(value: ["control": "pause"]))
    }

    /// Skip to next track. If the device does not auto-resume, call play() afterward.
    public func playNext() async throws {
        try await client.setDataWithBody(path: playerControlPath, role: "activate", value: SendableBody(value: ["control": "next"]))
    }

    /// Skip to previous track. If the device does not auto-resume, call play() afterward.
    public func playPrevious() async throws {
        try await client.setDataWithBody(path: playerControlPath, role: "activate", value: SendableBody(value: ["control": "previous"]))
    }

    /// Seek to position in current track (playback position in milliseconds). Uses player:player/control with control "seekTime" and value "time" (ms), per official app.
    public func seekTo(playTimeMs: Int) async throws {
        try await client.setDataWithBody(path: playerControlPath, role: "activate", value: SendableBody(value: ["control": "seekTime", "time": playTimeMs]))
    }

    /// Play streaming service playlist by ID.
    /// - Parameters:
    ///   - service: Streaming service (e.g., `.tidal`, future `.spotify`).
    ///   - playlistId: Playlist UUID (e.g., from https://tidal.com/playlist/{id}).
    /// - Throws: SpeakerConnectError if service not configured or playlist unavailable.
    /// Uses the same flow as the app: getRows → clear queue → addexternalitems (nsdkRoles) → play by index 0.
    /// Resolves Airable proxy from shadow state, play queue, or shorthand getRows when cold.
    public func playPlaylist(service: AudioService, playlistId: String) async throws {
        var base = airableProxyBase
        if base == nil { base = try await resolveAirableProxyBase() }
        if base == nil { base = try await resolveAirableProxyBaseFromLinkService(service: service) }
        if base == nil {
            base = try await resolveAirableProxyBaseFromShorthand(service: service, playlistId: playlistId)
        }
        guard let base = base else {
            throw SpeakerConnectError.invalidSource("Airable proxy unknown for \(service.id); play something on \(service.id) once or ensure service is configured")
        }
        let playlistPath = "airable:\(base)/id/\(service.playlistPathComponent)/\(playlistId)"
        var response = try await client.getRows(path: playlistPath, from: 0, to: 50)
        if let redirect = response["rowsRedirect"] as? String, !redirect.isEmpty {
            response = try await client.getRows(path: redirect, from: 0, to: 50)
        }
        guard let rows = response["rows"] as? [[String: Any]], !rows.isEmpty else {
            throw SpeakerConnectError.invalidResponseStructure
        }
        let tracks = rows.compactMap { resolveTrackFromRow($0) }
        guard !tracks.isEmpty else {
            throw SpeakerConnectError.invalidResponseStructure
        }
        // Clear play queue (same as app: playlists:pl/clear, role activate, value plid:0).
        try await client.setDataWithBody(path: "playlists:pl/clear", role: "activate", value: SendableBody(value: ["plid": 0]))
        // Add all playlist tracks to queue (playlists:pl/addexternalitems; each item has nsdkRoles = JSON string of track).
        let items: [[String: Any]] = try tracks.map { track in
            ["nsdkRoles": try nsdkRolesJSONString(from: track)]
        }
        try await client.setDataWithBody(
            path: "playlists:pl/addexternalitems",
            role: "activate",
            value: SendableBody(value: ["mode": "append", "plid": "0", "items": items])
        )
        // Start playback at index 0 in the queue (mediaRoles = playlists:pq/getitems). App sends timestamp and playLogicPath.
        guard let firstTrack = resolveFirstTrack(from: rows) else {
            throw SpeakerConnectError.invalidResponseStructure
        }
        let queueMediaRoles: [String: Any] = [
            "type": "container",
            "path": "playlists:pq/getitems",
            "containerType": "none",
            "title": "PlayQueue tracks",
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "mediaData": ["metaData": ["playLogicPath": "playlists:playlogic"]],
        ]
        let playValue: [String: Any] = [
            "control": "play",
            "type": "itemInContainer",
            "trackRoles": firstTrack,
            "index": 0,
            "mediaRoles": queueMediaRoles,
        ]
        try await client.setDataWithBody(path: playerControlPath, role: "activate", value: SendableBody(value: playValue))
    }

    /// Play Tidal playlist by UUID (e.g. from https://tidal.com/playlist/a1696225-3c8e-4333-99a1-a77afa213f24). Convenience wrapper for `playPlaylist(service: .tidal, playlistId:)`.
    public func playTidalPlaylist(playlistId: String) async throws {
        try await playPlaylist(service: .tidal, playlistId: playlistId)
    }

    /// Airable proxy base URL (e.g. `https://{proxy}.airable.io`) from shadow state trackRoles.path; nil if never played.
    public var airableProxyBase: String? {
        cachedPlayerData?.path.flatMap { proxyBaseFromTrackRolesPath($0) }
    }

    /// Resolve Airable proxy base when shadow state has none: try getData(player:player/data) then getRows(play queue). Used to play Tidal when nothing is currently playing.
    private func resolveAirableProxyBase() async throws -> String? {
        let data = try await client.getData(path: playerDataPath)
        StateReducer.applyToState(path: playerDataPath, dict: data, state: &stateHolder.state)
        stateHolder.notifyStateChanged()
        let playerData = PlayerDataDTO(dict: data)
        if let path = playerData.path, let base = proxyBaseFromTrackRolesPath(path) {
            return base
        }
        let response = try await client.getRows(path: "playlists:pq/getitems", from: 0, to: 1)
        guard let rows = response["rows"] as? [[String: Any]], let first = rows.first else { return nil }
        return proxyBaseFromQueueRow(first)
    }

    /// Resolve Airable proxy when cold: getRows(airable:linkService_{service}) returns rowsRedirect with proxy URL.
    private func resolveAirableProxyBaseFromLinkService(service: AudioService) async throws -> String? {
        let path = "airable:\(service.linkServicePath)"
        let response = try await client.getRows(path: path, from: 0, to: 19)
        guard let redirect = response["rowsRedirect"] as? String, !redirect.isEmpty else { return nil }
        return proxyBaseFromLinkServiceRedirect(redirect)
    }

    /// Resolve Airable proxy using shorthand path (no proxy in URL). Speaker may return rowsRedirect with full URL or rows with path containing proxy.
    private func resolveAirableProxyBaseFromShorthand(service: AudioService, playlistId: String) async throws -> String? {
        let shorthandPath = "airable:\(service.playlistPathComponent)/\(playlistId)"
        let response = try await client.getRows(path: shorthandPath, from: 0, to: 50)
        if let redirect = response["rowsRedirect"] as? String, !redirect.isEmpty,
           let base = proxyBaseFromTrackRolesPath(redirect) {
            return base
        }
        if let rows = response["rows"] as? [[String: Any]], let first = rows.first,
           let base = proxyBaseFromQueueRow(first) {
            return base
        }
        if let rows = response["rows"] as? [[String: Any]], let first = rows.first {
            let track = (first["value"] as? [String: Any]) ?? (first["itemValue"] as? [String: Any]) ?? first
            if let path = track["path"] as? String, path.contains("airable.io"), let base = proxyBaseFromTrackRolesPath(path) {
                return base
            }
        }
        return nil
    }

    /// Check if streaming service is configured on the speaker (user linked). Uses getRows(airable:linkService_{service}); configured when rowsRedirect is a full proxy URL.
    public func hasServiceConfiguration(_ service: AudioService) async throws -> Bool {
        let path = "airable:\(service.linkServicePath)"
        let response = try await client.getRows(path: path, from: 0, to: 19)
        guard let redirect = response["rowsRedirect"] as? String, !redirect.isEmpty else { return false }
        return proxyBaseFromLinkServiceRedirect(redirect) != nil
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
        (state.other[playerDataPath] as? [String: Any]).map { PlayerDataDTO(dict: $0) }
    }

    /// Current song (title, artist, album, etc.). Uses shadow state; no extra request.
    public var currentSong: CurrentSong? {
        cachedPlayerData.map { parseCurrentSong(from: $0.raw) }
    }

    /// Audio codec/quality info (codec, sample rates, channels, serviceID). Uses shadow state only — no extra getData; same source as `currentSong` and `isPlaying`.
    public var audioCodecInfo: AudioCodecInfo? {
        cachedPlayerData.map { parseAudioCodecInfo(from: $0.raw) }
    }

    // MARK: - Play context (like/favorite, current track)

    /// Refresh cached player data from the device (getData player:player/data). Use when shadow state may be stale (e.g. after track change) so currentPlayContextPath and currentSong are up to date.
    public func refreshPlayerData() async throws {
        let data = try await client.getData(path: playerDataPath)
        StateReducer.applyToState(path: playerDataPath, dict: data, state: &stateHolder.state)
        stateHolder.notifyStateChanged()
    }

    /// After a control/setData action, refetch player data, playTime, volume, mute and playMode from the device and push to state so the UI updates even when the event stream is not delivering. Called centrally from StateRefreshingClient after every successful setDataWithBody.
    func refreshStateAfterControlAction() async {
        async let d = client.getData(path: playerDataPath)
        async let p = client.getData(path: playTimePath)
        async let v = client.getData(path: "player:volume")
        async let m = client.getData(path: "settings:/mediaPlayer/mute")
        async let pm = client.getData(path: playModePath)
        let data = try? await d
        let playTime = try? await p
        let volume = try? await v
        let mute = try? await m
        let playMode = try? await pm
        if let data {
            StateReducer.applyToState(path: playerDataPath, dict: data, state: &stateHolder.state)
        }
        if let playTime {
            StateReducer.applyToState(path: playTimePath, dict: playTime, state: &stateHolder.state)
        }
        if let volume {
            StateReducer.applyToState(path: "player:volume", dict: volume, state: &stateHolder.state)
        }
        if let mute {
            StateReducer.applyToState(path: "settings:/mediaPlayer/mute", dict: mute, state: &stateHolder.state)
        }
        if let playMode {
            StateReducer.applyToState(path: playModePath, dict: playMode, state: &stateHolder.state)
        }
        if data != nil || playTime != nil || volume != nil || mute != nil || playMode != nil {
            stateHolder.notifyStateChanged()
        }
    }

    /// Content play context path for the current track (from shadow state). Nil when nothing is playing or track has no context (e.g. non-streaming source). Use with `fetchPlayContextActions()` to get like/favorite actions.
    public var currentPlayContextPath: String? {
        cachedPlayerData.flatMap { extractPlayContextPath(from: $0.raw) }
    }

    /// Fetch available actions for the current track (like/unlike, add to playlist). Uses `currentPlayContextPath` when present; otherwise derives path from current queue row (getRows playlists:pq/getitems). Returns nil if no context. Throws on network/API errors.
    public func fetchPlayContextActions() async throws -> PlayContextActions? {
        var path = currentPlayContextPath
        if path == nil, let queuePath = try await playContextPathFromCurrentQueueRow() {
            path = queuePath
        }
        guard let path else { return nil }
        let response = try await client.getRows(path: path, from: 0, to: 9)
        return parsePlayContextActions(from: response)
    }

    /// Derive play context path from the current queue item when player data does not include it (e.g. device omits contentPlayContextPath in getData).
    private func playContextPathFromCurrentQueueRow() async throws -> String? {
        let index = state.currentQueueIndex ?? 0
        let response = try await client.getRows(path: playQueuePath, from: index, to: index)
        let rows = response["rows"] as? [[String: Any]] ?? []
        guard let first = rows.first else { return nil }
        return extractPlayContextPathFromQueueRow(first)
    }

    /// Invoke an action by path (e.g. from `PlayContextActions.favoriteInsertPath`). Uses POST setData with role "activate" and empty value.
    public func activateAction(path: String) async throws {
        try await client.setDataWithBody(path: path, role: "activate", value: SendableBody(value: [:]))
    }

    /// Set liked (favorite) state for the current track. Fetches play context actions if needed; throws if no context or action unavailable (e.g. not Tidal). Updates playContextActions after success.
    public func setLiked(_ liked: Bool) async throws {
        let actions = try await fetchPlayContextActions()
        guard let actions = actions else {
            throw SpeakerConnectError.invalidSource("no play context for current track")
        }
        let path: String?
        if liked {
            path = actions.favoriteInsertPath
        } else {
            path = actions.favoriteRemovePath
        }
        guard let path = path else {
            throw SpeakerConnectError.invalidSource(liked ? "add to favorites not available" : "remove from favorites not available")
        }
        try await activateAction(path: path)
        try? await Task.sleep(for: .seconds(playContextRefetchDelayAfterActivate))
        var updated = try? await fetchPlayContextActions()
        if updated?.isLiked != liked, updated != nil {
            try? await Task.sleep(for: .seconds(playContextRefetchDelayAfterActivate))
            updated = try? await fetchPlayContextActions()
        }
        playContextActions = updated
    }

    // MARK: - Play queue

    /// Fetch the currently playing queue from the speaker. Uses getRows(playlists:pq/getitems). Range limited by client (e.g. max 1000 items per call). Returns items in the requested range and total queue length (rowsCount) when provided by the API.
    public func fetchPlayQueue(from startIndex: Int = 0, to endIndex: Int = 999) async throws -> PlayQueueResult {
        let response = try await client.getRows(path: playQueuePath, from: startIndex, to: endIndex)
        return parsePlayQueue(from: response)
    }

    /// When connected with `countRequests: true`, returns counts of HTTP requests by endpoint type; otherwise nil.
    public func getRequestCounts() async -> RequestCounts? {
        await client.getRequestCounts()
    }
}

