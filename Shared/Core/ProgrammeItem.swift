import Foundation

/// Station timestamps describe the audio clock, not the device's current wall clock.
public struct ProgrammeItem: Identifiable, Codable, Equatable {
    public var id: String
    public var start: Date
    public var end: Date?
    public var work: String
    public var movement: String?
    public var composer: String
    public var performers: String
    public var artworkURL: URL?
    public var programme: String?
    public var host: String?
    /// True when the station gives an explicit broadcast-item end, never an inferred recording duration.
    public var timingReliable: Bool

    public init(id: String, start: Date, end: Date? = nil, work: String,
                movement: String? = nil, composer: String = "", performers: String = "",
                artworkURL: URL? = nil, programme: String? = nil, host: String? = nil,
                timingReliable: Bool = false) {
        self.id = id
        self.start = start
        self.end = end
        self.work = work
        self.movement = movement
        self.composer = composer
        self.performers = performers
        self.artworkURL = artworkURL
        self.programme = programme
        self.host = host
        self.timingReliable = timingReliable
    }

    public var title: String {
        guard let movement = movement?.trimmingCharacters(in: .whitespacesAndNewlines),
              !movement.isEmpty else { return work }
        return work.isEmpty ? movement : "\(work) — \(movement)"
    }
}

public struct ProgrammeContext: Equatable {
    /// Most recent previous piece first.
    public let previous: [ProgrammeItem]
    public let current: ProgrammeItem?
    /// Next piece first.
    public let upcoming: [ProgrammeItem]
}

public struct PlaybackTimeline {
    public private(set) var items: [ProgrammeItem] = []
    public let capacity: Int

    public init(items: [ProgrammeItem] = [], capacity: Int = 256) {
        self.capacity = max(1, min(256, capacity))
        merge(items)
    }

    /// Updates existing identities, sorts station timestamps, and bounds cached history.
    public mutating func merge(_ incoming: [ProgrammeItem]) {
        var byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for item in incoming { byID[item.id] = item }
        let sorted = byID.values.sorted {
            $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start
        }
        items = Array(sorted.suffix(capacity))
    }

    public func item(at timestamp: Date) -> ProgrammeItem? {
        guard let candidate = items.last(where: { $0.start <= timestamp }) else { return nil }
        // An explicit endpoint leaves a gap rather than assigning ended music to speech.
        if let end = candidate.end, end <= timestamp { return nil }
        return candidate
    }

    public func context(at timestamp: Date) -> ProgrammeContext {
        let current = item(at: timestamp)
        let previous = items.filter { $0.start <= timestamp && $0.id != current?.id }
        let upcoming = items.filter { $0.start > timestamp }
        return ProgrammeContext(previous: Array(previous.suffix(5).reversed()),
                                current: current, upcoming: Array(upcoming.prefix(10)))
    }
}
