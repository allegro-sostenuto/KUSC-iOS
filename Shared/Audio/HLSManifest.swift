import Foundation

struct HLSVariant {
    let bandwidth: Int
    let url: URL
}

struct HLSMediaSegment {
    let sequence: Int64
    let url: URL
    let start: Date?
    let duration: TimeInterval
    var end: Date? { start?.addingTimeInterval(duration) }
}

struct HLSManifest {
    let variants: [HLSVariant]
    let segments: [HLSMediaSegment]
    let targetDuration: TimeInterval
    let ended: Bool

    /// Parses the station's unencrypted AAC HLS format. Unsupported encryption,
    /// byte ranges and fragmented MP4 fail explicitly rather than corrupting audio.
    static func parse(_ data: Data, baseURL: URL) throws -> HLSManifest {
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
        var nextDuration: Double?
        var nextBandwidth: Int?
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
                                                    start: nextDate, duration: duration))
                    sequence += 1
                    nextDate = nextDate?.addingTimeInterval(duration)
                    nextDuration = nil
                }
            }
        }
        guard !variants.isEmpty || !segments.isEmpty else {
            throw AudioStreamError.unsupportedFormat("empty HLS playlist")
        }
        return HLSManifest(variants: variants, segments: segments,
                           targetDuration: target, ended: ended)
    }
}
