// keflar - KEF Speaker Control Library (named after Kevlar)
//
// Architecture:
//   Three-layer design with domain-driven bounded contexts:
//   - Presentation: Keflar (entry point), Speaker (public API with @Observable state)
//   - Domain: SpeakerDevice (hardware), PlaybackSession (playback), StreamingServices (browse/favorites)
//   - Infrastructure: StateSynchronizer (event-driven state), CircuitBreaker, RetryPolicy
//
// Public API:
//   - Keflar: Entry point — probe(host:), connect(to:config:) for connecting to a KEF speaker
//   - Speaker: Main API for controlling the speaker
//   - SpeakerState: Shadow state (observe for updates)
//   - Speaker.connectionState: Connection health (connected / reconnecting / disconnected) for grace period and UI
//   - ConnectionState, ConnectionPolicy: Connection observation and optional grace-period configuration
//   - SpeakerConnectError, TransportFailureReason: Typed errors including connectionUnavailable(timeout, notConnectedToInternet, etc.)
//   - CurrentSong, AudioCodecInfo: Playback information
//   - PlayQueueResult: Play queue fetch
//   - PhysicalSource, RepeatMode: Enums for speaker control
//   - AudioService: Streaming service descriptor (e.g., .tidal) for multi-service support
//
// Bounded Contexts:
//   - SpeakerDevice: Physical device management (power, source, volume, mute)
//   - PlaybackSession: Playback and queue control (play, pause, seek, shuffle, repeat)
//   - StreamingServices: Service-agnostic browse/favorites (Tidal, future Spotify)
//
// All public types are automatically available when importing the keflar module.

import Foundation
