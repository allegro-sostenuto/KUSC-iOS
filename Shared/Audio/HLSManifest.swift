import Foundation

struct HLSVariant {
    let bandwidth: Int
    let url: URL
}

struct HLSMediaSegment {
    let sequence: Int64
    let url: URL
    var start: Date?
    let duration: TimeInterval
    let discontinuity: Bool
    let discontinuitySequence: Int64
    var end: Date? { start?.addingTimeInterval(duration) }
}

struct HLSManifest {
    let variants: [HLSVariant]
    let segments: [HLSMediaSegment]
    let targetDuration: TimeInterval
    let ended: Bool
    private let playlistURL: URL

    /// Parses the station's unencrypted AAC HLS format. Unsupported encryption,
    /// byte ranges and fragmented MP4 fail explicitly rather than corrupting audio.
    static func parse(_ data: Data, baseURL: URL, previous: HLSManifest? = nil) throws -> HLSManifest {
        guard data.count <= 1024 * 1024,
              let text = String(data: data, encoding: .utf8), text.hasPrefix("#EXTM3U") else {
            throw AudioStreamError.unsupportedFormat("invalid HLS playlist")
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let whole = ISO8601DateFormatter()
        var variants: [HLSVariant] = []
        var segments: [HLSMediaSegment] = []
        var sequence: Int64 = 0
        var nextDate: Date?
        var hasPendingExplicitDate = false
        var nextDuration: Double?
        var nextBandwidth: Int?
        var nextDiscontinuity = false
        var discontinuitySequence: Int64 = 0
        var target: Double = 10
        var ended = false
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                let attributes = line.dropFirst("#EXT-X-STREAM-INF:".count).split(separator: ",")
                nextBandwidth = attributes.first(where: { $0.hasPrefix("BANDWIDTH=") })
                    .flatMap { Int($0.dropFirst("BANDWIDTH=".count)) } ?? 0
            } else if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                sequence = Int64(line.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count)) ?? 0
            } else if line.hasPrefix("#EXT-X-TARGETDURATION:") {
                target = Double(line.dropFirst("#EXT-X-TARGETDURATION:".count)) ?? 10
                guard target > 0, target <= 60 else { throw AudioStreamError.invalidAAC }
            } else if line.hasPrefix("#EXT-X-PROGRAM-DATE-TIME:") {
                let value = String(line.dropFirst("#EXT-X-PROGRAM-DATE-TIME:".count))
                guard let date = fractional.date(from: value) ?? whole.date(from: value) else {
                    throw AudioStreamError.unsupportedFormat("invalid HLS program date")
                }
                nextDate = date
                hasPendingExplicitDate = true
            } else if line.hasPrefix("#EXT-X-DISCONTINUITY-SEQUENCE:") {
                guard segments.isEmpty, !nextDiscontinuity,
                      let value = Int64(line.dropFirst("#EXT-X-DISCONTINUITY-SEQUENCE:".count)), value >= 0 else {
                    throw AudioStreamError.unsupportedFormat("invalid HLS discontinuity sequence")
                }
                discontinuitySequence = value
            } else if line == "#EXT-X-DISCONTINUITY" {
                nextDiscontinuity = true
                guard discontinuitySequence < Int64.max else {
                    throw AudioStreamError.unsupportedFormat("HLS discontinuity sequence overflow")
                }
                discontinuitySequence += 1
                // Both tags describe the following segment, regardless of their
                // ordering. Discard inherited time, never that segment's own PDT.
                if !hasPendingExplicitDate { nextDate = nil }
            } else if line.hasPrefix("#EXTINF:") {
                let value = line.dropFirst("#EXTINF:".count).split(separator: ",", maxSplits: 1).first
                guard let value, let duration = Double(value), duration.isFinite, duration > 0, duration <= 60 else {
                    throw AudioStreamError.unsupportedFormat("invalid HLS duration")
                }
                nextDuration = duration
            } else if line.hasPrefix("#EXT-X-KEY:"), !line.contains("METHOD=NONE") {
                throw AudioStreamError.unsupportedFormat("encrypted HLS")
            } else if line.hasPrefix("#EXT-X-BYTERANGE:") || line.hasPrefix("#EXT-X-MAP:") {
                throw AudioStreamError.unsupportedFormat("HLS byte ranges or fragmented MP4")
            } else if line == "#EXT-X-ENDLIST" {
                ended = true
            } else if !line.hasPrefix("#") {
                guard let url = URL(string: line, relativeTo: baseURL)?.absoluteURL,
                      url.scheme == "https" else {
                    throw AudioStreamError.unsupportedFormat("non-HTTPS segment URL")
                }
                if let bandwidth = nextBandwidth {
                    variants.append(HLSVariant(bandwidth: bandwidth, url: url))
                    nextBandwidth = nil
                } else if let duration = nextDuration {
                    segments.append(HLSMediaSegment(sequence: sequence, url: url,
                                                    start: nextDate, duration: duration,
                                                    discontinuity: nextDiscontinuity,
                                                    discontinuitySequence: discontinuitySequence))
                    sequence += 1
                    nextDate = nextDate?.addingTimeInterval(duration)
                    nextDuration = nil
                    nextDiscontinuity = false
                    hasPendingExplicitDate = false
                }
            }
        }
        guard !variants.isEmpty || !segments.isEmpty else {
            throw AudioStreamError.unsupportedFormat("empty HLS playlist")
        }
        let resolved = reconcile(segments, previous: previous, baseURL: baseURL)
        return HLSManifest(variants: variants, segments: resolved,
                           targetDuration: target, ended: ended, playlistURL: baseURL)
    }

    /// A sliding playlist may evict its only PDT while retaining media whose
    /// station timestamp was established on the previous refresh. Reuse that
    /// evidence only inside the same playlist/connection and a verified overlap.
    /// New explicit PDT values have already been applied and are never replaced.
    private static func reconcile(_ segments: [HLSMediaSegment], previous: HLSManifest?,
                                  baseURL: URL) -> [HLSMediaSegment] {
        guard let previous, previous.playlistURL == baseURL, !previous.ended,
              let first = segments.first, let last = segments.last,
              let oldFirst = previous.segments.first, let oldLast = previous.segments.last,
              first.sequence >= oldFirst.sequence, last.sequence >= oldLast.sequence,
              hasContiguousSequences(segments), hasContiguousSequences(previous.segments) else { return segments }

        let older = Dictionary(uniqueKeysWithValues: previous.segments.map { ($0.sequence, $0) })
        let overlap = segments.filter { older[$0.sequence] != nil }
        guard !overlap.isEmpty, overlap.allSatisfy({ segment in
            guard let old = older[segment.sequence] else { return false }
            return segment.url == old.url && segment.duration == old.duration &&
                segment.discontinuitySequence == old.discontinuitySequence &&
                (!segment.discontinuity || old.discontinuity)
        }) else { return segments }
        // A fresh clock later in the overlap must not leave an earlier cached
        // prefix on a conflicting timeline. Keep the current playlist's own
        // dates in that case; a sub-microsecond tolerance covers Date rounding.
        guard overlap.allSatisfy({ segment in
            guard let currentStart = segment.start, let oldStart = older[segment.sequence]?.start else { return true }
            return abs(currentStart.timeIntervalSince(oldStart)) <= 0.000_001
        }) else { return segments }

        var resolved = segments
        var precedingEnd: Date?
        for index in resolved.indices {
            if resolved[index].discontinuity { precedingEnd = nil }
            if resolved[index].start == nil {
                // A known overlapping media item is an anchor, not a guess from
                // device time or lastEnd. An undated new discontinuity cannot
                // inherit the preceding region's clock.
                if let oldStart = older[resolved[index].sequence]?.start {
                    resolved[index].start = oldStart
                } else if !resolved[index].discontinuity {
                    resolved[index].start = precedingEnd
                }
            }
            precedingEnd = resolved[index].end
        }
        return resolved
    }

    private static func hasContiguousSequences(_ segments: [HLSMediaSegment]) -> Bool {
        zip(segments, segments.dropFirst()).allSatisfy { previous, next in
            previous.sequence < Int64.max && next.sequence == previous.sequence + 1
        }
    }
}
