#if canImport(UIKit) && !canImport(KUSCCore) && DEBUG
import XCTest
@testable import KUSC_SE

final class PlaybackDiagnosticsIntegrationTests: XCTestCase {
    @MainActor func testFirstFailureSurvivesImmediatePausedEngineTeardown() {
        let engine = RollingAudioEngine()
        defer { engine.stop() }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let segments = (0..<2).map { index in
            AudioSegment(url: URL(fileURLWithPath: "/diagnostic-fixture-\(index).aac"),
                         start: start.addingTimeInterval(Double(index * 10)),
                         end: start.addingTimeInterval(Double((index + 1) * 10)), byteCount: 100)
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

    @MainActor func testPausedModelFailureKeepsReportAndExplainsStoppedCollection() {
        let model = AppModel.shared
        model.configurePausedDiagnosticFailureForTesting()
        XCTAssertFalse(model.isPlaying)
        XCTAssertNil(model.bufferWindow)
        XCTAssertEqual(model.statusText, "Paused")
        XCTAssertEqual(model.bufferFailureMessage, "Rewind stopped after an audio error. Tap Play to reconnect.")
        XCTAssertNotNil(model.diagnostics.failureSummary)
        XCTAssertTrue(model.diagnostics.report.contains("retained=2"))
    }
}
#endif
