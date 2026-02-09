//
//  PropertyTests.swift
//  keflarTests
//

import Foundation
import Testing
@testable import keflar

struct PropertyTests {

    @Test(arguments: (0...100).map { $0 })
    func setVolumeRequestRoundTrips(volume: Int) throws {
        let request = SetVolumeRequest(volume: volume)
        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(SetVolumeRequest.self, from: encoded)
        #expect(decoded.i32_ == min(max(volume, 0), 100))
    }

    @Test(arguments: [-10, 0, 1, 50, 99, 100, 101, 200])
    func setVolumeRequestClampsToZeroToOneHundred(volume: Int) throws {
        let request = SetVolumeRequest(volume: volume)
        #expect(request.i32_ >= 0)
        #expect(request.i32_ <= 100)
        #expect(request.i32_ == min(max(volume, 0), 100))
    }

    @Test(arguments: PhysicalSource.allCases)
    func setPhysicalSourceRequestRoundTrips(source: PhysicalSource) throws {
        let request = SetPhysicalSourceRequest(source: source.rawValue)
        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(SetPhysicalSourceRequest.self, from: encoded)
        #expect(decoded.kefPhysicalSource == source.rawValue)
    }

    @Test(arguments: [true, false])
    func setMuteRequestRoundTrips(muted: Bool) throws {
        let request = SetMuteRequest(muted: muted)
        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(SetMuteRequest.self, from: encoded)
        #expect(decoded.bool_ == muted)
    }
}
