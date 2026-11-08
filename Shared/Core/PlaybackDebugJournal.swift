import Foundation

/// Adapts the user's recovered Work-mode diagnostics actor to the existing app.
/// Independent of focused captures: failures and relaunches do not erase history.
actor PlaybackDebugJournal {
    static let shared = PlaybackDebugJournal()
    nonisolated static let sessionID = UUID().uuidString
    static let retention: TimeInterval = 24 * 60 * 60

    struct Event: Codable, Sendable {
        let timestamp: String
        let monotonicNanoseconds: UInt64
        let category: String
        let name: String
        let sessionID: String?
        let scheduleID: String?
        let generation: String?
        let details: [String: String]

        init(date: Date = Date(), monotonicNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds,
             category: String, name: String, sessionID: String? = PlaybackDebugJournal.sessionID,
             scheduleID: String? = nil, generation: String? = nil, details: [String: String] = [:]) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            timestamp = formatter.string(from: date)
            self.monotonicNanoseconds = monotonicNanoseconds
            self.category = PlaybackDiagnosticLog.sanitizedText(category, limit: 64)
            self.name = PlaybackDiagnosticLog.sanitizedText(name, limit: 96)
            self.sessionID = sessionID.map { PlaybackDiagnosticLog.sanitizedText($0, limit: 128) }
            self.scheduleID = scheduleID.map { PlaybackDiagnosticLog.sanitizedText($0, limit: 128) }
            self.generation = generation.map { PlaybackDiagnosticLog.sanitizedText($0, limit: 128) }
            let forbidden = ["url", "token", "password", "credential", "serial", "account", "email", "cookie", "authorization"]
            self.details = details.sorted { $0.key < $1.key }.prefix(16).reduce(into: [:]) { result, pair in
                guard !forbidden.contains(where: pair.key.lowercased().contains) else { return }
                result[PlaybackDiagnosticLog.sanitizedText(pair.key, limit: 64)] =
                    PlaybackDiagnosticLog.sanitizedText(pair.value, limit: pair.key == "error" ? 4_000 : 1_000)
            }
        }

        var date: Date? {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp)
        }
    }

    struct Status: Sendable {
        let eventCount: Int
        let bytes: Int
        let oldest: Date?
        let discardedForBounds: Int
        let invalidLines: Int
        let storageError: String?
    }

    private struct Segment {
        let url: URL
        let hour: Int
        let part: Int
        var bytes: Int
        var count: Int
        var oldest: Date?
    }

    private let directory: URL
    private let reportDirectory: URL
    private let maximumBytes: Int
    private let maximumEvents: Int
    private let segmentBytes: Int
    private let encoder = JSONEncoder()
    private var segments: [Segment] = []
    private var loaded = false
    private var lastPrune = Date.distantPast
    private var activeURL: URL?
    private var discardedForBounds = 0
    private var invalidLines = 0
    private var storageError: String?
    private var clearedBefore = Date.distantPast
    private var clearedUptime: UInt64 = 0

    init(directory: URL? = nil, reportDirectory: URL? = nil,
         maximumBytes: Int = 64 * 1024 * 1024, maximumEvents: Int = 100_000) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.directory = directory ?? support.appendingPathComponent("Philharmonic/Debug", isDirectory: true)
        self.reportDirectory = reportDirectory ?? FileManager.default.temporaryDirectory.appendingPathComponent("PhilharmonicDebugReports", isDirectory: true)
        self.maximumBytes = max(4_096, maximumBytes)
        self.maximumEvents = max(1, maximumEvents)
        segmentBytes = min(256 * 1024, max(1_024, maximumBytes / 4))
        encoder.outputFormatting = [.sortedKeys]
    }

    /// For platform callbacks that do not own the observable diagnostics facade.
    nonisolated static func emit(category: String, name: String, scheduleID: String? = nil,
                                 generation: String? = nil, details: [String: String] = [:]) {
        let event = Event(category: category, name: name, scheduleID: scheduleID,
                          generation: generation, details: details)
        Task(priority: .utility) { await shared.record(event) }
    }

    func record(_ event: Event, now: Date = Date()) {
        do {
            try load()
            try prune(now: now, force: false)
            guard let date = event.date, date >= now.addingTimeInterval(-Self.retention), date >= clearedBefore,
                  event.sessionID != Self.sessionID || event.monotonicNanoseconds >= clearedUptime else { return }
            var line = try encoder.encode(event)
            line.append(0x0A)
            let hour = Int(floor(date.timeIntervalSince1970 / 3_600))
            var index = activeURL.flatMap { url in segments.firstIndex { $0.url == url } }
            if index == nil || segments[index!].hour != hour || segments[index!].bytes + line.count > segmentBytes
                || segments[index!].count >= max(1, maximumEvents / 4) {
                var part = (segments.filter { $0.hour == hour }.map(\.part).max() ?? -1) + 1
                var url = directory.appendingPathComponent("events-\(hour)-\(part).jsonl")
                while FileManager.default.fileExists(atPath: url.path) {
                    part += 1; url = directory.appendingPathComponent("events-\(hour)-\(part).jsonl")
                }
                guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try protect(url)
                segments.append(.init(url: url, hour: hour, part: part, bytes: 0, count: 0, oldest: date))
                segments.sort { ($0.hour, $0.part) < ($1.hour, $1.part) }
                activeURL = url
                index = segments.firstIndex { $0.url == url }
            }
            guard let index else { return }
            let handle = try FileHandle(forWritingTo: segments[index].url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            segments[index].bytes += line.count
            segments[index].count += 1
            try enforceBounds()
        } catch {
            activeURL = nil // A subsequent append never joins a partially written line.
            storageError = PlaybackDiagnosticLog.sanitizedError(error)
        }
    }

    func status(now: Date = Date()) -> Status {
        do { try load(); try prune(now: now, force: true) }
        catch { storageError = PlaybackDiagnosticLog.sanitizedError(error) }
        return .init(eventCount: segments.reduce(0) { $0 + $1.count },
                     bytes: segments.reduce(0) { $0 + $1.bytes }, oldest: segments.compactMap(\.oldest).min(),
                     discardedForBounds: discardedForBounds, invalidLines: invalidLines, storageError: storageError)
    }

    /// A separate immutable JSONL file; later recording/clearing cannot alter a share.
    func makeShareReport(now: Date = Date(), focusedCapture: String? = nil, captureDate: Date? = nil) throws -> URL {
        try load()
        try prune(now: now, force: true)
        try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)
        for old in try FileManager.default.contentsOfDirectory(at: reportDirectory, includingPropertiesForKeys: nil) {
            let parts = old.deletingPathExtension().lastPathComponent.split(separator: "-")
            if old.lastPathComponent.hasPrefix("philharmonic-debug-"), old.pathExtension == "jsonl",
               parts.count > 3, let seconds = TimeInterval(parts[2]), now.timeIntervalSince1970 - seconds > Self.retention {
                try? FileManager.default.removeItem(at: old)
            }
        }
        let destination = reportDirectory.appendingPathComponent("philharmonic-debug-\(Int(now.timeIntervalSince1970))-\(UUID().uuidString).jsonl")
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        try protect(destination)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        let header = Event(date: now, category: "debug", name: "report_created", details: [
            "window_hours": "24", "discarded_for_storage_bounds": String(discardedForBounds),
            "invalid_lines_skipped": String(invalidLines), "storage_error": storageError ?? "none"])
        var heading = try encoder.encode(header); heading.append(0x0A)
        try handle.write(contentsOf: heading)
        for segment in segments {
            for line in try validLines(in: segment.url, after: now.addingTimeInterval(-Self.retention)) {
                var row = line; row.append(0x0A)
                try handle.write(contentsOf: row)
            }
        }
        if let focusedCapture, let captureDate, captureDate >= now.addingTimeInterval(-Self.retention) {
            for line in focusedCapture.components(separatedBy: "\n") where !line.isEmpty {
                var row = try encoder.encode(Event(date: captureDate, category: "focused_capture", name: "captured_line",
                                                   details: ["message": line]))
                row.append(0x0A); try handle.write(contentsOf: row)
            }
        }
        return destination
    }

    func recentText(now: Date = Date(), maximumBytes: Int = 64 * 1024) throws -> String {
        try load(); try prune(now: now, force: true)
        var rows: [Data] = [], retainedBytes = 0
        outer: for segment in segments.reversed() {
            for line in try validLines(in: segment.url, after: now.addingTimeInterval(-Self.retention)).reversed() {
                guard retainedBytes + line.count + 1 <= maximumBytes else { break outer }
                rows.append(line); retainedBytes += line.count + 1
            }
        }
        return rows.reversed().map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n")
    }

    func clear(now: Date = Date()) throws {
        try load()
        for segment in segments { try FileManager.default.removeItem(at: segment.url) }
        segments = []; activeURL = nil; invalidLines = 0; discardedForBounds = 0; storageError = nil
        clearedBefore = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 * 1_000) / 1_000)
        clearedUptime = DispatchTime.now().uptimeNanoseconds
    }

    private func load() throws {
        guard !loaded else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try protect(directory)
        var found: [Segment] = []
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            let parts = url.deletingPathExtension().lastPathComponent.split(separator: "-")
            guard values.isRegularFile == true, values.isSymbolicLink != true, url.pathExtension == "jsonl",
                  parts.count == 3, parts[0] == "events", let hour = Int(parts[1]), let part = Int(parts[2]) else { continue }
            let rows = try validLines(in: url, after: .distantPast)
            let bytes = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            let oldest = rows.first.flatMap { try? JSONDecoder().decode(Event.self, from: $0).date }
            found.append(.init(url: url, hour: hour, part: part, bytes: bytes, count: rows.count, oldest: oldest))
        }
        segments = found.sorted { ($0.hour, $0.part) < ($1.hour, $1.part) }
        loaded = true
    }

    private func prune(now: Date, force: Bool) throws {
        guard force || now.timeIntervalSince(lastPrune) >= 300 || now < lastPrune else { return }
        let cutoff = now.addingTimeInterval(-Self.retention)
        var kept: [Segment] = []
        for var segment in segments {
            if TimeInterval((segment.hour + 1) * 3_600) <= cutoff.timeIntervalSince1970 {
                try FileManager.default.removeItem(at: segment.url)
                if activeURL == segment.url { activeURL = nil }
                continue
            }
            if segment.oldest.map({ $0 < cutoff }) == true {
                let rows = try validLines(in: segment.url, after: cutoff)
                var data = Data()
                for row in rows { data.append(row); data.append(0x0A) }
                try data.write(to: segment.url, options: .atomic)
                try protect(segment.url)
                segment.bytes = data.count; segment.count = rows.count
                segment.oldest = rows.first.flatMap { try? JSONDecoder().decode(Event.self, from: $0).date }
            }
            kept.append(segment)
        }
        segments = kept; lastPrune = now
        try enforceBounds()
    }

    private func enforceBounds() throws {
        var bytes = segments.reduce(0) { $0 + $1.bytes }
        var events = segments.reduce(0) { $0 + $1.count }
        while (bytes > maximumBytes || events > maximumEvents), !segments.isEmpty {
            let oldest = segments.removeFirst()
            try FileManager.default.removeItem(at: oldest.url)
            bytes -= oldest.bytes; events -= oldest.count; discardedForBounds += oldest.count
            if activeURL == oldest.url { activeURL = nil }
        }
    }

    private func validLines(in url: URL, after cutoff: Date) throws -> [Data] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        // Owned segments are small. Reject corrupt oversized input instead of
        // loading an unbounded file into an app that is playing audio.
        let data = try handle.read(upToCount: max(segmentBytes * 2, 64 * 1024)) ?? Data()
        guard (try handle.read(upToCount: 1) ?? Data()).isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        return data.split(separator: 0x0A).compactMap { line in
            guard line.count <= 64 * 1024, let event = try? JSONDecoder().decode(Event.self, from: Data(line)),
                  let date = event.date else { invalidLines += 1; return nil }
            return date >= cutoff ? Data(line) : nil
        }
    }

    private func protect(_ url: URL) throws {
        var target = url
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try target.setResourceValues(values)
        #if os(iOS)
        // Scheduled playback can continue while locked after the first unlock.
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }
}
