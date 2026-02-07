import Foundation
import os

extension Logger {
    private static let subsystem = "com.sbstjn.keflar"

    /// Speaker lifecycle and state.
    static let keflar = Logger(subsystem: subsystem, category: "speaker")

    /// HTTP and transport.
    static let network = Logger(subsystem: subsystem, category: "network")
}

/// Minimal request context for structured logging: correlation ID and optional path. Use for request/response logging and duration metrics.
struct RequestLogContext: Sendable {
    let correlationId: String
    let path: String?

    init(path: String? = nil) {
        self.correlationId = UUID().uuidString
        self.path = path
    }

    func logMessage(suffix: String) -> String {
        var parts = ["correlationId=\(correlationId)"]
        if let path { parts.append("path=\(path)") }
        parts.append(suffix)
        return parts.joined(separator: " ")
    }
}
