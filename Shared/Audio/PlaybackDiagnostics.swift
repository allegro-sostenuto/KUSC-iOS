import Combine
import Foundation

/// The daily journal is always local and survives relaunches. An optional focused
/// capture still freezes its first failure before teardown, for compatibility.
@MainActor final class PlaybackDiagnostics: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var report = ""
    @Published private(set) var failureSummary: String?
    @Published private(set) var latestFailureSummary: String?
    @Published private(set) var historyStatus: PlaybackDebugJournal.Status?
    private var log = PlaybackDiagnosticLog()
    private let journal: PlaybackDebugJournal
    private var pendingHistory: Task<Void, Never>?
    private var captureStartedAt: Date?

    init(journal: PlaybackDebugJournal = .shared) { self.journal = journal }

    func start(context: String) {
        captureStartedAt = Date()
        event(category: "debug", name: "detailed_capture_started", details: ["context": context])
        log.start(context: context)
        failureSummary = nil
        refresh()
    }

    func record(_ event: String, includeHistory: Bool = true, generation: String? = nil) {
        if includeHistory {
            enqueue(.init(category: event.hasPrefix("schedule ") ? "scheduler" : "playback",
                          name: "diagnostic_event", generation: generation, details: ["message": event]))
        }
        guard log.isRecording else { return }
        log.record(event)
        refresh()
    }

    func event(category: String, name: String, scheduleID: String? = nil,
               generation: String? = nil, details: [String: String] = [:]) {
        enqueue(.init(category: category, name: name, scheduleID: scheduleID,
                      generation: generation, details: details))
        if log.isRecording {
            log.record("\(category).\(name) \(details.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
            refresh()
        }
    }

    func captureFailure(_ error: Error, origin: String, generation: String? = nil) {
        let message = "\(origin): \(PlaybackDiagnosticLog.sanitizedError(error))"
        latestFailureSummary = String(message.prefix(4_000))
        let value = error as NSError
        event(category: "error", name: "playback_failed", generation: generation,
              details: ["origin": origin, "domain": value.domain, "code": String(value.code),
                        "error": PlaybackDiagnosticLog.sanitizedError(error)])
        guard log.isRecording else { return }
        log.captureFailure(message)
        failureSummary = String(message.prefix(1500))
        refresh()
    }

    func stop() {
        event(category: "debug", name: "detailed_capture_stopped")
        log.stop()
        refresh()
    }

    func refreshHistory() async {
        await pendingHistory?.value
        historyStatus = await journal.status()
    }

    func makeHistoryReport() async throws -> URL {
        await pendingHistory?.value
        return try await journal.makeShareReport(focusedCapture: captureStartedAt == nil ? nil : report,
                                                captureDate: captureStartedAt)
    }

    func recentHistory() async throws -> String {
        await pendingHistory?.value
        return try await journal.recentText()
    }

    func clearHistory() async throws {
        await pendingHistory?.value
        try await journal.clear()
        log = PlaybackDiagnosticLog()
        captureStartedAt = nil
        failureSummary = nil
        latestFailureSummary = nil
        refresh()
        event(category: "debug", name: "history_cleared")
        await refreshHistory()
    }

    private func enqueue(_ event: PlaybackDebugJournal.Event) {
        let previous = pendingHistory, journal = journal
        pendingHistory = Task(priority: .utility) {
            await previous?.value
            await journal.record(event)
        }
    }

    private func refresh() {
        isRecording = log.isRecording
        report = log.report
    }
}
