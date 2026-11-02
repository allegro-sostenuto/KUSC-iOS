import Foundation

public enum StationAudioFormat: String, Codable, Sendable {
    case hls, aac, mp3
}

/// Capabilities are explicit: an audio source does not imply a work or programme feed.
public enum StationMetadataCapability: String, Codable, Sendable {
    case kusc, stationOnly, hrt, srP2
}

public struct RadioStation: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let subtitle: String?
    public let websiteURL: URL
    public let logoAssetName: String?
    public let timeZoneIdentifier: String
    public let audioURL: URL
    public let audioFormat: StationAudioFormat
    public let metadataCapability: StationMetadataCapability

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)! }
    public var isHLS: Bool { audioFormat == .hls }
    public var supportsProgrammes: Bool { metadataCapability == .kusc }
}

/// Approved catalogue. Tests/Fixtures/station-catalog.json is its platform parity contract.
/// URLs are broadcaster-owned sources, not directories or relays; see docs/station_sources_v2.md.
public enum StationCatalog {
    public static let stations: [RadioStation] = [
        RadioStation(id: "kusc", name: "KUSC", subtitle: "91.5 FM",
                     websiteURL: URL(string: "https://www.classicalcalifornia.org")!, logoAssetName: "station-kusc",
                     timeZoneIdentifier: "America/Los_Angeles",
                     audioURL: URL(string: "https://playerservices.streamtheworld.com/api/livestream-redirect/KUSCAAC96.m3u8")!,
                     audioFormat: .hls, metadataCapability: .kusc),
        RadioStation(id: "radio-swiss-classic", name: "Radio Swiss Classic", subtitle: nil,
                     websiteURL: URL(string: "https://www.radioswissclassic.ch")!, logoAssetName: "station-swiss",
                     timeZoneIdentifier: "Europe/Zurich",
                     audioURL: URL(string: "https://stream.srg-ssr.ch/srgssr/rsc_de/aac/192")!,
                     audioFormat: .aac, metadataCapability: .stationOnly),
        RadioStation(id: "sr-p2", name: "Sveriges Radio P2", subtitle: "P2 Musik",
                     websiteURL: URL(string: "https://www.sverigesradio.se/kanaler/p2")!, logoAssetName: "station-p2",
                     timeZoneIdentifier: "Europe/Stockholm",
                     audioURL: URL(string: "https://live1.sr.se/p2-aac-320")!,
                     audioFormat: .aac, metadataCapability: .srP2),
        RadioStation(id: "france-musique-classique-easy", name: "France Musique · Classique Easy", subtitle: nil,
                     websiteURL: URL(string: "https://www.radiofrance.fr/francemusique")!, logoAssetName: "station-france-musique",
                     timeZoneIdentifier: "Europe/Paris",
                     audioURL: URL(string: "https://icecast.radiofrance.fr/francemusiqueeasyclassique-hifi.aac")!,
                     audioFormat: .aac, metadataCapability: .stationOnly),
        RadioStation(id: "france-musique-la-baroque", name: "France Musique · La Baroque", subtitle: nil,
                     websiteURL: URL(string: "https://www.radiofrance.fr/francemusique")!, logoAssetName: "station-france-musique",
                     timeZoneIdentifier: "Europe/Paris",
                     audioURL: URL(string: "https://icecast.radiofrance.fr/francemusiquebaroque-hifi.aac")!,
                     audioFormat: .aac, metadataCapability: .stationOnly),
        RadioStation(id: "wdr3", name: "WDR 3", subtitle: nil,
                     websiteURL: URL(string: "https://www1.wdr.de/radio/wdr3")!, logoAssetName: "station-wdr3",
                     timeZoneIdentifier: "Europe/Berlin",
                     audioURL: URL(string: "https://wdr-wdr3-live.icecastssl.wdr.de/wdr/wdr3/live/mp3/256/stream.mp3")!,
                     audioFormat: .mp3, metadataCapability: .stationOnly),
        RadioStation(id: "radio-chopin", name: "Polskie Radio Chopin", subtitle: nil,
                     websiteURL: URL(string: "https://chopin.polskieradio.pl")!, logoAssetName: "station-chopin",
                     timeZoneIdentifier: "Europe/Warsaw",
                     audioURL: URL(string: "https://stream85.polskieradio.pl/live/rytm.sdp/playlist.m3u8")!,
                     audioFormat: .hls, metadataCapability: .stationOnly),
        RadioStation(id: "orpheus-large-scale", name: "Orpheus · Large-Scale Works", subtitle: "Классика крупных форм",
                     websiteURL: URL(string: "https://radio.orpheus.ru/player/8")!, logoAssetName: "station-orpheus",
                     timeZoneIdentifier: "Europe/Moscow",
                     audioURL: URL(string: "https://radio.orpheus.ru:8000/Chan_8_192.mp3")!,
                     audioFormat: .mp3, metadataCapability: .stationOnly),
        RadioStation(id: "orpheus-russian-classical", name: "Orpheus · Russian Classical Music", subtitle: "Классика российской музыки",
                     websiteURL: URL(string: "https://radio.orpheus.ru/player/17")!, logoAssetName: "station-orpheus",
                     timeZoneIdentifier: "Europe/Moscow",
                     audioURL: URL(string: "https://radio.orpheus.ru:8000/Chan_17_192.mp3")!,
                     audioFormat: .mp3, metadataCapability: .stationOnly),
        RadioStation(id: "orpheus-camerata", name: "Orpheus · Camerata", subtitle: "Камерата",
                     websiteURL: URL(string: "https://radio.orpheus.ru/player/76")!, logoAssetName: "station-orpheus",
                     timeZoneIdentifier: "Europe/Moscow",
                     audioURL: URL(string: "https://radio.orpheus.ru:8000/Chan_76_256.mp3")!,
                     audioFormat: .mp3, metadataCapability: .stationOnly),
        RadioStation(id: "hr-klasik", name: "HR Klasik", subtitle: "Hrvatski radio Klasik",
                     websiteURL: URL(string: "https://radio.hrt.hr/stream/25")!, logoAssetName: "station-hr-klasik",
                     timeZoneIdentifier: "Europe/Zagreb",
                     audioURL: URL(string: "https://playerservices.streamtheworld.com/api/livestream-redirect/HR_CLASSICS.mp3")!,
                     audioFormat: .mp3, metadataCapability: .hrt)
    ]

