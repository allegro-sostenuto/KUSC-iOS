import Foundation

public enum ReconnectDecision: Equatable {
    case retry(elapsed: TimeInterval)
    case stop
}

public struct ReconnectPolicy {
    public static let timeout: TimeInterval = 60
    public let startedAt: Date

    public init(startedAt: Date) { self.startedAt = startedAt }

    public func decision(at now: Date) -> ReconnectDecision {
        let elapsed = max(0, now.timeIntervalSince(startedAt))
        return elapsed >= Self.timeout ? .stop : .retry(elapsed: elapsed)
    }
}

public enum StandbyDecision: Equatable {
    case standby(unpluggedAt: Date?)
    case notificationOnly
}

public enum StandbyPolicy {
    public static let unplugGrace: TimeInterval = 10 * 60
    public static let minimumBattery: Double = 0.30
    public static let maximumScheduleDelay: TimeInterval = 24 * 60 * 60

    /// A new battery-only schedule never starts silent audio. Grace applies only to a
    /// currently running plugged-in standby session. Unknown battery (-1) is conservative.
    public static func update(now: Date, isPluggedIn: Bool, batteryLevel: Double,
                              unpluggedAt: Date?, wasStandingBy: Bool) -> StandbyDecision {
        if isPluggedIn { return .standby(unpluggedAt: nil) }
        guard wasStandingBy, batteryLevel.isFinite, batteryLevel >= minimumBattery else {
            return .notificationOnly
        }
        let since = unpluggedAt ?? now
        return now.timeIntervalSince(since) < unplugGrace
            ? .standby(unpluggedAt: since)
            : .notificationOnly
    }

    public static func isValidSchedule(_ date: Date, now: Date) -> Bool {
        let delay = date.timeIntervalSince(now)
        return delay > 0 && delay <= maximumScheduleDelay
    }

    public static func shouldStartScheduled(alreadyPlaying: Bool) -> Bool { !alreadyPlaying }
}
