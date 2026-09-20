import Foundation

/// User-controlled, memory-only diagnostics. The first failure freezes the
/// bounded pre-failure history until the next explicit start.
public struct PlaybackDiagnosticLog {
    public private(set) var isRecording = false
    public private(set) var hasFailure = false

    private static let eventLimit = 256
    private static let lineByteLimit = 1_000
    private var context = ""
    private var startedAt: Date?
    private var startedUptime: TimeInterval = 0
    private var events: [String] = []

    public init() {}

    public var report: String {
        guard let startedAt else { return "No playback diagnostic recording." }
        let status = hasFailure ? "First failure captured; recording frozen." :
            (isRecording ? "Recording." : "Recording stopped.")
        let heading = "KUSC playback diagnostics\n\(status)\nStarted: \(Self.wallTime(startedAt))\nContext: \(context)"
        return heading + (events.isEmpty ? "" : "\n\n" + events.joined(separator: "\n"))
    }

    public mutating func start(context: String, date: Date = Date(),
                               uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.context = Self.sanitize(context)
        startedAt = date
        startedUptime = uptime
        events.removeAll(keepingCapacity: true)
        hasFailure = false
        isRecording = true
    }

    public mutating func record(_ event: String, date: Date = Date(),
                                uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard isRecording, !hasFailure else { return }
        append(event, date: date, uptime: uptime)
    }

    public mutating func captureFailure(_ message: String, date: Date = Date(),
                                        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard isRecording, !hasFailure else { return }
        let prefix = eventPrefix(date: date, uptime: uptime)
        // Sanitize the complete message before splitting, so a credential or URL
        // cannot escape redaction by crossing a continuation boundary.
        let message = Self.sanitize(message, limit: 4_000)
        let payloadLimit = Self.lineByteLimit - prefix.utf8.count - 48
        let causes = message.components(separatedBy: " <- ")
        // Keep normal NSError cause headings together. For arbitrary messages
        // with many separators, chunk the whole bounded text instead of creating
        // enough tiny continuation events to displace the failure itself.
        let parts = causes.count <= 8 ? causes : [message]
        let chunks = parts.enumerated().flatMap { index, part in
            Self.chunks((index == 0 ? "" : "<- ") + part, bytes: payloadLimit)
        }
        for (index, chunk) in chunks.enumerated() {
            let marker = chunks.count == 1 ? "FAILURE: " :
                (index == 0 ? "FAILURE [1/\(chunks.count)]: " : "FAILURE continuation [\(index + 1)/\(chunks.count)]: ")
            appendLine(prefix + marker + chunk)
        }
        hasFailure = true
        isRecording = false
    }

    public mutating func stop() { isRecording = false }

    /// Includes only the standard diagnostic fields, never a dump of userInfo.
    /// Four error objects at most are inspected; repeated NSError identities stop
    /// traversal even when an underlying-error graph contains a cycle.
    public static func sanitizedError(_ error: Error) -> String {
        var current: NSError? = error as NSError
        var seen = Set<ObjectIdentifier>()
        var pieces: [String] = []
        while let value = current, pieces.count < 4 {
            guard seen.insert(ObjectIdentifier(value)).inserted else {
                pieces.append("[underlying error cycle]")
                current = nil
                break
            }
            pieces.append("\(sanitize(value.domain, limit: 160)) (code \(value.code)): \(sanitize(value.localizedDescription, limit: 700))")
            current = (value.userInfo[NSUnderlyingErrorKey] as? Error).map { $0 as NSError }
        }
        if current != nil { pieces.append("[underlying error chain truncated]") }
        return bounded(pieces.joined(separator: " <- "), bytes: 4_000)
    }

    private mutating func append(_ event: String, date: Date, uptime: TimeInterval) {
        appendLine(eventPrefix(date: date, uptime: uptime) + Self.sanitize(event))
    }

    private mutating func appendLine(_ line: String) {
        events.append(Self.bounded(line, bytes: Self.lineByteLimit))
        if events.count > Self.eventLimit { events.removeFirst(events.count - Self.eventLimit) }
    }

