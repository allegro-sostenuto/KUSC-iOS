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
    case notifyOnly, currentOutput
}

public struct ScheduledOutputPreference: Codable, Equatable {
    /// nil means use the actual system output at execution, not a cached name.
    public var route: ObservedAudioRoute?
    public var fallback: ScheduleFallback
    public init(route: ObservedAudioRoute? = nil, fallback: ScheduleFallback = .notifyOnly) {
        self.route = route?.isIdentifiable == true ? route : nil
        self.fallback = fallback
    }
    public static var currentOutput: Self { .init() }
    public var summary: String {
        guard let route else { return "Current system output" }
        return "\(route.name) · \(fallback == .notifyOnly ? "notify if unavailable" : "use current output if unavailable")"
    }
    public func permits(_ actual: ObservedAudioRoute) -> Bool {
        guard let route else { return !actual.ports.isEmpty }
        return route.matches(actual) || (fallback == .currentOutput && !actual.ports.isEmpty)
    }
}

public struct ScheduledStartRequest: Codable, Equatable {
    public let id: UUID
    public let date: Date
    public let output: ScheduledOutputPreference
    public init(id: UUID = UUID(), date: Date, output: ScheduledOutputPreference = .currentOutput) {
        self.id = id; self.date = date; self.output = output
    }
}

public enum ScheduledStartPhase: String, Equatable {
    case waiting, standby, preparing, silent, fading, notificationOnly
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
