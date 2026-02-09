import XCTest
@testable import keflar

/// Tests for SpeakerDevice aggregate: hardware control and state properties.
@MainActor
final class SpeakerDeviceTests: XCTestCase {
    private var mockTransport: MockSpeakerTransport!
    private var stateHolder: TestStateHolder!
    private var device: SpeakerDevice!

    override func setUp() async throws {
        try await super.setUp()
        mockTransport = MockSpeakerTransport()
        stateHolder = TestStateHolder(
            state: SpeakerState(
                source: .wifi,
                volume: 50,
                mute: false
            )
        )
        let hardwareControl = HardwareControl(transport: mockTransport)
        device = SpeakerDevice(hardwareControl: hardwareControl, getState: stateHolder.getState)
    }

    // MARK: - State Properties

    func testSourceReturnsStateValue() {
        XCTAssertEqual(device.source, .wifi)
    }

    func testVolumeReturnsStateValue() {
        XCTAssertEqual(device.volume, 50)
    }

    func testIsMutedReturnsStateValue() {
        XCTAssertEqual(device.isMuted, false)
    }

    func testSourceReturnsNilWhenStateIsNil() {
        stateHolder.state = SpeakerState(source: nil)
        XCTAssertNil(device.source)
    }

    func testVolumeReturnsNilWhenStateIsNil() {
        stateHolder.state = SpeakerState(volume: nil)
        XCTAssertNil(device.volume)
    }

    func testIsMutedReturnsNilWhenStateIsNil() {
        stateHolder.state = SpeakerState(mute: nil)
        XCTAssertNil(device.isMuted)
    }

    func testStateUpdatesAreReflected() {
        stateHolder.state = stateHolder.state.with(volume: 75)
        XCTAssertEqual(device.volume, 75)
    }

    // MARK: - setSource

    func testSetSourceDelegatesToTransport() async throws {
        try await device.setSource(.bluetooth)
        XCTAssertEqual(mockTransport.setSourceCalls.count, 1)
        XCTAssertEqual(mockTransport.setSourceCalls[0], .bluetooth)
    }

    func testSetSourceWithDifferentSources() async throws {
        for source in PhysicalSource.allCases {
            try await device.setSource(source)
        }
        XCTAssertEqual(mockTransport.setSourceCalls.count, PhysicalSource.allCases.count)
        XCTAssertEqual(mockTransport.setSourceCalls, PhysicalSource.allCases)
    }

    func testSetSourcePropagatesError() async {
        mockTransport.setSourceError = SpeakerConnectError.connectionUnavailable(.timeout)
        do {
            try await device.setSource(.tv)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is SpeakerConnectError)
        }
    }

    // MARK: - setVolume

    func testSetVolumeDelegatesToTransport() async throws {
        try await device.setVolume(25)
        XCTAssertEqual(mockTransport.setVolumeCalls.count, 1)
        XCTAssertEqual(mockTransport.setVolumeCalls[0], 25)
    }

    func testSetVolumeWithBoundaryValues() async throws {
        try await device.setVolume(0)
        try await device.setVolume(100)
        XCTAssertEqual(mockTransport.setVolumeCalls, [0, 100])
    }

    func testSetVolumePropagatesError() async {
        mockTransport.setVolumeError = SpeakerConnectError.invalidResponseStructure
        do {
            try await device.setVolume(50)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is SpeakerConnectError)
        }
    }

    // MARK: - setMute

    func testSetMuteDelegatesToTransport() async throws {
        try await device.setMute(true)
        XCTAssertEqual(mockTransport.setMuteCalls.count, 1)
        XCTAssertEqual(mockTransport.setMuteCalls[0], true)
    }

    func testSetMuteWithBothValues() async throws {
        try await device.setMute(true)
        try await device.setMute(false)
        XCTAssertEqual(mockTransport.setMuteCalls, [true, false])
    }

    func testSetMutePropagatesError() async {
        mockTransport.setMuteError = SpeakerConnectError.connectionUnavailable(.connectionLost)
        do {
            try await device.setMute(true)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is SpeakerConnectError)
        }
    }

    // MARK: - State Reconfiguration

    func testConfigureGetStateUpdatesStateClosure() {
        let newState = SpeakerState(volume: 99)
        let newHolder = TestStateHolder(state: newState)
        device.configureGetState(newHolder.getState)
        XCTAssertEqual(device.volume, 99)
    }
}

// MARK: - Mock Transport

final class MockSpeakerTransport: SpeakerTransport, @unchecked Sendable {
    var playCalls = 0
    var pauseCalls = 0
    var playNextCalls = 0
    var playPreviousCalls = 0
    var seekToCalls: [Int] = []
    var setVolumeCalls: [Int] = []
    var setMuteCalls: [Bool] = []
    var setSourceCalls: [PhysicalSource] = []

    var playError: Error?
    var pauseError: Error?
    var playNextError: Error?
    var playPreviousError: Error?
    var seekToError: Error?
    var setVolumeError: Error?
    var setMuteError: Error?
    var setSourceError: Error?

    func play() async throws {
        if let error = playError { throw error }
        playCalls += 1
    }

    func pause() async throws {
        if let error = pauseError { throw error }
        pauseCalls += 1
    }

    func playNext() async throws {
        if let error = playNextError { throw error }
        playNextCalls += 1
    }

    func playPrevious() async throws {
        if let error = playPreviousError { throw error }
        playPreviousCalls += 1
    }

    func seekTo(playTimeMs: Int) async throws {
        if let error = seekToError { throw error }
        seekToCalls.append(playTimeMs)
    }

    func setVolume(_ volume: Int) async throws {
        if let error = setVolumeError { throw error }
        setVolumeCalls.append(volume)
    }

    func setMute(_ muted: Bool) async throws {
        if let error = setMuteError { throw error }
        setMuteCalls.append(muted)
    }

    func setSource(_ source: PhysicalSource) async throws {
        if let error = setSourceError { throw error }
        setSourceCalls.append(source)
    }
}
