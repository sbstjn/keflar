// keflar - KEF Speaker Control Library (named after Kevlar)
//
// Public API:
//   - SpeakerConnection: Entry point for connecting to a KEF speaker
//   - Speaker: Main API for controlling the speaker
//   - SpeakerState: Shadow state (observe for updates)
//   - Speaker.connectionState: Connection health (connected / reconnecting / disconnected) for grace period and UI
//   - ConnectionState, ConnectionPolicy: Connection observation and optional grace-period configuration
//   - SpeakerConnectError, TransportFailureReason: Typed errors including connectionUnavailable(timeout, notConnectedToInternet, etc.)
//   - CurrentSong, AudioCodecInfo: Playback information
//   - Speaker.playContextActions: Like/favorite state for current track (refetched on track change and after setLiked)
//   - PlayContextActions, PlayQueueResult: Collections and actions
//   - PhysicalSource, RepeatMode: Enums for speaker control
//
// All public types are automatically available when importing the keflar module.

import Foundation
