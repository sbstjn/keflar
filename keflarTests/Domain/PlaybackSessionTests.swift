import XCTest
@testable import keflar

/// Tests for PlaybackSession aggregate: playback control, queue operations, and state properties.
@MainActor
final class PlaybackSessionTests: XCTestCase {
    private var mockTransport: MockSpeakerTransport!
    private var mockClient: MockSpeakerClient!
    private var mockPlaylistManager: EnhancedMockPlaylistManager!
    private var stateHolder: TestStateHolder!
    private var session: PlaybackSession!

    override func setUp() async throws {
        try await super.setUp()
        mockTransport = MockSpeakerTransport()
        mockClient = MockSpeakerClient()
        mockPlaylistManager = EnhancedMockPlaylistManager()
        stateHolder = TestStateHolder(
            state: SpeakerState(
                playerState: .playing,
                playTime: 30000,
                duration: 180000,
                currentQueueIndex: 2,
                shuffle: false,
                repeatMode: .off
            )
        )
        let playbackControl = PlaybackControl(
            transport: mockTransport,
            client: mockClient,
            getState: stateHolder.getState
        )
        let queueManager = QueueManager(playlistManager: mockPlaylistManager)
        session = PlaybackSession(
            playbackControl: playbackControl,
            queueManager: queueManager,
            getState: stateHolder.getState
        )
    }

    // MARK: - State Properties

    func testPlayerStateReturnsStateValue() {
        XCTAssertEqual(session.playerState, .playing)
    }

    func testPlayTimeReturnsStateValue() {
        XCTAssertEqual(session.playTime, 30000)
    }

    func testDurationReturnsStateValue() {
        XCTAssertEqual(session.duration, 180000)
    }

    func testCurrentQueueIndexReturnsStateValue() {
        XCTAssertEqual(session.currentQueueIndex, 2)
    }

    func testShuffleReturnsStateValue() {
        XCTAssertEqual(session.shuffle, false)
    }

    func testRepeatModeReturnsStateValue() {
        XCTAssertEqual(session.repeatMode, .off)
    }

    func testStatePropertiesReturnNilWhenNotSet() {
        stateHolder.state = SpeakerState()
        XCTAssertNil(session.playerState)
        XCTAssertNil(session.playTime)
        XCTAssertNil(session.duration)
        XCTAssertNil(session.currentQueueIndex)
        XCTAssertNil(session.shuffle)
        XCTAssertNil(session.repeatMode)
    }

    func testStateUpdatesAreReflected() {
        stateHolder.state = stateHolder.state.with(playerState: .paused, playTime: 45000)
        XCTAssertEqual(session.playerState, .paused)
        XCTAssertEqual(session.playTime, 45000)
    }

    // MARK: - play()

    func testPlayDelegatesToTransport() async throws {
        try await session.play()
        XCTAssertEqual(mockTransport.playCalls, 1)
    }

