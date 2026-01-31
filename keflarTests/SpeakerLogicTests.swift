//
//  SpeakerLogicTests.swift
//  keflarTests
//

import Foundation
import Testing
@testable import keflar

struct SpeakerLogicTests {

    // MARK: - StateReducer.applyToState

    @Test func stateReducerApplyVolume() {
        var state = SpeakerState()
        StateReducer.applyToState(path: "player:volume", dict: ["i32_": 42], state: &state)
        #expect(state.volume == 42)
    }

    @Test func stateReducerApplyPhysicalSource() {
        var state = SpeakerState()
        StateReducer.applyToState(path: "settings:/kef/play/physicalSource", dict: ["kefPhysicalSource": "wifi"], state: &state)
        #expect(state.source == "wifi")
    }

    @Test func stateReducerApplyPlayerDataPath() {
        var state = SpeakerState()
        let dict: [String: Any] = [
            "state": "playing",
            "status": ["duration": 158226] as [String: Any],
            "trackRoles": ["path": "airable:https://x.airable.io/id/tidal/track/1", "value": ["i32_": 8] as [String: Any]] as [String: Any],
        ]
        StateReducer.applyToState(path: "player:player/data", dict: dict, state: &state)
        #expect(state.playerState == "playing")
        #expect(state.duration == 158226)
        #expect(state.currentQueueIndex == 8)
        #expect(state.other["player:player/data"] as? [String: Any] != nil)
    }

    @Test func stateReducerApplyUnknownPathToOther() {
        var state = SpeakerState()
        StateReducer.applyToState(path: "custom:path", dict: ["key": "value"], state: &state)
        #expect((state.other["custom:path"] as? [String: Any])?["key"] as? String == "value")
    }

    @Test func stateReducerApplyPlayModeShuffle() {
        var state = SpeakerState()
        StateReducer.applyToState(path: "settings:/mediaPlayer/playMode", dict: ["type": "playerPlayMode", "playerPlayMode": "shuffle"], state: &state)
        #expect(state.shuffle == true)
        #expect(state.repeatMode == .off)
    }

    @Test func stateReducerApplyPlayModeRepeatOne() {
        var state = SpeakerState()
        StateReducer.applyToState(path: "settings:/mediaPlayer/playMode", dict: ["type": "playerPlayMode", "playerPlayMode": "repeatOne"], state: &state)
        #expect(state.shuffle == false)
        #expect(state.repeatMode == .one)
    }

    @Test func stateReducerApplyPlayModeNormal() {
        var state = SpeakerState()
        StateReducer.applyToState(path: "settings:/mediaPlayer/playMode", dict: ["type": "playerPlayMode", "playerPlayMode": "normal"], state: &state)
        #expect(state.shuffle == false)
        #expect(state.repeatMode == .off)
    }

    // MARK: - StateReducer.parseEvents

    @Test func stateReducerParseEventsVolume() {
        let pathToItemValue: [String: Any] = ["player:volume": ["i32_": 50]]
        let events = StateReducer.parseEvents(pathToItemValue: pathToItemValue)
        #expect(events.volume == 50)
    }

    @Test func stateReducerParseEventsMultipleAndUnknown() {
        let pathToItemValue: [String: Any] = [
            "player:volume": ["i32_": 30],
            "settings:/deviceName": ["string_": "KEF"],
            "unknown:path": ["foo": 1],
        ]
        let events = StateReducer.parseEvents(pathToItemValue: pathToItemValue)
        #expect(events.volume == 30)
        #expect(events.deviceName == "KEF")
        #expect((events.other["unknown:path"] as? [String: Any])?["foo"] as? Int == 1)
    }

    @Test func stateReducerParseEventsPlayMode() {
        let pathToItemValue: [String: Any] = [
            "settings:/mediaPlayer/playMode": ["type": "playerPlayMode", "playerPlayMode": "repeatOne"] as [String: Any],
        ]
        let events = StateReducer.parseEvents(pathToItemValue: pathToItemValue)
        #expect(events.shuffle == false)
        #expect(events.repeatMode == .one)
    }

    @Test func stateReducerParseEventsPlayerDataPathDurationAndQueueIndex() {
        let pathToItemValue: [String: Any] = [
            "player:player/data": [
                "state": "playing",
                "status": ["duration": 200000] as [String: Any],
                "trackRoles": ["value": ["i32_": 3] as [String: Any]] as [String: Any],
            ] as [String: Any],
        ]
        let events = StateReducer.parseEvents(pathToItemValue: pathToItemValue)
        #expect(events.playerState == "playing")
        #expect(events.duration == 200000)
        #expect(events.currentQueueIndex == 3)
    }

