import Foundation
import os

/// Token for managing an active auto-reconnection loop. Cancel the loop by calling `cancel()` or by releasing the token.
@MainActor
public final class AutoReconnectToken {
    private var task: Task<Void, Never>?
    
    init(task: Task<Void, Never>) {
        self.task = task
    }
    
    /// Cancel the auto-reconnection loop.
    public func cancel() {
        task?.cancel()
        task = nil
    }
    
    deinit {
        task?.cancel()
    }
}

/// Auto-reconnection coordinator for Speaker instances. Handles retry logic when connection is lost.
public struct AutoReconnect {
    
    /// Start automatic reconnection for the specified host.
    ///
    /// When the speaker's `connectionState` becomes `.reconnecting` or `.disconnected`, this will automatically
    /// attempt to reconnect at regular intervals until successful or cancelled.
    ///
    /// - Parameters:
    ///   - host: The speaker host IP address to reconnect to.
    ///   - interval: Time interval between reconnection attempts (default: 1 second).
    ///   - connectTimeout: Timeout for each connection attempt (default: 4 seconds for full connection setup).
    ///   - connectionPolicy: Connection grace period policy (passed to reconnected speaker).
    ///   - onReconnected: Callback invoked when reconnection succeeds, providing the new Speaker instance.
    ///   - onAttemptFailed: Optional callback invoked after each failed attempt with the error.
    /// - Returns: AutoReconnectToken that manages the reconnection loop. Cancel it to stop reconnecting.
    @MainActor
    public static func start(
        host: String,
        interval: TimeInterval = 1.0,
        connectTimeout: TimeInterval = 4.0,
        connectionPolicy: ConnectionPolicy? = nil,
        onReconnected: @escaping @MainActor (Speaker) -> Void,
        onAttemptFailed: (@MainActor (Error) -> Void)? = nil
    ) -> AutoReconnectToken {
        let task = Task { @MainActor in
            let intervalNs = UInt64(interval * 1_000_000_000)
            Logger.keflar.info("AutoReconnect: started for host=\(host) interval=\(interval)s")
            
            while !Task.isCancelled {
                do {
                    var config = ConnectionConfig.default
                    config.policy = connectionPolicy
                    config.timeout = connectTimeout
                    let speaker = try await Keflar.connect(to: host, config: config)
                    Logger.keflar.info("AutoReconnect: succeeded host=\(host)")
                    onReconnected(speaker)
                    return
                } catch {
                    Logger.keflar.info("AutoReconnect: attempt failed host=\(host) error=\(String(describing: error))")
                    onAttemptFailed?(error)
                }
                
                guard !Task.isCancelled else { break }
                try? await Task.sleep(nanoseconds: intervalNs)
            }
            
            Logger.keflar.info("AutoReconnect: cancelled host=\(host)")
        }
        
        return AutoReconnectToken(task: task)
    }
    
    /// Start automatic reconnection monitoring for an existing speaker.
    ///
    /// Monitors the speaker's `connectionEvents` stream and automatically attempts to reconnect
    /// when `.reconnecting` or `.disconnected` events are received.
    ///
    /// - Parameters:
    ///   - speaker: The speaker to monitor for connection events.
    ///   - host: The speaker host IP address to reconnect to.
    ///   - interval: Time interval between reconnection attempts (default: 1 second).
    ///   - connectTimeout: Timeout for each connection attempt (default: 4 seconds).
    ///   - connectionPolicy: Connection grace period policy (passed to reconnected speaker).
    ///   - onReconnected: Callback invoked when reconnection succeeds, providing the new Speaker instance.
    ///   - onAttemptFailed: Optional callback invoked after each failed attempt with the error.
    /// - Returns: AutoReconnectToken that manages the monitoring and reconnection. Cancel it to stop.
    @MainActor
    public static func monitor(
        speaker: Speaker,
        host: String,
        interval: TimeInterval = 1.0,
        connectTimeout: TimeInterval = 4.0,
        connectionPolicy: ConnectionPolicy? = nil,
        onReconnected: @escaping @MainActor (Speaker) -> Void,
        onAttemptFailed: (@MainActor (Error) -> Void)? = nil
    ) -> AutoReconnectToken {
        var reconnectTask: Task<Void, Never>?
        
        let monitorTask = Task { @MainActor in
            for await event in speaker.connectionEvents {
                guard !Task.isCancelled else { break }
                
                switch event {
                case .reconnecting, .disconnected:
                    // Start reconnection loop if not already running
                    if reconnectTask == nil || reconnectTask?.isCancelled == true {
                        reconnectTask = Task { @MainActor in
                            let intervalNs = UInt64(interval * 1_000_000_000)
                            Logger.keflar.info("AutoReconnect.monitor: starting reconnection host=\(host)")
                            
                            while !Task.isCancelled {
                                // Check if connection recovered externally
                                if speaker.connectionState == .connected {
                                    Logger.keflar.info("AutoReconnect.monitor: connection recovered externally")
                                    return
                                }
                                
                                do {
                                    var config = ConnectionConfig.default
                                    config.policy = connectionPolicy
                                    config.timeout = connectTimeout
                                    let newSpeaker = try await Keflar.connect(to: host, config: config)
                                    Logger.keflar.info("AutoReconnect.monitor: reconnection succeeded host=\(host)")
                                    onReconnected(newSpeaker)
                                    return
                                } catch {
                                    Logger.keflar.info("AutoReconnect.monitor: attempt failed host=\(host) error=\(String(describing: error))")
                                    onAttemptFailed?(error)
                                }
                                
                                guard !Task.isCancelled else { break }
                                try? await Task.sleep(nanoseconds: intervalNs)
                            }
                        }
                    }
                    
                case .recovered:
                    // Connection recovered naturally; cancel reconnection loop
                    reconnectTask?.cancel()
                    reconnectTask = nil
                }
            }
        }
        
        let token = AutoReconnectToken(task: monitorTask)
        
        // When token is cancelled, also cancel any active reconnection task
        Task { @MainActor in
            await monitorTask.value
            reconnectTask?.cancel()
        }
        
        return token
    }
}
