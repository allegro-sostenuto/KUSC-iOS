#if canImport(UIKit) && !canImport(PhilharmonicCore) && DEBUG
import XCTest
@testable import Philharmonic_SE

final class PlaybackDiagnosticsIntegrationTests: XCTestCase {
    @MainActor func testDailyHistoryContinuesAfterFocusedFailureAndSurvivesReopening() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("philharmonic-debug-integration-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("log")
        let journal = PlaybackDebugJournal(directory: directory, reportDirectory: root.appendingPathComponent("reports"))
        let diagnostics = PlaybackDiagnostics(journal: journal)
        diagnostics.start(context: "isolated journal test")
        diagnostics.record("before failure")
        diagnostics.captureFailure(NSError(domain: "NSURLErrorDomain", code: -1001), origin: "test.connection")
        let frozen = diagnostics.report
        diagnostics.record("after-failure-retry")
        _ = try await diagnostics.makeHistoryReport()
        XCTAssertEqual(diagnostics.report, frozen)
        XCTAssertFalse(diagnostics.isRecording)
        let reopened = PlaybackDebugJournal(directory: directory, reportDirectory: root.appendingPathComponent("reports"))
        let report = try await reopened.makeShareReport()
        let text = try String(contentsOf: report, encoding: .utf8)
        XCTAssertTrue(text.contains("after-failure-retry"))
        XCTAssertTrue(text.contains("playback_failed"))
        XCTAssertTrue(text.contains("-1001"))
    }

    @MainActor func testFirstFailureSurvivesImmediatePausedEngineTeardown() {
        let engine = RollingAudioEngine()
        defer { engine.stop() }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let segments: [AudioSegment] = (0..<2).map { (index: Int) -> AudioSegment in
            let url = URL(fileURLWithPath: "/diagnostic-fixture-\(index).aac")
            let segmentStart = start.addingTimeInterval(TimeInterval(index) * 10)
            let segmentEnd = segmentStart.addingTimeInterval(10)
            return AudioSegment(url: url, start: segmentStart, end: segmentEnd, byteCount: 100)
        }
        engine.configureBufferedTransportForTesting(segments: segments, pausedAt: start.addingTimeInterval(4))
        engine.diagnostics.start(context: "paused buffer regression")
        var latest: EngineSnapshot?
        engine.onUpdate = { latest = $0 }
        engine.onFailure = { [weak engine] _ in engine?.stop() }
        engine.failForDiagnosticsTesting(NSError(domain: "NSURLErrorDomain", code: -1001,
            userInfo: [NSLocalizedDescriptionKey: "The request timed out."]))
        let report = engine.diagnostics.report
        XCTAssertTrue(report.contains("requested=false"))
        XCTAssertTrue(report.contains("retained=2"), "Evidence must precede teardown that removes these segments")
        XCTAssertTrue(report.contains("NSURLErrorDomain"))
        XCTAssertTrue(report.contains("-1001"))
        XCTAssertNil(latest?.window)
        XCTAssertFalse(engine.diagnostics.isRecording)
        engine.failForDiagnosticsTesting(AudioStreamError.disconnected)
        XCTAssertEqual(engine.diagnostics.report, report, "A later retry failure cannot replace the first failure")
    }

    @MainActor func testPausedModelFailureKeepsReportWithoutOfferingRewind() {
        let model = AppModel.shared
        model.configurePausedDiagnosticFailureForTesting()
        XCTAssertFalse(model.isPlaying)
        XCTAssertNil(model.bufferWindow)
        XCTAssertEqual(model.statusText, "Paused")
        XCTAssertNil(model.bufferFailureMessage)
        XCTAssertFalse(model.canSeek(to: Date()))
        XCTAssertNotNil(model.diagnostics.failureSummary)
        XCTAssertTrue(model.diagnostics.report.contains("retained=2"))
    }
}
#endif