    // MARK: - merge

    @Test func mergeUpdatesState() {
        var state = SpeakerState()
        state.volume = 10
        let batch = SpeakerEvents(source: "wifi", volume: 80)
        mergeEvents(batch, into: &state)
        #expect(state.volume == 80)
        #expect(state.source == "wifi")
    }

    @Test func mergeLeavesUnsetFieldsUnchanged() {
        var state = SpeakerState(volume: 25, deviceName: "Speaker")
        let batch = SpeakerEvents(volume: 50)
        mergeEvents(batch, into: &state)
        #expect(state.volume == 50)
        #expect(state.deviceName == "Speaker")
    }

    @Test func mergeUpdatesShuffleAndRepeatMode() {
        var state = SpeakerState()
        let batch = SpeakerEvents(shuffle: true, repeatMode: .all)
        mergeEvents(batch, into: &state)
        #expect(state.shuffle == true)
        #expect(state.repeatMode == .all)
    }

    @Test func mergeUpdatesDurationAndCurrentQueueIndex() {
        var state = SpeakerState()
        let batch = SpeakerEvents(duration: 180000, currentQueueIndex: 5)
        mergeEvents(batch, into: &state)
        #expect(state.duration == 180000)
        #expect(state.currentQueueIndex == 5)
    }

    // MARK: - parsePlayMode

    @Test func parsePlayModeShuffle() {
        let (shuffle, repeatMode) = parsePlayMode(from: ["type": "playerPlayMode", "playerPlayMode": "shuffle"])
        #expect(shuffle == true)
        #expect(repeatMode == .off)
    }

    @Test func parsePlayModeRepeatAll() {
        let (shuffle, repeatMode) = parsePlayMode(from: ["playerPlayMode": "repeatAll"])
        #expect(shuffle == false)
        #expect(repeatMode == .all)
    }

    @Test func parsePlayModeNormalOrDefault() {
        let (s1, r1) = parsePlayMode(from: ["playerPlayMode": "normal"])
        #expect(s1 == false)
        #expect(r1 == .off)
        let (s2, r2) = parsePlayMode(from: [:])
        #expect(s2 == false)
        #expect(r2 == .off)
    }

    // MARK: - parseDuration

    @Test func parseDurationValid() {
        let playerData: [String: Any] = ["status": ["duration": 158226] as [String: Any]]
        #expect(parseDuration(from: playerData) == 158226)
    }

    @Test func parseDurationMissingStatus() {
        #expect(parseDuration(from: [:]) == nil)
        #expect(parseDuration(from: ["state": "playing"]) == nil)
    }

    @Test func parseDurationMissingDuration() {
        let playerData: [String: Any] = ["status": ["other": 1] as [String: Any]]
        #expect(parseDuration(from: playerData) == nil)
    }

    // MARK: - parseQueueIndex

    @Test func parseQueueIndexValid() {
        let playerData: [String: Any] = ["trackRoles": ["value": ["i32_": 8] as [String: Any]] as [String: Any]]
        #expect(parseQueueIndex(from: playerData) == 8)
    }

    @Test func parseQueueIndexMissingValue() {
        #expect(parseQueueIndex(from: [:]) == nil)
        #expect(parseQueueIndex(from: ["trackRoles": ["path": "x"] as [String: Any]]) == nil)
    }

    @Test func parseQueueIndexMissingTrackRoles() {
        #expect(parseQueueIndex(from: ["state": "playing"]) == nil)
    }

    // MARK: - parseCurrentSong

    @Test func parseCurrentSongFull() {
        let playerData: [String: Any] = [
            "status": ["duration": 240000] as [String: Any],
            "trackRoles": [
                "title": "Song Title",
                "icon": "https://cover.url",
                "mediaData": [
                    "metaData": [
                        "artist": "Artist",
                        "album": "Album",
                        "albumArtist": "Album Artist",
                        "serviceID": "tidal",
                    ] as [String: Any],
                ] as [String: Any],
            ] as [String: Any],
        ]
        let song = parseCurrentSong(from: playerData)
        #expect(song.title == "Song Title")
        #expect(song.artist == "Artist")
        #expect(song.album == "Album")
        #expect(song.albumArtist == "Album Artist")
        #expect(song.coverURL == "https://cover.url")
        #expect(song.serviceID == "tidal")
        #expect(song.duration == 240000)
    }

    @Test func parseCurrentSongEmptyDict() {
        let song = parseCurrentSong(from: [:])
        #expect(song.title == nil)
        #expect(song.artist == nil)
    }

    // MARK: - parseAudioCodecInfo