    private func eventPrefix(date: Date, uptime: TimeInterval) -> String {
        let elapsed: String
        if uptime.isFinite, startedUptime.isFinite, uptime >= startedUptime {
            elapsed = "+" + Self.number(uptime - startedUptime) + "s"
        } else { elapsed = "unavailable" }
        let monotonic = uptime.isFinite ? Self.number(uptime) : "unavailable"
        let prefix = "\(Self.wallTime(date)) | uptime=\(monotonic) | elapsed=\(elapsed) | "
        return Self.bounded(prefix, bytes: 300)
    }

    private static func wallTime(_ date: Date) -> String {
        guard date.timeIntervalSince1970.isFinite else { return "wall time unavailable" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func sanitize(_ input: String, limit: Int = lineByteLimit) -> String {
        // Bound temporary work as well as retained output. Decode escaped URLs so
        // their query/session tokens cannot bypass the same redaction rules.
        var text = bounded(input, bytes: 16_384)
        for _ in 0..<2 {
            guard let decoded = text.removingPercentEncoding, decoded != text else { break }
            text = decoded
        }
        let replacements: [(String, String)] = [
            // Remove the whole URL, including userinfo, path, query and fragment.
            (#"(?i)\b(?:https?|file)(?:%3a|%253a)(?:%2f|%252f){2}[^\r\n<>\"']+"#, "[URL redacted]"),
            (#"(?i)\b[a-z][a-z0-9+.-]*://[^\r\n<>\"']+"#, "[URL redacted]"),
            (#"(?i)\b(?:https?|file):[^\r\n<>\"']+"#, "[URL redacted]"),
            // Credentials can also occur outside a URL in error descriptions.
            (#"(?i)\b(?:authorization|proxy-authorization)\s*[:=]\s*(?:(?:Bearer|Basic)\s+)?[^\r\n,;]+"#, "[authorization redacted]"),
            (#"(?i)\b(?:Bearer|Basic)\s+[a-z0-9+/=_.-]+"#, "[credential redacted]"),
            (#"(?i)\b(?:access[_-]?token|refresh[_-]?token|api[_-]?key|token|password|passwd|secret|credential|session(?:[_-]?id)?|cookie|set-cookie|signature|sig|username)[\"']?\s*[:=]\s*(?:\"[^\"]*\"|'[^']*'|[^\s,;&]+)"#, "[credential redacted]"),
            // Absolute Windows, UNC and POSIX paths. Unquoted paths may contain
            // spaces: favor redacting trailing prose over leaking a personal path.
            (#"(?i)(?<![a-z0-9])[a-z]:[\\/][^\r\n,;\)\]\"']*"#, "[path redacted]"),
            (#"\\\\[^\r\n,;\)\]\"']+"#, "[path redacted]"),
            (#"(?<![a-zA-Z0-9:/])/(?!/)[^\s/][^\r\n,;\)\]\"']*"#, "[path redacted]"),
            (#"\?[^\s<>\"']+"#, "[query redacted]"),
            (#"[\x00-\x1F\x7F]"#, " ")
        ]
        for (pattern, replacement) in replacements {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return bounded(text, bytes: limit)
    }

    private static func bounded(_ text: String, bytes limit: Int) -> String {
        guard text.utf8.count > limit else { return text }
        let suffix = " …[truncated]"
        let available = max(0, limit - suffix.utf8.count)
        var result = ""
        var count = 0
        for scalar in text.unicodeScalars {
            let size = String(scalar).utf8.count
            guard count + size <= available else { break }
            result.unicodeScalars.append(scalar)
            count += size
        }
        return result + suffix
    }

    private static func chunks(_ text: String, bytes limit: Int) -> [String] {
        var result: [String] = []
        var chunk = ""
        var count = 0
        for scalar in text.unicodeScalars {
            let size = String(scalar).utf8.count
            if count + size > limit {
                result.append(chunk)
                chunk = ""
                count = 0
            }
            chunk.unicodeScalars.append(scalar)
            count += size
        }
        if !chunk.isEmpty || result.isEmpty { result.append(chunk) }
        return result
    }
}
