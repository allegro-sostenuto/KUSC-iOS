import Foundation

public struct AudioSegment: Identifiable, Equatable {
    public let id: UUID
    public let url: URL
    public let start: Date
    public let end: Date
    public let byteCount: Int

    public init(id: UUID = UUID(), url: URL, start: Date, end: Date, byteCount: Int) {
        self.id = id
        self.url = url
        self.start = start
        self.end = end
        self.byteCount = max(0, byteCount)
    }
}

/// A closed cursor range. Actual audio segments use half-open [start, end) intervals.
public struct BufferWindow: Equatable {
    public let oldest: Date
    public let live: Date

    public init(oldest: Date, live: Date) {
        self.live = live
        self.oldest = min(oldest, live)
    }

    public var duration: TimeInterval { live.timeIntervalSince(oldest) }
    public func contains(_ timestamp: Date) -> Bool { timestamp >= oldest && timestamp <= live }
    public func clamped(_ timestamp: Date) -> Date { min(live, max(oldest, timestamp)) }
}

public struct RetentionResult {
    public let retained: [AudioSegment]
    public let expired: [AudioSegment]
    public let window: BufferWindow?
}

public enum BufferRetention {
    public static let maximumMinutes = 15
    public static let maximumBytes = 64 * 1_024 * 1_024
    public static let maximumSegments = 512

    /// Straddling segments stay on disk, but their expired prefix is immediately unseekable.
    /// Hard byte/segment ceilings also bound storage if source timing becomes malformed.
    public static func trim(_ segments: [AudioSegment], live: Date, minutes: Int,
                            byteLimit: Int = maximumBytes,
                            segmentLimit: Int = maximumSegments) -> RetentionResult {
        let duration = TimeInterval(max(0, min(maximumMinutes, minutes)) * 60)
        guard duration > 0, byteLimit > 0, segmentLimit > 0 else {
            return RetentionResult(retained: [], expired: segments, window: nil)
        }
        let cutoff = live.addingTimeInterval(-duration)
        let candidates = segments.filter {
            $0.end > cutoff && $0.start < live && $0.end > $0.start
        }.sorted { $0.start < $1.start }
        var bytes = 0
        var retained: [AudioSegment] = []
        for segment in candidates.reversed() {
            guard retained.count < segmentLimit, segment.byteCount <= byteLimit - bytes else { break }
            retained.append(segment)
            bytes += segment.byteCount
        }
        retained.reverse()
        let retainedIDs = Set(retained.map(\.id))
        let expired = segments.filter { !retainedIDs.contains($0.id) }
        let window: BufferWindow?
        if let first = retained.first, let last = retained.last {
            window = BufferWindow(oldest: max(cutoff, first.start), live: min(live, last.end))
        } else {
            window = nil
        }
        return RetentionResult(retained: retained, expired: expired, window: window)
    }

    /// Resolves discontinuities to the next available segment, never to missing audio.
    public static func seekTarget(_ requested: Date, result: RetentionResult) -> Date? {
        guard let window = result.window else { return nil }
        let target = window.clamped(requested)
        if target == window.live { return target }
        for segment in result.retained {
            if target >= segment.start && target < segment.end { return target }
            if segment.start > target { return window.clamped(segment.start) }
        }
        return window.live
    }
}

public enum ResumeMode: String, Codable, CaseIterable {
    case live
    case wherePaused
}

public enum ResumePolicy {
    public static func target(mode: ResumeMode, pausedAt: Date?, window: BufferWindow) -> Date {
        guard mode == .wherePaused, let pausedAt else { return window.live }
        return window.clamped(pausedAt)
    }
}