    public static let defaultStation = stations[0]
    public static func station(id: String) -> RadioStation? { stations.first { $0.id == id } }
}

public enum StationDisplayMode: String, Codable, CaseIterable, Sendable {
    case grid, list
}

/// Selection is independent of playback intent and never changes when the order changes.
public struct StationPreferences: Codable, Equatable {
    public var selectedID: String
    public var orderedIDs: [String]
    public var displayMode: StationDisplayMode
    public static let storageKey = "stations.v2"

    public init(selectedID: String = StationCatalog.defaultStation.id,
                orderedIDs: [String] = StationCatalog.stations.map(\.id),
                displayMode: StationDisplayMode = .grid) {
        self.selectedID = selectedID
        self.orderedIDs = orderedIDs
        self.displayMode = displayMode
        normalize()
    }

    private enum CodingKeys: String, CodingKey { case selectedID, orderedIDs, displayMode }

    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        selectedID = (try? fields.decode(String.self, forKey: .selectedID)) ?? StationCatalog.defaultStation.id
        orderedIDs = (try? fields.decode([String].self, forKey: .orderedIDs)) ?? []
        displayMode = (try? fields.decode(StationDisplayMode.self, forKey: .displayMode)) ?? .grid
        normalize()
    }

    public mutating func normalize() {
        let known = Set(StationCatalog.stations.map(\.id))
        var seen = Set<String>()
        orderedIDs = orderedIDs.filter { known.contains($0) && seen.insert($0).inserted }
        orderedIDs += StationCatalog.stations.map(\.id).filter { !seen.contains($0) }
        if !known.contains(selectedID) { selectedID = StationCatalog.defaultStation.id }
    }

    /// Accessible actions stop at the ends; station transport navigation wraps cyclically.
    public mutating func move(id: String, by offset: Int) {
        normalize()
        guard let source = orderedIDs.firstIndex(of: id), offset != 0 else { return }
        let destination: Int
        if offset > 0 { destination = source + min(offset, orderedIDs.count - 1 - source) }
        else { destination = source + max(offset, -source) }
        guard source != destination else { return }
        orderedIDs.remove(at: source)
        orderedIDs.insert(id, at: destination)
    }

    public mutating func move(id: String, before targetID: String) {
        normalize()
        guard id != targetID, let source = orderedIDs.firstIndex(of: id), orderedIDs.contains(targetID) else { return }
        orderedIDs.remove(at: source)
        if let destination = orderedIDs.firstIndex(of: targetID) { orderedIDs.insert(id, at: destination) }
    }

    /// Next/Previous wrap through one shared persisted order in either picker presentation.
    public func adjacent(to id: String, offset: Int) -> String {
        var valid = self
        valid.normalize()
        let count = valid.orderedIDs.count
        let source = valid.orderedIDs.firstIndex(of: id) ?? 0
        let destination = (source + offset % count + count) % count
        return valid.orderedIDs[destination]
    }

    public static func load(defaults: UserDefaults = .standard) -> StationPreferences {
        guard let data = defaults.data(forKey: storageKey),
              var preferences = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        preferences.normalize()
        return preferences
    }

    public func save(defaults: UserDefaults = .standard) {
        var valid = self
        valid.normalize()
        if let data = try? JSONEncoder().encode(valid) { defaults.set(data, forKey: Self.storageKey) }
    }
}
