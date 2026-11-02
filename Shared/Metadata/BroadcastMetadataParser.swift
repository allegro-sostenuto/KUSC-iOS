import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Adapters for the broadcaster-owned feeds. A missing field stays missing;
/// a recording duration is never promoted to a broadcast endpoint.
enum BroadcastMetadataParser {
    static let hrtURL = URL(string: "https://np.tritondigital.com/public/nowplaying?mountName=HR_CLASSICS&numberToFetch=10&eventType=track")!
    static let srP2URL = URL(string: "https://api.sr.se/api/v2/playlists/rightnow?channelid=2562&format=json")!

    static func srP2(_ data: Data) throws -> [ProgrammeItem] {
        let response = try JSONDecoder().decode(SRResponse.self, from: data)
        guard response.playlist.channel.id == 2562 else { return [] }
        return [response.playlist.previoussong, response.playlist.song, response.playlist.nextsong].compactMap { song in
            guard let song, let start = srDate(song.starttimeutc), !song.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let end = srDate(song.stoptimeutc).flatMap { $0 > start ? $0 : nil }
            return ProgrammeItem(id: "sr-p2-\(Int(start.timeIntervalSince1970))", start: start, end: end,
                work: song.title, composer: song.composer ?? "", performers: song.artist ?? "", timingReliable: end != nil)
        }
    }

    static func hrt(_ data: Data) throws -> [ProgrammeItem] {
        let delegate = HRTDelegate()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? CocoaError(.fileReadCorruptFile) }
        // Identifier stings still close the previous item's interval. Dropping
        // them without that boundary would claim the old work continued playing.
        let rows = delegate.rows.sorted { $0.start < $1.start }
        return rows.enumerated().compactMap { index, row in
            let title = row.values["cue_title"] ?? ""
            let performer = row.values["track_artist_name"] ?? ""
            guard !title.isEmpty, title.uppercased() != "HRVATSKI RADIO", performer.uppercased() != "HR KLASIK" else { return nil }
            let next = index + 1 < rows.count ? rows[index + 1].start : nil
            return ProgrammeItem(id: "hr-klasik-\(Int(row.start.timeIntervalSince1970 * 1000))", start: row.start,
                end: next, work: title, composer: row.values["track_album_name"] ?? "", performers: performer,
                timingReliable: false)
        }
    }

    static func srDate(_ value: String?) -> Date? {
        guard let value, value.hasPrefix("/Date("), let close = value.firstIndex(of: ")") else { return nil }
        let number = value[value.index(value.startIndex, offsetBy: 6)..<close]
        guard let milliseconds = Double(number), milliseconds.isFinite else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }

    private struct SRResponse: Decodable { let playlist: SRPlaylist }
    private struct SRPlaylist: Decodable {
        let channel: SRChannel
        let previoussong: SRSong?
        let song: SRSong?
        let nextsong: SRSong?
    }
    private struct SRChannel: Decodable { let id: Int }
    private struct SRSong: Decodable {
        let title: String
        let artist: String?
        let composer: String?
        let starttimeutc: String?
        let stoptimeutc: String?
    }

    private final class HRTDelegate: NSObject, XMLParserDelegate {
        struct Row { let start: Date; let values: [String: String] }
        var rows: [Row] = []
        private var values: [String: String] = [:]
        private var timestamp: Double?
        private var key: String?
        private var text = ""
        private var accepted = false
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            if name == "nowplaying-info" {
                values = [:]; timestamp = attributes["timestamp"].flatMap(Double.init)
                accepted = attributes["mountName"] == "HR_CLASSICS" && attributes["type"] == "track"
            } else if name == "property" { key = attributes["name"]; text = "" }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { if key != nil { text += string } }
        func parser(_ parser: XMLParser, foundCDATA data: Data) { if key != nil { text += String(decoding: data, as: UTF8.self) } }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "property", let key { values[key] = text.trimmingCharacters(in: .whitespacesAndNewlines); self.key = nil }
            if name == "nowplaying-info", accepted {
                let seconds = values["cue_time_start"].flatMap(Double.init).map { $0 / 1000 } ?? timestamp
                if let seconds, seconds.isFinite { rows.append(Row(start: Date(timeIntervalSince1970: seconds), values: values)) }
            }
        }
    }
}