    @Test func parseAudioCodecInfoFull() {
        let playerData: [String: Any] = [
            "trackRoles": [
                "mediaData": [
                    "activeResource": [
                        "codec": "flac",
                        "sampleFrequency": 44100,
                        "streamSampleRate": 96000,
                        "streamChannels": "stereo",
                        "nrAudioChannels": 2,
                    ] as [String: Any],
                    "metaData": ["serviceID": "tidal"] as [String: Any],
                ] as [String: Any],
            ] as [String: Any],
        ]
        let info = parseAudioCodecInfo(from: playerData)
        #expect(info.codec == "flac")
        #expect(info.sampleFrequency == 44100)
        #expect(info.streamSampleRate == 96000)
        #expect(info.streamChannels == "stereo")
        #expect(info.nrAudioChannels == 2)
        #expect(info.serviceID == "tidal")
    }

    @Test func parseAudioCodecInfoEmpty() {
        let info = parseAudioCodecInfo(from: [:])
        #expect(info.codec == nil)
        #expect(info.serviceID == nil)
    }

    // MARK: - proxyBaseFromTrackRolesPath

    @Test func proxyBaseFromTrackRolesPathValid() {
        #expect(proxyBaseFromTrackRolesPath("airable:https://example.airable.io/id/tidal/track/1") == "https://example.airable.io")
    }

    @Test func proxyBaseFromTrackRolesPathNil() {
        #expect(proxyBaseFromTrackRolesPath(nil) == nil)
    }

    @Test func proxyBaseFromTrackRolesPathNoAirablePrefix() {
        #expect(proxyBaseFromTrackRolesPath("https://example.com/id/foo") == nil)
    }

    @Test func proxyBaseFromTrackRolesPathNoIdSegment() {
        #expect(proxyBaseFromTrackRolesPath("airable:https://x.airable.io/") == nil)
    }

    // MARK: - proxyBaseFromLinkServiceRedirect

    @Test func proxyBaseFromLinkServiceRedirectValid() {
        #expect(proxyBaseFromLinkServiceRedirect("airable:https://example.airable.io/tidal") == "https://example.airable.io")
    }

    @Test func proxyBaseFromLinkServiceRedirectNil() {
        #expect(proxyBaseFromLinkServiceRedirect(nil) == nil)
    }

    @Test func proxyBaseFromLinkServiceRedirectBarePath() {
        #expect(proxyBaseFromLinkServiceRedirect("airable:linkService_tidal") == nil)
    }

    // MARK: - proxyBaseFromQueueRow

    @Test func proxyBaseFromQueueRowContentPlayContextPath() {
        let row: [String: Any] = [
            "value": [
                "mediaData": [
                    "metaData": ["contentPlayContextPath": "airable:playContext:airable:https://proxy.airable.io/id/tidal/playlist/1"] as [String: Any],
                ] as [String: Any],
            ] as [String: Any],
        ]
        #expect(proxyBaseFromQueueRow(row) == "https://proxy.airable.io")
    }

    @Test func proxyBaseFromQueueRowResourcesUri() {
        let row: [String: Any] = [
            "itemValue": [
                "mediaData": [
                    "resources": [["uri": "https://proxy.airable.io/stream"]] as [[String: Any]],
                ] as [String: Any],
            ] as [String: Any],
        ]
        #expect(proxyBaseFromQueueRow(row) == "https://proxy.airable.io")
    }

    @Test func proxyBaseFromQueueRowEmpty() {
        #expect(proxyBaseFromQueueRow([:]) == nil)
    }

    // MARK: - resolveTrackFromRow

    @Test func resolveTrackFromRowItemValueTidalTrack() {
        let row: [String: Any] = [
            "path": "playlists:pq/getitems",
            "itemValue": ["path": "airable:https://x.airable.io/id/tidal/track/123", "title": "Track"] as [String: Any],
        ]
        let track = resolveTrackFromRow(row)
        #expect(track != nil)
        #expect(track?["title"] as? String == "Track")
    }

    @Test func resolveTrackFromRowValueTidalTrack() {
        let row: [String: Any] = [
            "value": ["path": "id/tidal/track/456"] as [String: Any],
        ]
        let track = resolveTrackFromRow(row)
        #expect(track != nil)
    }

    @Test func resolveTrackFromRowNonTrackPathReturnsNil() {
        let row: [String: Any] = [
            "itemValue": ["path": "other:service/album/1"] as [String: Any],
        ]
        #expect(resolveTrackFromRow(row) == nil)
    }

    // MARK: - AudioService

