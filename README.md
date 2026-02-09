# keflar

[![CI](https://github.com/sbstjn/keflar/actions/workflows/ci.yml/badge.svg)](https://github.com/sbstjn/keflar/actions/workflows/ci.yml)
[![Swift 6.2+](https://img.shields.io/badge/Swift-6.2+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%20%7C%20iOS%20%7C%20tvOS%20%7C%20visionOS-blue.svg)](https://github.com/sbstjn/keflar)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Swift library for controlling [KEF](https://www.kef.com) speakers on the local network. Talks to the device over HTTP (Speaker API) and uses Airable for streaming (Tidal); exposes an `@Observable` `Speaker` with live state from the event stream.

**Protocol and internals:** [SPECS.md](SPECS.md) — Speaker API (getData, setData, getRows, [event stream](SPECS.md#15-event-stream-modifyqueue--pollqueue)), [session bootstrap](SPECS.md#11-base-and-transport), and [service integration (Airable)](SPECS.md#2-service-integration-apis-airable) (proxy resolution, browse, favorites, play playlist).

## Library and functionality

| Area | What the library does |
|------|------------------------|
| **Connection** | `Keflar.probe(host:)` — reachability and basic info (model, version, name). `Keflar.connect(to:config:)` — full session: [modifyQueue](SPECS.md#15-event-stream-modifyqueue--pollqueue) subscribe, [initial getData](SPECS.md#11-base-and-transport) for shadow state, then long-poll event stream. |
| **State** | `Speaker.state` — volume, mute, deviceName, playerState, playTime, currentSong, shuffle, repeatMode. Updated from [pollQueue](SPECS.md#15-event-stream-modifyqueue--pollqueue) events; same path→field mapping as getData. |
| **Playback** | play, pause, next, previous, seek; setVolume, setMute; setSource (physical input); setShuffle, setRepeat. All via [setData](SPECS.md#13-setdata) on `player:player/control` or settings paths. |
| **Play queue** | `fetchPlayQueue(from:to:)` — [getRows](SPECS.md#14-getrows) on `playlists:pq/getitems`. |
| **Streaming (Tidal)** | [Proxy resolution](SPECS.md#22-proxy-resolution), then browse (playlists, tracks, mixes, playlist tracks), favorites (add/remove/isFavorited), `playPlaylist(service:playlistId:)` ([pl/clear → pl/addexternalitems → player/control](SPECS.md#25-play-playlist-queue-replace--play)). |
| **Connection health** | `speaker.connectionEvents` — `.reconnecting`, `.recovered`, `.disconnected` after a [grace period](SPECS.md#15-event-stream-modifyqueue--pollqueue) of poll failures. |

## Requirements

- Swift 6.2+
- iOS 26+ / iPadOS 26+ / macOS 26+ / tvOS 26+ / visionOS 26+

## Installation

**Swift Package Manager** — Add to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/sbstjn/keflar.git", from: "0.0.1")
]
```

Or in Xcode: File → Add Package Dependencies → repository URL.

## Usage

### Probe (optional)

Basic device info only; no event subscription. Uses [getData](SPECS.md#12-getdata) for `settings:/releasetext` and `settings:/deviceName`.

```swift
import keflar

let probe = try await Keflar.probe(host: "192.168.1.100")
// probe.host, probe.model, probe.version, probe.name
```

### Connect

Full session: [modifyQueue](SPECS.md#15-event-stream-modifyqueue--pollqueue) subscribe, [initial state fetch](SPECS.md#11-base-and-transport), then event poll loop. Returns an `@Observable` `Speaker`.

```swift
let speaker = try await Keflar.connect(to: "192.168.1.100")

// Optional: custom config
var config = ConnectionConfig.default
config.awaitInitialState = true
config.timeout = 10
config.services = [.tidal]
let speaker = try await Keflar.connect(to: host, config: config)
```

### SwiftUI: observable state and controls

`Speaker` is `@Observable`. Views that hold a `Speaker` re-render when `state` or `currentSong` change (events are merged into state as in [SPECS §1.5](SPECS.md#15-event-stream-modifyqueue--pollqueue)).

```swift
import SwiftUI
import keflar

struct PlayerView: View {
    @State private var speaker: Speaker?
    @State private var host = "192.168.1.100"
    @State private var isConnecting = false
    @State private var error: Error?

    var body: some View {
        VStack(spacing: 16) {
            if let speaker {
                // — State (from event stream)
                Text(speaker.state.deviceName ?? "Speaker").font(.headline)
                HStack {
                    Text("Volume: \(speaker.state.volume ?? 0)")
                    if speaker.state.mute == true { Text("Muted") }
                }
                if let song = speaker.currentSong {
                    Text(song.title ?? "").font(.title2)
                    Text(song.artist ?? "").foregroundStyle(.secondary)
                    if let id = song.trackId {
                        Text("Track ID: \(id)").font(.caption)
                    }
                }

                // — Transport
                HStack(spacing: 12) {
                    Button("Previous") { Task { try? await speaker.playPrevious() } }
                    Button(speaker.isPlaying() ? "Pause" : "Play") {
                        Task {
                            if speaker.isPlaying() { try? await speaker.pause() }
                            else { try? await speaker.play() }
                        }
                    }
                    Button("Next") { Task { try? await speaker.playNext() } }
                }
                .buttonStyle(.bordered)

                // — Volume and mute
                if let v = speaker.state.volume {
                    Text("Volume: \(v)")
                    Button(speaker.state.mute == true ? "Unmute" : "Mute") {
                        Task { try? await speaker.setMute(speaker.state.mute != true) }
                    }
                }
            } else if isConnecting {
                ProgressView("Connecting…")
            } else {
                TextField("Speaker IP", text: $host).textFieldStyle(.roundedBorder)
                Button("Connect") { connect() }
                if let error { Text(error.localizedDescription).foregroundStyle(.red) }
            }
        }
        .padding()
    }

    private func connect() {
        isConnecting = true
        error = nil
        Task {
            defer { isConnecting = false }
            do {
                speaker = try await Keflar.connect(to: host)
            } catch {
                self.error = error
            }
        }
    }
}
```

### Connection health (SwiftUI or async)

Use `connectionEvents` to show “Reconnecting…” or navigate away when disconnected. See [SPECS §1.5](SPECS.md#15-event-stream-modifyqueue--pollqueue) (queue lifecycle, grace period).

```swift
Task {
    for await event in speaker.connectionEvents {
        switch event {
        case .reconnecting:  // show "Reconnecting…"
        case .recovered:     // clear message
        case .disconnected:  // e.g. pop to device picker
        }
    }
}
```

## Logging

keflar uses Apple’s [Unified Logging](https://developer.apple.com/documentation/os/logging) (OSLog). Logs are **not** stripped in release builds; use Console.app or `log stream` to inspect by subsystem and category.

- **Subsystem:** `com.sbstjn.keflar`
- **Categories:** `speaker` (probe, connect, lifecycle), `network` (HTTP getData/setData/getRows/modifyQueue/pollQueue), `eventPoll` (queue created, reconnecting, recovered, disconnected), `resilience` (circuit breaker, retry), `streaming` (proxy resolution, browse, play playlist), `state` (optional state apply)
- **Levels:** **debug** — per-request, timings, retries; **info** — lifecycle (probe success, connected, queue created, reconnecting, recovered, disconnected); **error** — transport or resolution failures (in addition to throwing)
- **Privacy:** Host, path, URL, and payload content are logged with `.private` so they are redacted on device when the debugger is not attached; correlation IDs and non-sensitive enums are `.public`

## License

MIT. See [LICENSE](LICENSE).

**Acknowledgements:** [pykefcontrol](https://github.com/N0ciple/pykefcontrol), [SwiftKEF](https://github.com/melonamin/SwiftKEF). Local traffic inspection with [Proxyman](https://proxyman.com/).
