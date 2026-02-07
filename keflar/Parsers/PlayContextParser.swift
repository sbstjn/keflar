import Foundation

// Parsers: parse... transforms a dict into a typed model (e.g. parsePlayContextActions → PlayContextActions). Extractors: extract... returns a single value from a nested structure (e.g. extractPlayContextPath → String?).

/// Extract content play context path for the current track (getRows target for like/favorite actions). Internal for testing.
func extractPlayContextPath(from playerData: [String: Any]) -> String? {
    let trackRoles = playerData["trackRoles"] as? [String: Any] ?? [:]
    let mediaData = trackRoles["mediaData"] as? [String: Any] ?? [:]
    let metaData = mediaData["metaData"] as? [String: Any] ?? [:]
    return metaData["contentPlayContextPath"] as? String
}

/// Extract content play context path from a play-queue row (getRows playlists:pq/getitems). Row may have value/itemValue.mediaData.metaData or row.mediaData.metaData. Internal for testing.
func extractPlayContextPathFromQueueRow(_ row: [String: Any]) -> String? {
    let track = (row["value"] as? [String: Any]) ?? (row["itemValue"] as? [String: Any]) ?? row
    let metaData = (track["mediaData"] as? [String: Any])?["metaData"] as? [String: Any]
        ?? (row["mediaData"] as? [String: Any])?["metaData"] as? [String: Any]
    return metaData?["contentPlayContextPath"] as? String
}

/// Parse getRows(playContext) response into PlayContextActions. Rows have type, path, title, id. Internal for testing.
func parsePlayContextActions(from getRowsResponse: [String: Any]) -> PlayContextActions? {
    guard let rows = getRowsResponse["rows"] as? [[String: Any]] else { return nil }
    var items: [PlayContextItem] = []
    for row in rows {
        guard let path = row["path"] as? String, let title = row["title"] as? String else { continue }
        let typeRaw = row["type"] as? String ?? "action"
        let type: PlayContextItemType = (typeRaw == "container") ? .container : .action
        let id = row["id"] as? String
        items.append(PlayContextItem(type: type, path: path, title: title, id: id))
    }
    return PlayContextActions(items: items)
}
