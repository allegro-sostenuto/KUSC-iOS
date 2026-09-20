import Foundation

public struct AudioSegment: Identifiable, Equatable {
    public let id: UUID
    public let url: URL
    public let start: Date
    public let end: Date
    public let byteCount: Int
    public let discontinuity: Bool

    public init(id: UUID = UUID(), url: URL, start: Date, end: Date, byteCount: Int, discontinuity: Bool = false) {
        self.id = id
        self.url = url
        self.start = start
        self.end = end
        self.byteCount = max(0, byteCount)
        self.discontinuity = discontinuity
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

/// A live join is intentionally behind the downloaded edge. After joining, its
/// clock advances continuously instead of jumping by one HLS segment per fetch.
/// The margin is a bounded initial policy, not a claim of measured device latency.
public struct LivePlaybackClock {
    public static let joinHeadroom: TimeInterval = 8
    public static let minimumHeadroom: TimeInterval = 2
    public static let maximumHeadroom: TimeInterval = 128
    private var anchor: Date?
    private var anchorUptime: TimeInterval = 0

    public init() {}

    public mutating func target(in result: RetentionResult, uptime: TimeInterval) -> Date? {
        guard let rawWindow = result.window, let newest = result.retained.last else { return nil }
        // Never cross a gap to manufacture headroom. The last continuous suffix
        // alone determines the join point; earlier history remains seekable.
        var suffixStart = newest.start
        var discontinuity = newest.discontinuity
        for segment in result.retained.dropLast().reversed() {
            guard !discontinuity, suffixStart.timeIntervalSince(segment.end) <= 0.05 else { break }
            suffixStart = min(suffixStart, segment.start)
            discontinuity = segment.discontinuity
        }
        let earliest = max(rawWindow.oldest, suffixStart)
        let ceiling = max(earliest, newest.end.addingTimeInterval(-Self.minimumHeadroom))
        // A full segment may not become available until its complete duration
        // passes. Cover that observed cadence plus the two-second poll and a
        // provisional two-second download allowance, not just a fixed 8 seconds.
        let segmentDuration = result.retained.suffix(2).map { $0.end.timeIntervalSince($0.start) }.max() ?? 0
        let headroom = min(64, max(Self.joinHeadroom, segmentDuration + 4))
        let recoveryLimit = min(Self.maximumHeadroom, max(16, headroom + segmentDuration))
        if anchor == nil {
            anchor = max(earliest, newest.end.addingTimeInterval(-headroom))
            anchorUptime = uptime
        }
        let projected = anchor!.addingTimeInterval(max(0, uptime - anchorUptime))
        var target = min(ceiling, max(earliest, projected))
        // Recovery may reveal a large acquisition gap. Keep the live definition
        // bounded without moving a deliberately delayed listener's actual cursor.
        if newest.end.timeIntervalSince(target) > recoveryLimit {
            target = min(ceiling, max(earliest, newest.end.addingTimeInterval(-headroom)))
        }
        // Reanchor whenever capped, so time spent starved never becomes a jump
        // when a new file arrives. Explicit gaps may advance to the next suffix.
        anchor = target
        anchorUptime = uptime
        return target
    }

    public static func seekTarget(_ requested: Date, liveTarget: Date,
                                  result: RetentionResult) -> Date? {
        BufferRetention.seekTarget(min(requested, liveTarget), result: result)
    }

    public static func isAtLive(heardAt: Date, liveTarget: Date, acquisitionIsStale: Bool) -> Bool {
        !acquisitionIsStale && heardAt >= liveTarget.addingTimeInterval(-0.75)
    }
}

public enum AcquisitionPollPolicy {
    /// Work already spent downloading is part of the interval, not extra delay.
    public static func delay(targetDuration: TimeInterval, elapsed: TimeInterval) -> TimeInterval {
        max(0, max(0.5, min(2, targetDuration / 4)) - max(0, elapsed))
    }
}

public enum BufferQueuePolicy {
    /// Manifest order/identity determines the next file. Small timestamp overlap
    /// does not authorize dropping an entire segment of otherwise valid audio.
    public static func followers(after tail: AudioSegment, retained: [AudioSegment],
                                 alreadyQueued: Set<UUID>, limit: Int) -> [AudioSegment] {
        let candidates: [AudioSegment]
        if let index = retained.firstIndex(where: { $0.id == tail.id }) {
            candidates = Array(retained.dropFirst(index + 1))
        } else {
            // A paused queue can outlive retention trimming of its old tail.
            candidates = retained.filter { $0.end > tail.end }
        }
        return Array(candidates.filter { !alreadyQueued.contains($0.id) }.prefix(max(0, limit)))
    }
}

/// Retains actual media time when the queue has no current item. Only an
/// explicitly confirmed seek is allowed to move this cursor backwards.
public struct ConfirmedPlaybackCursor {
    public private(set) var position: Date?
    public init() {}

    public mutating func record(_ date: Date?, confirmingSeek: Bool = false) {
        guard let date else { return }
        if confirmingSeek || position == nil { position = date }
        else { position = max(position!, date) }
    }
}

/// A completion belongs only to the latest still-active seek. Pause, Live,
/// teardown and a replacement seek revoke every prior completion.
public struct PlaybackSeekGeneration {
    public private(set) var pending: UUID?
    public init() {}
    @discardableResult public mutating func begin() -> UUID {
        let request = UUID()
        pending = request
        return request
    }
    public mutating func invalidate() { pending = nil }
    public func accepts(_ request: UUID) -> Bool { pending == request }
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
