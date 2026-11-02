import Foundation

/// One atomic record keeps artwork, heard-item metadata and transport intent in sync.
struct WidgetPlaybackSnapshot: Codable, Equatable {
    static let lifetime: TimeInterval = 120
    var updatedAt: Date
    var playbackRequested: Bool
    var stationID: String
    var stationName: String
    var work: String
    var movement: String
    var composer: String
    var performers: String
    var programme: String
    var host: String
    var artwork: Data?

    init(updatedAt: Date = Date(), playbackRequested: Bool = false,
         item: ProgrammeItem? = nil, programme: String? = nil, host: String? = nil,
         artwork: Data? = nil, stationID: String = "kusc", stationName: String = "KUSC") {
        self.updatedAt = updatedAt
        self.playbackRequested = playbackRequested
        self.stationID = String(stationID.prefix(100))
        self.stationName = String(stationName.prefix(160))
        work = String((item?.work ?? stationName).prefix(240))
        movement = String((item?.movement ?? "").prefix(200))
        composer = String((item?.composer ?? "").prefix(160))
        performers = String((item?.performers ?? "").prefix(240))
        self.programme = String((programme ?? item?.programme ?? "").prefix(160))
        self.host = String((host ?? item?.host ?? "").prefix(160))
        self.artwork = artwork.flatMap { $0.count <= 120_000 ? $0 : nil }
    }

    private enum CodingKeys: String, CodingKey {
        case updatedAt, playbackRequested, stationID, stationName, work, movement, composer, performers, programme, host, artwork
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        playbackRequested = try values.decode(Bool.self, forKey: .playbackRequested)
        // The existing app-group file and widget kinds remain compatible.
        // Snapshots written by version 1 have no explicit station identity.
        stationID = try values.decodeIfPresent(String.self, forKey: .stationID) ?? "kusc"
        stationName = try values.decodeIfPresent(String.self, forKey: .stationName) ?? "KUSC"
        work = try values.decode(String.self, forKey: .work)
        movement = try values.decode(String.self, forKey: .movement)
        composer = try values.decode(String.self, forKey: .composer)
        performers = try values.decode(String.self, forKey: .performers)
        programme = try values.decode(String.self, forKey: .programme)
        host = try values.decode(String.self, forKey: .host)
        artwork = try values.decodeIfPresent(Data.self, forKey: .artwork)
    }

    func requestingPlayback(at date: Date) -> Bool {
        playbackRequested && date.timeIntervalSince(updatedAt) < Self.lifetime
    }

    func hasSameContent(as other: Self) -> Bool {
        var copy = self
        copy.updatedAt = other.updatedAt
        return copy == other
    }

    static func groupIdentifiers(configured: String, resigned: [String]) -> [String] {
        // AltStore publishes the newly provisioned IDs in ALTAppGroups. Never
        // select an unrelated group, nor share the classic and modern app state.
        resigned.filter { $0 == configured || $0.hasPrefix(configured + ".") } + [configured]
    }
}

struct WidgetSnapshotStore {
    let directory: URL
    private var file: URL { directory.appendingPathComponent("playback-widget-v1.json") }

    func read() -> WidgetPlaybackSnapshot? {
        guard let data = try? Data(contentsOf: file), data.count <= 200_000 else { return nil }
        return try? JSONDecoder().decode(WidgetPlaybackSnapshot.self, from: data)
    }

    func write(_ snapshot: WidgetPlaybackSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: file, options: .atomic)
        #endif
    }

    #if os(iOS)
    static var shared: Self? {
        guard let configured = Bundle.main.object(forInfoDictionaryKey: "PhilharmonicAppGroup") as? String else { return nil }
        let resigned = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        for identifier in WidgetPlaybackSnapshot.groupIdentifiers(configured: configured, resigned: resigned) {
            if let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
                return Self(directory: directory)
            }
        }
        return nil
    }
    #endif
}
