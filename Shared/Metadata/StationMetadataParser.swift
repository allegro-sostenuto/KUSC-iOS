import Foundation

enum StationMetadataError: LocalizedError {
    case invalidPayload
    case httpStatus(Int)
    case payloadTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidPayload: return "The station's metadata response could not be read."
        case .httpStatus(let status): return "The station's metadata service returned HTTP \(status)."
        case .payloadTooLarge: return "The station's metadata response exceeded the size limit."
        }
    }
}

struct StationProgramme {
    let name: String?
    let host: String?
    let start: Date
    let end: Date
}

struct StationMetadataRecord {
    var item: ProgrammeItem
    let artworkSource: String?
}

/// Tolerates a malformed individual row without discarding the remaining day's history.
enum StationMetadataParser {
    static func combined(_ data: Data) throws -> (records: [StationMetadataRecord], programmes: [StationProgramme]) {
        guard let blocks = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw StationMetadataError.invalidPayload
        }
        var records: [StationMetadataRecord] = []
        var programmes: [StationProgramme] = []
        for block in blocks {
            let programme = parseProgramme(block)
            if let programme { programmes.append(programme) }
            for song in block["songs"] as? [[String: Any]] ?? [] {
                if let record = parseSong(song, programme: programme) { records.append(record) }
            }
        }
        return (records, programmes)
    }

    static func now(_ data: Data, programmes: [StationProgramme]) throws -> StationMetadataRecord? {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StationMetadataError.invalidPayload
        }
        let extra = (object["extraInfo"] as? [String: Any]) ?? [:]
        let start = timestamp(object["start"]) ?? timestamp(extra["AirStarttime"])
        let programme = programmes.first { p in start.map { $0 >= p.start && $0 < p.end } ?? false }
        return parseSong(object, programme: programme)
    }

    private static func parseProgramme(_ object: [String: Any]) -> StationProgramme? {
        guard let start = timestamp(object["start"]), let end = timestamp(object["end"]), end > start else { return nil }
        let extra = (object["extraInfo"] as? [String: Any]) ?? [:]
        let show = (object["show"] as? [String: Any]) ?? [:]
        let host = (object["host"] as? [String: Any]) ?? [:]
        return StationProgramme(name: string(show["name"]) ?? string(object["name"]) ?? string(extra["show_name"]),
                                host: string(host["name"]) ?? string(extra["host_name"]), start: start, end: end)
    }

    private static func parseSong(_ object: [String: Any], programme: StationProgramme?) -> StationMetadataRecord? {
        let extra = (object["extraInfo"] as? [String: Any]) ?? [:]
        // Speech, station identifiers and other non-musical events are not invented as pieces.
        if let kind = string(extra["media_type"]), kind.caseInsensitiveCompare("Song") != .orderedSame { return nil }
        guard let start = timestamp(object["start"]) ?? timestamp(extra["AirStarttime"]),
              let title = string(extra["title"]) ?? string(object["summary"]) ?? string(object["name"]) else { return nil }
        let reportedEnd = timestamp(extra["AirStoptime"]) ?? timestamp(object["end"])
        // Bad endpoints must not cause a timer to wait for hours or make a reversed interval.
        let end = reportedEnd.flatMap { $0 > start && $0.timeIntervalSince(start) <= 6 * 3600 ? $0 : nil }
        let recordingID = string(extra["MMID"]) ?? string(extra["MM_ID"]) ?? string(extra["UniversalIdentifier"]) ?? title
        // The now and day APIs use different object IDs. Broadcast timestamp + recording ID
        // identifies the same airing in both feeds, including repeated airings of one record.
        let id = "kusc-\(Int(start.timeIntervalSince1970))-\(recordingID)"
        var people: [String] = []
        for field in ["Soloist", "Performer", "Orchestra", "Conductor"] {
            if let person = string(extra[field]), !people.contains(person) { people.append(person) }
        }
        let item = ProgrammeItem(id: id, start: start, end: end, work: title,
                                 composer: string(extra["Composer"]) ?? string(extra["artist"]) ?? "",
                                 performers: people.joined(separator: " · "),
                                 programme: programme?.name, host: programme?.host,
                                 timingReliable: end != nil)
        // No separate movement field is supplied by the observed API. Preserve its exact
        // title; do not infer movement boundaries from punctuation or a recording duration.
        return StationMetadataRecord(item: item, artworkSource: string(extra["image"]))
    }

    static func timestamp(_ value: Any?) -> Date? {
        if let fields = value as? [String: Any] { return timestamp(fields["dateTime"]) }
        guard let text = string(value) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = formatter.date(from: text) { return value }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty || result == "N/A" ? nil : result
    }
}
