import Foundation

/// Processes event batches: parses raw event dicts into SpeakerEvents.
actor EventProcessor {
    /// Parse event batch from poll queue response.
    func parse(rawEvents: [[String: Any]]) -> SpeakerEvents {
        var pathToItemValue: [String: Any] = [:]
        for item in rawEvents {
            guard let path = item["path"] as? String,
                  let itemValue = item["itemValue"] else { continue }
            pathToItemValue[path] = itemValue
        }
        return EventParser.parseEvents(pathToItemValue: pathToItemValue)
    }
}
