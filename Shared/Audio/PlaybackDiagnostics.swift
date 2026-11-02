import Combine
import Foundation

/// Explicitly started, local-only diagnostics available in the sideloaded Release
/// build. A failure freezes the evidence before playback teardown or retries.
@MainActor final class PlaybackDiagnostics: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var report = ""
    @Published private(set) var failureSummary: String?
    private var log = PlaybackDiagnosticLog()

    func start(context: String) {
        log.start(context: context)
        failureSummary = nil
        refresh()
    }

    func record(_ event: String) {
        guard log.isRecording else { return }
        log.record(event)
        refresh()
    }

    func captureFailure(_ error: Error, origin: String) {
        guard log.isRecording else { return }
        let message = "\(origin): \(PlaybackDiagnosticLog.sanitizedError(error))"
        log.captureFailure(message)
        failureSummary = String(message.prefix(1500))
        refresh()
    }

    func stop() {
        log.stop()
        refresh()
    }

    private func refresh() {
        isRecording = log.isRecording
        report = log.report
    }
}
