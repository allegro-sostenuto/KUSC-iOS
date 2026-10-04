import Foundation

/// An observed output set. Names are presentation only; matching uses every UID/transport pair.
public struct ObservedAudioRoute: Codable, Equatable {
    public struct Port: Codable, Equatable {
        public var uid: String
        public var type: String
        public var name: String
        public init(uid: String, type: String, name: String) {
            self.uid = uid; self.type = type; self.name = name
        }
    }
    public var ports: [Port]
    public init(ports: [Port]) { self.ports = ports }
    public var name: String { ports.map(\.name).joined(separator: " + ") }
    public var isBuiltInSpeaker: Bool { !ports.isEmpty && ports.allSatisfy { $0.type == "Speaker" } }
    public var isIdentifiable: Bool {
        !ports.isEmpty && ports.allSatisfy { !$0.uid.isEmpty && !$0.type.isEmpty }
            && Set(ports.map { $0.type + "\u{0}" + $0.uid }).count == ports.count
    }
    public func matches(_ other: Self) -> Bool {
        guard isIdentifiable, other.isIdentifiable else { return false }
        return Set(ports.map { $0.type + "\u{0}" + $0.uid }) == Set(other.ports.map { $0.type + "\u{0}" + $0.uid })
    }
}

public enum ScheduleFallback: String, Codable, CaseIterable {
    case notifyOnly, speaker, currentOutput
}

public enum ScheduledOutputMode: String, Codable {
    case speaker, selected, currentOutput // currentOutput is retained for saved v2 schedules.
}

public struct ScheduledOutputPreference: Codable, Equatable {
    /// nil means use the actual system output at execution, not a cached name.
    public var route: ObservedAudioRoute?
    public var fallback: ScheduleFallback
    public var mode: ScheduledOutputMode
    public init(route: ObservedAudioRoute? = nil, fallback: ScheduleFallback = .notifyOnly,
                mode: ScheduledOutputMode? = nil) {
        self.route = route?.isIdentifiable == true ? route : nil
        self.fallback = fallback
        self.mode = mode ?? (self.route == nil ? .currentOutput : .selected)
    }
    public static var currentOutput: Self { .init() }
    public static var speaker: Self { .init(mode: .speaker) }
    private enum CodingKeys: String, CodingKey { case route, fallback, mode }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(route: try values.decodeIfPresent(ObservedAudioRoute.self, forKey: .route),
                  fallback: try values.decodeIfPresent(ScheduleFallback.self, forKey: .fallback) ?? .notifyOnly,
                  mode: try values.decodeIfPresent(ScheduledOutputMode.self, forKey: .mode))
    }
    public var summary: String {
        if mode == .speaker { return "Always iPhone speaker" }
        guard let route else { return "Current system output" }
        let unavailable = fallback == .notifyOnly ? "notify if unavailable"
            : (fallback == .speaker ? "speaker if unavailable" : "use current output if unavailable")
        return "\(route.name) · \(unavailable)"
    }
    public func permits(_ actual: ObservedAudioRoute) -> Bool {
        if mode == .speaker { return actual.isBuiltInSpeaker }
        if mode == .selected && route == nil { return false }
        guard let route else { return !actual.ports.isEmpty }
        return route.matches(actual) || (fallback == .speaker && actual.isBuiltInSpeaker)
            || (fallback == .currentOutput && !actual.ports.isEmpty)
    }
}

/// Settings are copied into each request so a saved start keeps its exact policy.
public struct ScheduledStartOptions: Codable, Equatable {
    public var allowOnBattery: Bool
    public var batteryOnlyStop: Bool
    public private(set) var batteryPercent: Int
    public private(set) var lowBatteryMinutes: Int
    public init(allowOnBattery: Bool = false, batteryOnlyStop: Bool = false,
                batteryPercent: Int = 25, lowBatteryMinutes: Int = 20) {
        self.allowOnBattery = allowOnBattery || batteryOnlyStop
        self.batteryOnlyStop = batteryOnlyStop
        self.batteryPercent = min(100, max(25, batteryPercent))
        self.lowBatteryMinutes = min(20, max(1, lowBatteryMinutes))
    }
    private enum CodingKeys: String, CodingKey { case allowOnBattery, batteryOnlyStop, batteryPercent, lowBatteryMinutes }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(allowOnBattery: try values.decodeIfPresent(Bool.self, forKey: .allowOnBattery) ?? false,
                  batteryOnlyStop: try values.decodeIfPresent(Bool.self, forKey: .batteryOnlyStop) ?? false,
                  batteryPercent: try values.decodeIfPresent(Int.self, forKey: .batteryPercent) ?? 25,
                  lowBatteryMinutes: try values.decodeIfPresent(Int.self, forKey: .lowBatteryMinutes) ?? 20)
    }
}