    func testPlayPropagatesError() async {
        mockTransport.playError = SpeakerConnectError.connectionUnavailable(.timeout)
        do {
            try await session.play()
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is SpeakerConnectError)
        }
    }

    // MARK: - pause()

    func testPauseDelegatesToTransport() async throws {
        try await session.pause()
        XCTAssertEqual(mockTransport.pauseCalls, 1)
    }

    func testPausePropagatesError() async {
        mockTransport.pauseError = SpeakerConnectError.invalidResponseStructure
        do {
            try await session.pause()
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is SpeakerConnectError)
        }
    }

    // MARK: - playNext()

    func testPlayNextDelegatesToTransport() async throws {
        try await session.playNext()
        XCTAssertEqual(mockTransport.playNextCalls, 1)
    }

    func testPlayNextPropagatesError() async {
        mockTransport.playNextError = SpeakerConnectError.connectionUnavailable(.connectionLost)
        do {
            try await session.playNext()
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is SpeakerConnectError)
        }
    }

    // MARK: - playPrevious()

    func testPlayPreviousDelegatesToTransport() async throws {
        try await session.playPrevious()
        XCTAssertEqual(mockTransport.playPreviousCalls, 1)
    }

    func testPlayPreviousPropagatesError() async {
        mockTransport.playPreviousError = SpeakerConnectError.invalidURL
        do {
            try await session.playPrevious()
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is SpeakerConnectError)
        }
    }

    // MARK: - seekTo()

    func testSeekToDelegatesToTransport() async throws {
        try await session.seekTo(playTimeMs: 60000)
        XCTAssertEqual(mockTransport.seekToCalls, [60000])
    }

    func testSeekToWithMultipleValues() async throws {
        try await session.seekTo(playTimeMs: 0)
        try await session.seekTo(playTimeMs: 120000)
        XCTAssertEqual(mockTransport.seekToCalls, [0, 120000])
    }

    func testSeekToPropagatesError() async {
        mockTransport.seekToError = SpeakerConnectError.connectionUnavailable(.notConnectedToInternet)
        do {
            try await session.seekTo(playTimeMs: 30000)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is SpeakerConnectError)
        }
    }

    // MARK: - setShuffle()

    func testSetShuffleOnSendsCorrectModeString() async throws {
        stateHolder.state = stateHolder.state.with(shuffle: false, repeatMode: .off)
        try await session.setShuffle(true)
        XCTAssertEqual(mockClient.setDataWithBodyCalls.count, 1)
        XCTAssertEqual(mockClient.setDataWithBodyCalls[0].path, "settings:/mediaPlayer/playMode")
        XCTAssertEqual(mockClient.setDataWithBodyCalls[0].role, "value")
    }

    func testSetShuffleOffSendsCorrectModeString() async throws {
        stateHolder.state = stateHolder.state.with(shuffle: true, repeatMode: .off)
        try await session.setShuffle(false)
        XCTAssertEqual(mockClient.setDataWithBodyCalls.count, 1)
        XCTAssertEqual(mockClient.setDataWithBodyCalls[0].path, "settings:/mediaPlayer/playMode")
    }

    func testSetShuffleWithRepeatOne() async throws {
        stateHolder.state = stateHolder.state.with(shuffle: false, repeatMode: .one)
        try await session.setShuffle(true)
        XCTAssertEqual(mockClient.setDataWithBodyCalls.count, 1)
    }

    func testSetShuffleWithRepeatAll() async throws {
        stateHolder.state = stateHolder.state.with(shuffle: false, repeatMode: .all)
        try await session.setShuffle(true)
        XCTAssertEqual(mockClient.setDataWithBodyCalls.count, 1)
    }

    // MARK: - setRepeat()

    func testSetRepeatOffSendsCorrectModeString() async throws {
        stateHolder.state = stateHolder.state.with(shuffle: false, repeatMode: .one)
        try await session.setRepeat(.off)
        XCTAssertEqual(mockClient.setDataWithBodyCalls.count, 1)
        XCTAssertEqual(mockClient.setDataWithBodyCalls[0].path, "settings:/mediaPlayer/playMode")
    }

    func testSetRepeatOneSendsCorrectModeString() async throws {
        stateHolder.state = stateHolder.state.with(shuffle: false, repeatMode: .off)
        try await session.setRepeat(.one)
        XCTAssertEqual(mockClient.setDataWithBodyCalls.count, 1)
    }

    func testSetRepeatAllSendsCorrectModeString() async throws {
        stateHolder.state = stateHolder.state.with(shuffle: false, repeatMode: .off)
        try await session.setRepeat(.all)
        XCTAssertEqual(mockClient.setDataWithBodyCalls.count, 1)
    }

    func testSetRepeatWithShuffleOn() async throws {
        stateHolder.state = stateHolder.state.with(shuffle: true, repeatMode: .off)
        try await session.setRepeat(.all)
        XCTAssertEqual(mockClient.setDataWithBodyCalls.count, 1)
    }

    // MARK: - fetchPlayQueue()

    func testFetchPlayQueueDelegatesToQueueManager() async throws {
        mockPlaylistManager.fetchPlayQueueResult = PlayQueueResult(
            items: [
                PlayQueueItem(index: 0, id: "1", title: "Song 1"),
                PlayQueueItem(index: 1, id: "2", title: "Song 2")
            ],
            totalCount: 10
        )
        let result = try await session.fetchPlayQueue(from: 0, to: 1)
        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.totalCount, 10)
        XCTAssertEqual(mockPlaylistManager.fetchPlayQueueCalls.count, 1)
        XCTAssertEqual(mockPlaylistManager.fetchPlayQueueCalls[0].from, 0)
        XCTAssertEqual(mockPlaylistManager.fetchPlayQueueCalls[0].to, 1)
    }

    func testFetchPlayQueuePropagatesError() async {
        mockPlaylistManager.fetchPlayQueueError = SpeakerConnectError.invalidResponseStructure
        do {
            _ = try await session.fetchPlayQueue(from: 0, to: 10)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is SpeakerConnectError)
        }
    }

    // MARK: - playPlaylist()

    func testPlayPlaylistDelegatesToQueueManager() async throws {
        try await session.playPlaylist(service: .tidal, playlistId: "test-playlist")
        XCTAssertEqual(mockPlaylistManager.playPlaylistCalls.count, 1)
        XCTAssertEqual(mockPlaylistManager.playPlaylistCalls[0].service.id, "tidal")
        XCTAssertEqual(mockPlaylistManager.playPlaylistCalls[0].playlistId, "test-playlist")
    }

    func testPlayPlaylistPropagatesError() async {
        mockPlaylistManager.playPlaylistError = SpeakerConnectError.serviceNotConfigured(service: "tidal")
        do {
            try await session.playPlaylist(service: .tidal, playlistId: "test-playlist")
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is SpeakerConnectError)
        }
    }

    // MARK: - hasServiceConfiguration()

    func testHasServiceConfigurationDelegatesToQueueManager() async throws {
        mockPlaylistManager.hasServiceConfigurationResult = true
        let result = try await session.hasServiceConfiguration(.tidal)
        XCTAssertTrue(result)
        XCTAssertEqual(mockPlaylistManager.hasServiceConfigurationCalls.count, 1)
        XCTAssertEqual(mockPlaylistManager.hasServiceConfigurationCalls[0].id, "tidal")
    }

    func testHasServiceConfigurationReturnsFalseWhenNotConfigured() async throws {
        mockPlaylistManager.hasServiceConfigurationResult = false
        let result = try await session.hasServiceConfiguration(.tidal)
        XCTAssertFalse(result)
    }

    // MARK: - State Reconfiguration

    func testConfigureGetStateUpdatesStateClosure() {
        let newState = SpeakerState(playerState: .paused, playTime: 99000)
        let newHolder = TestStateHolder(state: newState)
        session.configureGetState(newHolder.getState)
        XCTAssertEqual(session.playerState, .paused)
        XCTAssertEqual(session.playTime, 99000)
    }
}

// MARK: - Enhanced Mock PlaylistManager

final class EnhancedMockPlaylistManager: PlaylistManager, @unchecked Sendable {
    var playPlaylistCalls: [(service: AudioService, playlistId: String)] = []
    var fetchPlayQueueCalls: [(from: Int, to: Int)] = []
    var hasServiceConfigurationCalls: [AudioService] = []

    var playPlaylistError: Error?
    var fetchPlayQueueResult: PlayQueueResult = PlayQueueResult(items: [], totalCount: nil)
    var fetchPlayQueueError: Error?
    var hasServiceConfigurationResult = true

    func playPlaylist(service: AudioService, playlistId: String) async throws {
        if let error = playPlaylistError { throw error }
        playPlaylistCalls.append((service, playlistId))
    }

    func fetchPlayQueue(from startIndex: Int, to endIndex: Int) async throws -> PlayQueueResult {
        if let error = fetchPlayQueueError { throw error }
        fetchPlayQueueCalls.append((from: startIndex, to: endIndex))
        return fetchPlayQueueResult
    }

    func hasServiceConfiguration(_ service: AudioService) async throws -> Bool {
        hasServiceConfigurationCalls.append(service)
        return hasServiceConfigurationResult
    }
}
