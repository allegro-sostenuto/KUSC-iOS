import Foundation

public enum SleepDecision: Equatable {
    /// Reliable station item endpoint: keep full volume, then stop at this wall-clock date.
    case stopAt(Date)
    /// A linear gain ramp, including compressed ramps when the transition is imminent.
    case fade(start: Date, end: Date)
    /// Continue requesting metadata until this wall-clock deadline.
    case retry(until: Date)
}

public enum SleepPolicy {
    public static let maximumExtension: TimeInterval = 10 * 60
    public static let fadeDuration: TimeInterval = 60
    public static let metadataRetryDuration: TimeInterval = 60

    /// `heardAt` is the timestamp of audible programme content. It can lag `now`.
    /// Decisions always return wall-clock deadlines so a delayed stream finishes its own piece.
    public static func evaluate(now: Date, heardAt: Date,
                                movementEnd: Date?, movementEndReliable: Bool,
                                nextStart: Date?, retryStartedAt: Date? = nil) -> SleepDecision {
        if movementEndReliable, let movementEnd {
            let remaining = max(0, movementEnd.timeIntervalSince(heardAt))
            if remaining <= maximumExtension {
                return .stopAt(now.addingTimeInterval(remaining))
            }
            return immediateFade(now)
        }

        if let nextStart, nextStart >= heardAt {
            let remaining = nextStart.timeIntervalSince(heardAt)
            if remaining <= maximumExtension {
                let endpoint = now.addingTimeInterval(remaining)
                return .fade(start: max(now, endpoint.addingTimeInterval(-fadeDuration)), end: endpoint)
            }
            return immediateFade(now)
        }

        let retryDeadline = (retryStartedAt ?? now).addingTimeInterval(metadataRetryDuration)
        return now >= retryDeadline ? immediateFade(now) : .retry(until: retryDeadline)
    }

    public static func gain(at date: Date, fadeStart: Date, fadeEnd: Date) -> Double {
        guard fadeEnd > fadeStart else { return date < fadeEnd ? 1 : 0 }
        let duration = fadeEnd.timeIntervalSince(fadeStart)
        return max(0, min(1, fadeEnd.timeIntervalSince(date) / duration))
    }

    private static func immediateFade(_ now: Date) -> SleepDecision {
        .fade(start: now, end: now.addingTimeInterval(fadeDuration))
    }
}