    @Test func audioServiceTidalMetadata() {
        #expect(AudioService.tidal.id == "tidal")
        #expect(AudioService.tidal.linkServicePath == "linkService_tidal")
        #expect(AudioService.tidal.playlistPathComponent == "tidal/playlist")
        #expect(AudioService.tidal.trackPathComponent == "tidal/track")
    }

    // MARK: - resolveFirstTrack

    @Test func resolveFirstTrackReturnsFirstTidalTrack() {
        let rows: [[String: Any]] = [
            ["itemValue": ["path": "other:path"] as [String: Any]],
            ["itemValue": ["path": "airable:https://x.airable.io/id/tidal/track/1", "title": "First"] as [String: Any]],
        ]
        let track = resolveFirstTrack(from: rows)
        #expect(track?["title"] as? String == "First")
    }

    @Test func resolveFirstTrackNoTidalReturnsFirstRow() {
        let rows: [[String: Any]] = [
            ["path": "row1", "value": ["key": "a"] as [String: Any]],
        ]
        let track = resolveFirstTrack(from: rows)
        #expect(track != nil)
        #expect(track?["path"] as? String == "row1")
        #expect((track?["value"] as? [String: Any])?["key"] as? String == "a")
    }

    // MARK: - Play context parsing

    @Test func extractPlayContextPathPresent() {
        let playerData: [String: Any] = [
            "trackRoles": [
                "mediaData": [
                    "metaData": ["contentPlayContextPath": "airable:playContext:https://p.airable.io/id/tidal/track/123"] as [String: Any],
                ] as [String: Any],
            ] as [String: Any],
        ]
        #expect(extractPlayContextPath(from: playerData) == "airable:playContext:https://p.airable.io/id/tidal/track/123")
    }

    @Test func extractPlayContextPathMissing() {
        #expect(extractPlayContextPath(from: [:]) == nil)
        let noMeta: [String: Any] = ["trackRoles": ["mediaData": [:]] as [String: Any]]
        #expect(extractPlayContextPath(from: noMeta) == nil)
    }

    @Test func parsePlayContextActionsFavoriteInsertNotLiked() {
        let response: [String: Any] = [
            "rows": [
                [
                    "type": "action",
                    "path": "airable:action:https://p.airable.io/actions/tidal/track/1/favorites/insert",
                    "title": "Add to TIDAL favorites",
                    "id": "airable://tidal/action/favorite.insert",
                ] as [String: Any],
                [
                    "type": "container",
                    "path": "airable:action:https://p.airable.io/actions/tidal/track/1/playlist/choose/insert",
                    "title": "Add to playlist",
                    "id": "airable://tidal/action/playlist.insert",
                ] as [String: Any],
            ] as [[String: Any]],
        ]
        let actions = parsePlayContextActions(from: response)
        #expect(actions != nil)
        #expect(actions!.items.count == 2)
        #expect(actions!.isLiked == false)
        #expect(actions!.favoriteInsertPath == "airable:action:https://p.airable.io/actions/tidal/track/1/favorites/insert")
        #expect(actions!.favoriteRemovePath == nil)
    }

    @Test func parsePlayContextActionsFavoriteRemoveLiked() {
        let response: [String: Any] = [
            "rows": [
                [
                    "type": "action",
                    "path": "airable:action:https://p.airable.io/actions/tidal/track/2/favorites/remove",
                    "title": "Remove from TIDAL favorites",
                    "id": "airable://tidal/action/favorite.remove",
                ] as [String: Any],
            ] as [[String: Any]],
        ]
        let actions = parsePlayContextActions(from: response)
        #expect(actions != nil)
        #expect(actions!.isLiked == true)
        #expect(actions!.favoriteInsertPath == nil)
        #expect(actions!.favoriteRemovePath == "airable:action:https://p.airable.io/actions/tidal/track/2/favorites/remove")
    }

    @Test func parsePlayContextActionsEmptyRows() {
        let response: [String: Any] = ["rows": [] as [[String: Any]]]
        let actions = parsePlayContextActions(from: response)
        #expect(actions != nil)
        #expect(actions!.items.isEmpty)
        #expect(actions!.isLiked == false)
        #expect(actions!.favoriteInsertPath == nil)
        #expect(actions!.favoriteRemovePath == nil)
    }

    @Test func parsePlayContextActionsMissingRowsReturnsNil() {
        #expect(parsePlayContextActions(from: [:]) == nil)
        #expect(parsePlayContextActions(from: ["roles": [:]]) == nil)
    }