/// Counts continuous time below the threshold AND unplugged, using a monotonic clock.
/// Charging or recovering to the threshold resets the countdown. Unknown readings
/// cannot establish a low-battery condition and never manufacture a stop.
public struct ScheduledBatteryGuard {
    public private(set) var lowSince: TimeInterval?
    public init() {}
    public mutating func shouldStop(uptime: TimeInterval, plugged: Bool, level: Double,
                                   options: ScheduledStartOptions) -> Bool {
        if plugged { lowSince = nil; return false }
        guard level.isFinite, (0...1).contains(level) else { lowSince = nil; return false }
        guard level + 0.000_001 < Double(options.batteryPercent) / 100 else { lowSince = nil; return false }
        if lowSince == nil || uptime < lowSince! { lowSince = uptime }
        return uptime - lowSince! >= Double(options.lowBatteryMinutes) * 60
    }
}

public struct ScheduledStartRequest: Codable, Equatable {
    public let id: UUID
    public let date: Date
    public let output: ScheduledOutputPreference
    public let options: ScheduledStartOptions
    public var requiresDeletionToCancel: Bool { output.mode == .speaker && options.batteryOnlyStop }
    public var survivesInterruption: Bool { output.mode == .speaker }
    public init(id: UUID = UUID(), date: Date, output: ScheduledOutputPreference = .currentOutput,
                options: ScheduledStartOptions = .init()) {
        self.id = id; self.date = date; self.output = output
        self.options = .init(allowOnBattery: options.allowOnBattery,
                             batteryOnlyStop: output.mode == .speaker && options.batteryOnlyStop,
                             batteryPercent: options.batteryPercent, lowBatteryMinutes: options.lowBatteryMinutes)
    }
    private enum CodingKeys: String, CodingKey { case id, date, output, options }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try values.decode(UUID.self, forKey: .id), date: try values.decode(Date.self, forKey: .date),
                  output: try values.decode(ScheduledOutputPreference.self, forKey: .output),
                  options: try values.decodeIfPresent(ScheduledStartOptions.self, forKey: .options) ?? .init())
    }
}

public enum ScheduledStartPhase: String, Equatable {
    case waiting, standby, preparing, silent, fading, playing, paused, notificationOnly
}

/// Wall time records the user's intent. Once audio becomes ready, uptime drives the
/// envelope so changing the device clock cannot replay or reverse an audible ramp.
public struct ScheduledGainEnvelope: Equatable {
    public let startUptime: TimeInterval
    public let endUptime: TimeInterval
    public init(target: Date, readyAt: Date, uptime: TimeInterval) {
        let remaining = target.timeIntervalSince(readyAt)
        startUptime = uptime + max(0, remaining - 10)
        endUptime = remaining > 0 ? uptime + remaining : uptime + 10
    }
    public func gain(at uptime: TimeInterval) -> Float {
        guard uptime > startUptime else { return 0 }
        return Float(min(1, max(0, (uptime - startUptime) / max(0.001, endUptime - startUptime))))
    }
    public func isComplete(at uptime: TimeInterval) -> Bool { uptime >= endUptime }
}

public enum ScheduledStartPolicy {
    public static func shouldPrepare(target: Date, now: Date) -> Bool {
        now >= target.addingTimeInterval(-60)
    }
    public static func composedGain(schedule: Float, sleep: Float, muted: Bool) -> Float {
        muted ? 0 : min(1, max(0, schedule)) * min(1, max(0, sleep))
    }
}

/// A value-type intent token shared by scheduling and asynchronous notification setup.
/// New schedules and explicit transport actions invalidate any outstanding completion.
public struct ScheduleGeneration {
    private var value = UUID()
    public init() {}
    public mutating func begin() -> UUID { value = UUID(); return value }
    public mutating func invalidate() { value = UUID() }
    public func accepts(_ candidate: UUID) -> Bool { candidate == value }
}

/// Serializes writes for one schedule ID. A canceled in-flight write is removed
/// after completion; a superseded write is followed by the latest desired write,
/// never by a stale removal of that newer notification.
@MainActor public final class ScheduledNotificationWrites {
    private var generations: [UUID: UUID] = [:]
    private var tails: [UUID: Task<Void, Error>] = [:]

    public init() {}

    @discardableResult public func submit(id: UUID, write: @escaping @MainActor () async throws -> Void,
                                          remove: @escaping @MainActor () -> Void) -> Task<Void, Error> {
        let generation = UUID()
        generations[id] = generation
        let previous = tails[id]
        let task = Task { @MainActor [weak self] in
            if let previous { _ = await previous.result }
            guard let self else { return }
            defer {
                if self.generations[id] == generation || self.generations[id] == nil { self.tails[id] = nil }
            }
            guard self.generations[id] == generation else { return }
            try await write()
            if self.generations[id] == nil { remove() }
        }
        tails[id] = task
        return task
    }

    public func cancel(id: UUID, remove: () -> Void) {
        generations[id] = nil
        // Preserve the pending tail so a replacement with the same ID waits for
        // the old system add operation before writing its newer content.
        remove()
    }
}
