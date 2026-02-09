import Foundation

/// Build BrowseResult from a getRows response. Handles rows, rowsCount, rowsRedirect.
func parseBrowseResult(from response: [String: Any]) -> BrowseResult {
    let rawRows = response["rows"] as? [[String: Any]] ?? []
    let rows = rawRows.map(parseBrowseRow(from:))
    let totalCount = response["rowsCount"] as? Int
    let redirectedFrom = response["rowsRedirect"] as? String
    return BrowseResult(rows: rows, totalCount: totalCount, redirectedFrom: redirectedFrom)
}

/// Build a single BrowseRow from a getRows row dict. Row may have id, path, title, type, icon at top level or under value/itemValue.
func parseBrowseRow(from row: [String: Any]) -> BrowseRow {
    let candidate = (row["value"] as? [String: Any]) ?? (row["itemValue"] as? [String: Any]) ?? row
    return BrowseRow(
        id: (candidate["id"] as? String) ?? (row["id"] as? String),
        path: (candidate["path"] as? String) ?? (row["path"] as? String),
        title: (candidate["title"] as? String) ?? (row["title"] as? String),
        type: (candidate["type"] as? String) ?? (row["type"] as? String),
        icon: (candidate["icon"] as? String) ?? (row["icon"] as? String)
    )
}
