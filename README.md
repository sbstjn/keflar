# keflar

[![CI](https://github.com/sbstjn/keflar/actions/workflows/ci.yml/badge.svg)](https://github.com/sbstjn/keflar/actions/workflows/ci.yml)
[![Swift 6.2+](https://img.shields.io/badge/Swift-6.2+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%20%7C%20iOS%20%7C%20tvOS%20%7C%20visionOS-blue.svg)](https://github.com/sbstjn/keflar)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Opinionated Swift library for controlling [KEF](https://www.kef.com) speakers on your local network. Create a reactive SwiftUI shadow of your speaker via `Speaker` (`@Observable` with live state updates).

### Public API

- **SpeakerConnection** — Entry point: `probe()` fetches basic speaker info (host, model, version, name) for discovery or overviews; `connect()` establishes full connectivity with live state updates via the event stream.
- **Speaker** — Main API: transport (play, pause, seek, volume, mute), source, shuffle/repeat, Tidal playlists, play context (like/favorite), play queue.
- **SpeakerState** — Shadow state (observe for updates); includes volume, mute, playerState, playTime, currentSong metadata, shuffle, repeatMode.
- **ConnectionEvent**, **connectionEvents** — Connection health stream: `for await event in speaker.connectionEvents` (reconnecting, recovered, disconnected).
- **CurrentSong**, **AudioCodecInfo** — Playback info from shadow state (no extra requests).
- **PlayContextActions**, **PlayQueueResult** — Like/favorite actions and queue fetch results.
- **PhysicalSource**, **RepeatMode** — Enums for source and repeat control.
- **SpeakerConnectError** — Errors from connection or API (invalidURL, invalidResponseStructure, invalidJSON, invalidSource).
- **SpeakerProbe** — Result of `probe()` (host, model, version, name).
- **AudioService** — Streaming service descriptor (e.g. `.tidal`); used with `playPlaylist(service:playlistId:)` and `hasServiceConfiguration(_:)`.
- **RequestCounts** — Optional request counts when connecting with `countRequests: true`.

## Requirements

- Swift 6.2+
- iOS 26+ / iPadOS 26+
- macOS 26+
- tvOS 26+
- visionOS 26+

## Installation

### Swift Package Manager

Add keflar to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/sbstjn/keflar.git", from: "0.0.1")
]
```

Or in Xcode: File → Add Package Dependencies, then enter the repository URL.

## Usage

### Basic Connection

```swift
import keflar

let connection = SpeakerConnection(host: "192.168.1.100")

// Optional: probe fetches basic info only (host, model, version, name) — e.g. for discovery or overviews
let probe = try await connection.probe()

// connect establishes full connectivity with live state updates
let speaker = try await connection.connect()
// connect(awaitInitialState: true, countRequests: false) — set countRequests: true to read request counts via getRequestCounts()

// Shadow state and playback
let state = speaker.state
let queue = try await speaker.fetchPlayQueue(from: 0, to: 50)
```

### SwiftUI Integration

`Speaker` is `@Observable`; SwiftUI views that hold a `Speaker` instance automatically update when its state changes.

```swift
import SwiftUI
import keflar

@MainActor
class SpeakerViewModel {
    var speaker: Speaker?
    var isConnecting = false
    var error: Error?
    
    func connect(host: String) async {
        isConnecting = true
        defer { isConnecting = false }
        
        do {
            speaker = try await SpeakerConnection(host: host).connect()
        } catch {
            self.error = error
        }
    }
}

struct PlayerView: View {
    @State private var viewModel = SpeakerViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            if let speaker = viewModel.speaker {
                // State automatically updates when speaker state changes
                Text(speaker.state.deviceName ?? "Unknown Speaker")
                    .font(.headline)
                
                VStack {
                    Text("Volume: \(speaker.state.volume ?? 0)")
                    Text(speaker.state.mute == true ? "Muted" : "Active")
                }
                
                if let song = speaker.currentSong {
                    VStack {
                        Text(song.title ?? "Unknown Track")
                            .font(.title2)
                        Text(song.artist ?? "Unknown Artist")
                            .foregroundStyle(.secondary)
                    }
                }
                
                HStack {
                    Button("Previous") {
                        Task { try? await speaker.playPrevious() }
                    }
                    
                    Button(speaker.isPlaying() ? "Pause" : "Play") {
                        Task {
                            if speaker.isPlaying() {
                                try? await speaker.pause()
                            } else {
                                try? await speaker.play()
                            }
                        }
                    }
                    
                    Button("Next") {
                        Task { try? await speaker.playNext() }
                    }
                }
                .buttonStyle(.bordered)
            } else if viewModel.isConnecting {
                ProgressView("Connecting...")
            } else {
                Button("Connect") {
                    Task {
                        await viewModel.connect(host: "192.168.1.100")
                    }
                }
            }
        }
        .padding()
    }
}
```

The library subscribes to the device event queue and long-polls automatically; events are merged into `state` internally. Observe `speaker.state` for updates. For connection health (reconnecting, disconnected), use `for await event in speaker.connectionEvents`.

## License

MIT. See [LICENSE](LICENSE).

### Acknowledgements

The [pykefcontrol](https://github.com/N0ciple/pykefcontrol) project was of great help; as well as [SwiftKEF](https://github.com/melonamin/SwiftKEF).

Local KEF traffic investigation was done with [Proxyman](https://proxyman.com/).