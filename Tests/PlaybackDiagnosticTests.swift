import Foundation
import XCTest
#if canImport(KUSCCore)
@testable import KUSCCore
#else
@testable import KUSC_SE
#endif

final class PlaybackDiagnosticTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_700_000_000)

    func testRecordingRequiresExplicitStartAndStopRetainsEvidence() {
        var log = PlaybackDiagnosticLog()
        log.record("not opted in")
        log.captureFailure("not opted in either")
        XCTAssertFalse(log.isRecording)
        XCTAssertFalse(log.hasFailure)
        XCTAssertFalse(log.report.contains("not opted in"))
        log.start(context: "retention=5", date: origin, uptime: 100)
        log.record("ready", date: origin.addingTimeInterval(2), uptime: 102)
        log.stop()
        let stopped = log.report
        log.record("after stop")
        log.captureFailure("after stop")
        XCTAssertEqual(log.report, stopped)
        XCTAssertTrue(stopped.contains("ready"))
        XCTAssertTrue(stopped.contains("Recording stopped."))
        XCTAssertFalse(log.hasFailure)
    }

    func testFirstFailureFreezesPriorEventsAndCannotBeOverwrittenByRetries() {
        var log = PlaybackDiagnosticLog()
        log.start(context: "buffer=15", date: origin, uptime: 100)
        log.record("download began", date: origin, uptime: 100)
        log.record("player waiting", date: origin.addingTimeInterval(1), uptime: 101)
        log.captureFailure("original decoder failure", date: origin.addingTimeInterval(2), uptime: 102)
        let frozen = log.report
        for _ in 0..<300 { log.record("retry event"); log.captureFailure("later timeout") }
        log.stop()
        XCTAssertFalse(log.isRecording)
        XCTAssertTrue(log.hasFailure)
        XCTAssertEqual(log.report, frozen)
        XCTAssertTrue(frozen.contains("download began"))
        XCTAssertTrue(frozen.contains("player waiting"))
        XCTAssertTrue(frozen.contains("FAILURE: original decoder failure"))
        XCTAssertFalse(frozen.contains("later timeout"))
    }

    func testFreshStartClearsFailureHistoryAndUsesNewMonotonicOrigin() {
        var log = PlaybackDiagnosticLog()
        log.start(context: "old context", date: origin, uptime: 100)
        log.captureFailure("old failure", date: origin, uptime: 101)
        log.start(context: "new context", date: origin.addingTimeInterval(10), uptime: 500)
        log.record("fresh event", date: origin.addingTimeInterval(12), uptime: 502.25)
        XCTAssertTrue(log.isRecording)
        XCTAssertFalse(log.hasFailure)
        XCTAssertFalse(log.report.contains("old context"))
        XCTAssertFalse(log.report.contains("old failure"))
        XCTAssertTrue(log.report.contains("new context"))
        XCTAssertTrue(log.report.contains("uptime=502.250 | elapsed=+2.250s"))
    }

    func testWallClockChangeCannotRewriteMonotonicElapsedTime() {
        var log = PlaybackDiagnosticLog()
        log.start(context: "clock adjustment", date: origin, uptime: 100)
        log.record("wall clock moved back", date: origin.addingTimeInterval(-3_600), uptime: 112.5)
        XCTAssertTrue(log.report.contains("elapsed=+12.500s"))
        XCTAssertTrue(log.report.contains("2023-11-14T21:13:20.000Z"))
        log.record("invalid clock input", date: origin, uptime: .nan)
        XCTAssertTrue(log.report.contains("uptime=unavailable | elapsed=unavailable"))
    }

    func testUnicodeRingAndContextStayBelowStorageBudget() {
        var log = PlaybackDiagnosticLog()
        log.start(context: String(repeating: "🎻", count: 10_000), date: origin, uptime: 0)
        for number in 0..<400 {
            log.record("entry-\(number): " + String(repeating: "🎻", count: 900), date: origin, uptime: Double(number))
        }
        let lines = log.report.components(separatedBy: "\n").filter { $0.contains(" | uptime=") }
        XCTAssertEqual(lines.count, 256)
        XCTAssertFalse(log.report.contains("entry-143:"))
        XCTAssertTrue(log.report.contains("entry-144:"))
        XCTAssertTrue(log.report.contains("entry-399:"))
        XCTAssertTrue(lines.allSatisfy { $0.utf8.count <= 1_000 && $0.count <= 1_000 })
        XCTAssertLessThan(log.report.utf8.count, 300 * 1_024)
        XCTAssertFalse(log.report.contains("�"))
    }

    func testFailureStillFitsAFullRingWithoutLosingImmediateContext() {
        var log = PlaybackDiagnosticLog()
        log.start(context: "full ring", date: origin, uptime: 0)
        for number in 0..<256 { log.record("entry-\(number): player", date: origin, uptime: Double(number)) }
        log.captureFailure("decoder stopped", date: origin, uptime: 256)
        XCTAssertFalse(log.report.contains("entry-0:"))
        XCTAssertTrue(log.report.contains("entry-1:"))
        XCTAssertTrue(log.report.contains("entry-255:"))
        XCTAssertTrue(log.report.contains("FAILURE: decoder stopped"))
        XCTAssertEqual(log.report.components(separatedBy: "\n").filter { $0.contains(" | uptime=") }.count, 256)
    }

    func testContextEventsAndFailureAllRedactURLsPathsAndCredentials() {
        var log = PlaybackDiagnosticLog()
        log.start(context: "source=https://alice:password@example.invalid/private?session=super-secret", date: origin, uptime: 0)
        log.record(#"file="C:\Users\Private Person\Downloads\private-audio.aac""#, date: origin, uptime: 1)
        log.record(#"source="file:///Users/private%20person/private-audio.aac""#, date: origin, uptime: 2)
        log.record(#"path="/var/mobile/Containers/personal-id/file.aac""#, date: origin, uptime: 3)
        log.record(#"share="\\private-server\users\private-name\track.aac""#, date: origin, uptime: 4)
        log.record(#"{"password":"json-secret","access_token":"token-secret"}"#, date: origin, uptime: 5)
        log.captureFailure("Authorization: Bearer private-credential\nrequest failed", date: origin, uptime: 6)
        for secret in ["alice", "example.invalid", "super-secret", "Private Person", "private-audio",
                       "private person", "personal-id", "private-server", "private-name", "json-secret",
                       "token-secret", "private-credential"] {
            XCTAssertFalse(log.report.contains(secret), "Leaked \(secret)")
        }
        XCTAssertTrue(log.report.contains("[URL redacted]"))
        XCTAssertTrue(log.report.contains("[path redacted]"))
        XCTAssertTrue(log.report.contains("[credential redacted]"))
        XCTAssertTrue(log.report.contains("request failed"))
    }

    func testPercentEncodedURLAndBareQueryAreRedacted() {
        var log = PlaybackDiagnosticLog()
        log.start(context: "encoded request", date: origin, uptime: 0)
        log.record("https%253A%252F%252Fhidden.invalid%252Fsession%253Ftoken%253Dencoded-secret", date: origin, uptime: 1)
        log.record("request ?unknown-key=bare-query-secret", date: origin, uptime: 2)
        log.record("https%3A%2F%2Fhidden.invalid%2Fstream%3Ftoken%3Dinvalid-escape-secret%zz", date: origin, uptime: 3)
        XCTAssertFalse(log.report.contains("hidden.invalid"))
        XCTAssertFalse(log.report.contains("encoded-secret"))
        XCTAssertFalse(log.report.contains("bare-query-secret"))
        XCTAssertFalse(log.report.contains("invalid-escape-secret"))
    }

    func testErrorSummaryKeepsDomainCodeAndCauseWithoutSerializingUserInfo() {
        let underlying = NSError(domain: "NSOSStatusErrorDomain", code: -12_839,
                                 userInfo: [NSLocalizedDescriptionKey: "Decoder rejected media"])
        let error = NSError(domain: "AVFoundationErrorDomain", code: -11_800, userInfo: [
            NSLocalizedDescriptionKey: "Cannot open https://private.invalid/live?session=secret-value",
            NSUnderlyingErrorKey: underlying,
            "UnrelatedSensitiveValue": "must-never-appear",
            NSFilePathErrorKey: "/Users/private-name/recording.aac"
        ])
        let result = PlaybackDiagnosticLog.sanitizedError(error)
        XCTAssertTrue(result.contains("AVFoundationErrorDomain (code -11800)"))
        XCTAssertTrue(result.contains("NSOSStatusErrorDomain (code -12839): Decoder rejected media"))
        XCTAssertTrue(result.contains("Cannot open [URL redacted]"))
        for secret in ["private.invalid", "secret-value", "must-never-appear", "private-name"] {
            XCTAssertFalse(result.contains(secret))
        }
    }

    func testUnderlyingErrorsAreBoundedAndCyclesTerminate() {
        var error = NSError(domain: "Level5", code: 5, userInfo: [NSLocalizedDescriptionKey: "deepest"])
        for level in (0..<5).reversed() {
            error = NSError(domain: "Level\(level)", code: level,
                            userInfo: [NSLocalizedDescriptionKey: "cause", NSUnderlyingErrorKey: error])
        }
        let bounded = PlaybackDiagnosticLog.sanitizedError(error)
        XCTAssertTrue(bounded.contains("Level0"))
        XCTAssertTrue(bounded.contains("Level3"))
        XCTAssertFalse(bounded.contains("Level4"))
        XCTAssertTrue(bounded.contains("chain truncated"))
        let cycle = CyclicDiagnosticError(domain: "CycleError", code: 7, userInfo: nil)
        let cyclic = PlaybackDiagnosticLog.sanitizedError(cycle)
        XCTAssertTrue(cyclic.contains("CycleError (code 7)"))
        XCTAssertTrue(cyclic.contains("underlying error cycle"))
        XCTAssertLessThan(cyclic.count, 300)
    }

    func testLongOuterErrorsCannotDiscardTheDeepestIncludedCodeFromCapturedFailure() {
        var error = NSError(domain: "DeepDecoderDomain", code: -12_839,
                            userInfo: [NSLocalizedDescriptionKey: "deep decoder evidence"])
        for level in (0..<3).reversed() {
            error = NSError(domain: "OuterError\(level)", code: -11_800 - level, userInfo: [
                NSLocalizedDescriptionKey: String(repeating: "Verbose outer description. ", count: 100),
                NSUnderlyingErrorKey: error
            ])
        }
        var log = PlaybackDiagnosticLog()
        log.start(context: "long error chain", date: origin, uptime: 100)
        for number in 0..<256 { log.record("before-failure-\(number)", date: origin, uptime: 101) }
        log.captureFailure(PlaybackDiagnosticLog.sanitizedError(error), date: origin, uptime: 102)
        let frozen = log.report
        XCTAssertTrue(frozen.contains("OuterError0 (code -11800)"))
        XCTAssertTrue(frozen.contains("DeepDecoderDomain (code -12839): deep decoder evidence"))
        XCTAssertTrue(frozen.contains("FAILURE continuation"))
        XCTAssertTrue(frozen.contains("before-failure-255"))
        let lines = frozen.components(separatedBy: "\n").filter { $0.contains(" | uptime=") }
        XCTAssertEqual(lines.count, 256)
        XCTAssertTrue(lines.allSatisfy { $0.utf8.count <= 1_000 })
        XCTAssertLessThan(frozen.utf8.count, 300 * 1_024)
        log.captureFailure("later failure")
        log.record("retry")
        log.stop()
        XCTAssertEqual(log.report, frozen)
    }

    func testLongUnicodeFailureRetainsTheWholeBoundedMessageAcrossContinuations() {
        let message = String(repeating: "🎻", count: 900) + " deepest-code=-12839"
        var log = PlaybackDiagnosticLog()
        log.start(context: "unicode failure", date: origin, uptime: 100)
        log.captureFailure(message, date: origin, uptime: 101)
        let lines = log.report.components(separatedBy: "\n").filter { $0.contains(" | uptime=") }
        XCTAssertGreaterThan(lines.count, 1)
        XCTAssertTrue(lines.allSatisfy { $0.utf8.count <= 1_000 })
        XCTAssertEqual(log.report.filter { $0 == "🎻" }.count, 900)
        XCTAssertTrue(log.report.contains("deepest-code=-12839"))
        XCTAssertFalse(log.report.contains("�"))
        XCTAssertLessThan(log.report.utf8.count, 300 * 1_024)
    }
}

private final class CyclicDiagnosticError: NSError, @unchecked Sendable {
    override var userInfo: [String: Any] {
        [NSLocalizedDescriptionKey: "cyclic error", NSUnderlyingErrorKey: self]
    }
}