    @Test func parsePlayContextActionsSkipsRowWithoutPathOrTitle() {
        let response: [String: Any] = [
            "rows": [
                ["type": "action", "id": "some.id"] as [String: Any],
                ["type": "action", "path": "p", "title": "T", "id": "ok"] as [String: Any],
            ] as [[String: Any]],
        ]
        let actions = parsePlayContextActions(from: response)
        #expect(actions != nil)
        #expect(actions!.items.count == 1)
        #expect(actions!.items[0].path == "p")
        #expect(actions!.items[0].title == "T")
    }

    // MARK: - DTOs (SpeakerClient)

    @Test func playerDataDTOInit() {
        let dict: [String: Any] = ["state": "paused", "trackRoles": ["path": "airable:https://p.airable.io/id/track", "title": "T"] as [String: Any]]
        let dto = PlayerDataDTO(dict: dict)
        #expect(dto.state == "paused")
        #expect(dto.path == "airable:https://p.airable.io/id/track")
        #expect(dto.raw["state"] as? String == "paused")
    }

    @Test func modifyQueueResponseFromString() {
        #expect(ModifyQueueResponse(json: "abc")?.queueId == "abc")
        #expect(ModifyQueueResponse(json: "{qid}")?.queueId == "qid")
    }

    @Test func modifyQueueResponseFromArray() {
        #expect(ModifyQueueResponse(json: [0, "queue-id-123"])?.queueId == "queue-id-123")
    }

    @Test func modifyQueueResponseInvalidReturnsNil() {
        #expect(ModifyQueueResponse(json: 42) == nil)
        #expect(ModifyQueueResponse(json: []) == nil)
    }

    // MARK: - Play queue parsing

    @Test func parsePlayQueueFromGetRowsResponse() {
        let response: [String: Any] = [
            "rowsCount": 2,
            "rows": [
                [
                    "id": "1",
                    "path": "playlists:item/1",
                    "title": "Track One",
                    "icon": "https://cover.url/1",
                    "value": ["type": "i32_", "i32_": 0] as [String: Any],
                    "mediaData": [
                        "metaData": [
                            "artist": "Artist A",
                            "album": "Album A",
                            "serviceID": "tidal",
                        ] as [String: Any],
                    ] as [String: Any],
                ] as [String: Any],
                [
                    "id": "2",
                    "title": "Track Two",
                    "value": ["type": "i32_", "i32_": 1] as [String: Any],
                    "mediaData": ["metaData": ["artist": "Artist B"] as [String: Any]] as [String: Any],
                ] as [String: Any],
            ] as [[String: Any]],
        ]
        let result = parsePlayQueue(from: response)
        #expect(result.items.count == 2)
        #expect(result.totalCount == 2)
        #expect(result.items[0].index == 0)
        #expect(result.items[0].id == "1")
        #expect(result.items[0].title == "Track One")
        #expect(result.items[0].artist == "Artist A")
        #expect(result.items[0].album == "Album A")
        #expect(result.items[0].coverURL == "https://cover.url/1")
        #expect(result.items[0].serviceID == "tidal")
        #expect(result.items[1].index == 1)
        #expect(result.items[1].id == "2")
        #expect(result.items[1].title == "Track Two")
        #expect(result.items[1].artist == "Artist B")
    }

    @Test func parsePlayQueueEmptyOrMissingRows() {
        let empty = parsePlayQueue(from: [:])
        #expect(empty.items.isEmpty)
        #expect(empty.totalCount == nil)
        let emptyRows = parsePlayQueue(from: ["rows": [] as [[String: Any]], "rowsCount": 0])
        #expect(emptyRows.items.isEmpty)
        #expect(emptyRows.totalCount == 0)
    }

    @Test func parsePlayQueueSkipsRowWithoutId() {
        let response: [String: Any] = [
            "rows": [
                ["title": "No Id", "value": ["i32_": 0] as [String: Any]] as [String: Any],
                ["id": "1", "title": "With Id", "value": ["i32_": 1] as [String: Any]] as [String: Any],
            ] as [[String: Any]],
        ]
        let result = parsePlayQueue(from: response)
        #expect(result.items.count == 1)
        #expect(result.items[0].id == "1")
    }

    // MARK: - Error types

    @Test func speakerConnectErrorInvalidJSONHasPreview() {
        let err = SpeakerConnectError.invalidJSON(responsePreview: "bad body")
        guard case .invalidJSON(let preview) = err else {
            Issue.record("expected invalidJSON case")
            return
        }
        #expect(preview == "bad body")
    }

    @Test func speakerConnectErrorInvalidSourceHasMessage() {
        let err = SpeakerConnectError.invalidSource("proxy unknown")
        guard case .invalidSource(let msg) = err else {
            Issue.record("expected invalidSource case")
            return
        }
        #expect(msg == "proxy unknown")
    }
}
