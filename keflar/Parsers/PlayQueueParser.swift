import Foundation

/// Parse getRows(playlists:pq/getitems) response into PlayQueueResult (items + totalCount). Internal for testing.
func parsePlayQueue(from getRowsResponse: [String: Any]) -> PlayQueueResult {
    let rows = getRowsResponse["rows"] as? [[String: Any]] ?? []
    let totalCount: Int?
    if let count = getRowsResponse["rowsCount"] as? Int {
        totalCount = count
    } else if let num = getRowsResponse["rowsCount"] as? NSNumber {
        totalCount = num.intValue
    } else {
        totalCount = nil
    }
    var items: [PlayQueueItem] = []
    for (offset, row) in rows.enumerated() {
        let index: Int
        if let value = row["value"] as? [String: Any], let queueIndex = value["i32_"] as? Int {
            index = queueIndex
        } else {
            index = offset
        }
        guard let id = row["id"] as? String else { continue }
        let title = row["title"] as? String
        let mediaData = row["mediaData"] as? [String: Any]
        let metaData = mediaData?["metaData"] as? [String: Any]
        let artist = metaData?["artist"] as? String
        let album = metaData?["album"] as? String
        let serviceID = metaData?["serviceID"] as? String
        let coverURL = row["icon"] as? String
        items.append(PlayQueueItem(index: index, id: id, title: title, artist: artist, album: album, coverURL: coverURL, serviceID: serviceID))
    }
    return PlayQueueResult(items: items, totalCount: totalCount)
}
