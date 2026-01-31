import Foundation

// MARK: - Airable Proxy Resolution

/// Extract Airable proxy base (e.g. "https://{proxy}.airable.io") from trackRoles.path ("airable:https://.../id/...").
func proxyBaseFromTrackRolesPath(_ path: String?) -> String? {
    guard let path = path, path.hasPrefix("airable:") else { return nil }
    let rest = path.dropFirst("airable:".count)
    guard let idx = rest.range(of: "/id/") else { return nil }
    return String(rest[..<idx.lowerBound])
}

/// Extract Airable proxy base from linkService redirect (e.g. "airable:https://{proxy}.airable.io/tidal" → "https://{proxy}.airable.io").
func proxyBaseFromLinkServiceRedirect(_ redirect: String?) -> String? {
    guard let redirect = redirect, redirect.hasPrefix("airable:https://"), redirect.contains(".airable.io") else { return nil }
    let rest = String(redirect.dropFirst("airable:".count))
    guard let end = rest.range(of: ".airable.io")?.upperBound else { return nil }
    return String(rest[..<end])
}

/// Extract Airable proxy base from a play-queue row (mediaData.resources[0].uri or metaData.contentPlayContextPath).
func proxyBaseFromQueueRow(_ row: [String: Any]) -> String? {
    let candidate: [String: Any]? = (row["value"] as? [String: Any]) ?? (row["itemValue"] as? [String: Any]) ?? row
    guard let track = candidate else { return nil }
    if let metaData = (track["mediaData"] as? [String: Any])?["metaData"] as? [String: Any],
       let p = metaData["contentPlayContextPath"] as? String {
        return proxyBaseFromTrackRolesPath(p.replacingOccurrences(of: "airable:playContext:", with: ""))
    }
    if let resources = (track["mediaData"] as? [String: Any])?["resources"] as? [[String: Any]],
       let uri = resources.first?["uri"] as? String,
       uri.hasPrefix("https://"), uri.contains(".airable.io"),
       let end = uri.range(of: ".airable.io")?.upperBound {
        return String(uri[..<end])
    }
    return nil
}

// MARK: - Track Resolution

/// Get the track dict from a single getRows row (itemValue / value / row itself). Returns nil if row is not an Airable track.
func resolveTrackFromRow(_ row: [String: Any]) -> [String: Any]? {
    let candidate: [String: Any]?
    if let wrapped = row["itemValue"] as? [String: Any] {
        candidate = wrapped
    } else if let wrapped = row["value"] as? [String: Any] {
        candidate = wrapped
    } else {
        candidate = row
    }
    guard let track = candidate else { return nil }
    let path = (track["path"] as? String) ?? (row["path"] as? String) ?? ""
    guard path.contains("/track") || path.hasSuffix("track") else { return nil }
    return track
}

/// From getRows response.rows: find first track object (path contains "tidal/track"). Row may be the track or have itemValue/value.
func resolveFirstTrack(from rows: [[String: Any]]) -> [String: Any]? {
    for row in rows {
        if let track = resolveTrackFromRow(row) { return track }
    }
    return rows.first
}

/// Serialize track dict to JSON string for playlists:pl/addexternalitems nsdkRoles.
internal func nsdkRolesJSONString(from track: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: track)
    guard let s = String(data: data, encoding: .utf8) else { throw SpeakerConnectError.invalidResponseStructure }
    return s
}
