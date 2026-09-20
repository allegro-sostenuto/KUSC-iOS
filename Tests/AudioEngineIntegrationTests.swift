// These exercise AVFoundation ownership, so they run in the native KUSCTests
// target rather than the portable policy package. No station request is used.
#if DEBUG && canImport(AVFoundation) && !canImport(KUSCCore)
import Foundation
import XCTest
@testable import KUSC_SE

@MainActor final class AudioEngineIntegrationTests: XCTestCase {
    private let source = URL(string: "https://example.invalid/kusc-test.m3u8")!

    func testLiveBeforeBufferedMediaDoesNotInsertASecondRemotePlayerItem() async throws {
        let engine = RollingAudioEngine()
        defer { engine.stop() }
        var latest: EngineSnapshot?
        engine.onUpdate = { latest = $0 }
        try await engine.start(url: source, retentionMinutes: 5)
        engine.goLive()
        XCTAssertNil(latest?.window)
        XCTAssertEqual(latest?.hasAudio, false)
        XCTAssertEqual(latest?.playbackRequested, true)
        XCTAssertEqual(latest?.hasConfirmedPosition, false)
        engine.seek(to: Date()) // An unavailable scrub cannot create a player item either.
        XCTAssertEqual(latest?.hasAudio, false)
    }

    func testLiveWhilePausedThenPlayPreservesThePendingLiveSeek() {
        let engine = RollingAudioEngine()
        defer { engine.stop() }
        var latest: EngineSnapshot?
        engine.onUpdate = { latest = $0 }
        let origin = Date(timeIntervalSince1970: 1_000_000)
        let files = (0..<2).map { index in
            AudioSegment(url: URL(fileURLWithPath: "/nonexistent/kusc-fixture-\(index).aac"),
                         start: origin.addingTimeInterval(Double(index * 10)),
                         end: origin.addingTimeInterval(Double((index + 1) * 10)), byteCount: 100)
        }
        engine.configureBufferedTransportForTesting(segments: files, pausedAt: origin.addingTimeInterval(1))
        engine.goLive()
        let live = latest?.pendingSeekAt
        XCTAssertNotNil(live)
        XCTAssertGreaterThan(live!.timeIntervalSince(origin), 5)
        engine.play()
        XCTAssertEqual(latest?.pendingSeekAt, live)
        XCTAssertEqual(latest?.isSeeking, true)
        // Pending media must not overwrite the last actual heard timestamp.
        XCTAssertEqual(latest?.heardAt, origin.addingTimeInterval(1))
    }

    func testStartupAnchorsLiveOnlyAfterBothInitialSegmentsArrive() {
        let engine = RollingAudioEngine()
        defer { engine.stop() }
        var latest: EngineSnapshot?
        engine.onUpdate = { latest = $0 }
        let origin = Date(timeIntervalSince1970: 1_000_000)
        let files = (0..<2).map { index in
            AudioSegment(url: URL(fileURLWithPath: "/nonexistent/kusc-startup-\(index).aac"),
                         start: origin.addingTimeInterval(Double(index * 10)),
                         end: origin.addingTimeInterval(Double((index + 1) * 10)), byteCount: 100)
        }
        engine.configureBufferedTransportForTesting(segments: [], pausedAt: nil, initialJoinPending: true)
        engine.acceptBufferedSegmentForTesting(files[0])
        XCTAssertNil(latest?.window)
        XCTAssertNil(latest?.pendingSeekAt)
        XCTAssertEqual(latest?.hasAudio, false)
        engine.goLive() // A first-file Live tap must retain the two-file join rule.
        XCTAssertEqual(latest?.hasAudio, false)
        engine.acceptBufferedSegmentForTesting(files[1])
        XCTAssertNotNil(latest?.pendingSeekAt)
        XCTAssertEqual(latest!.pendingSeekAt!.timeIntervalSince(origin), 6, accuracy: 0.05)
        XCTAssertEqual(latest?.hasConfirmedPosition, false)
    }

    func testPauseBeforeRetentionSwitchKeepsReplacementPlaybackPaused() async throws {
        let engine = RollingAudioEngine()
        defer { engine.stop() }
        try await engine.start(url: source, retentionMinutes: 0)
        engine.setRetention(minutes: 5)
        engine.pause()
        let replacement = expectation(description: "Paused retention replacement publishes")
        var requests: [Bool] = []
        var observedReplacement = false
        engine.onUpdate = { snapshot in
            requests.append(snapshot.playbackRequested)
            if !snapshot.hasAudio && !observedReplacement {
                observedReplacement = true
                replacement.fulfill()
            }
        }
        await fulfillment(of: [replacement], timeout: 2)
        XCTAssertFalse(requests.isEmpty)
        XCTAssertTrue(requests.allSatisfy { !$0 }, "A queued retention change must not override Pause")
    }

    func testRapidRetentionReversalWhilePausedDoesNotRestartPlayback() async throws {
        let engine = RollingAudioEngine()
        defer { engine.stop() }
        try await engine.start(url: source, retentionMinutes: 0, playbackRequested: false)
        let originalSession = engine.transportSessionForTesting
        engine.setRetention(minutes: 5)
        engine.setRetention(minutes: 0)
        let replacement = expectation(description: "Latest direct-mode replacement publishes")
        var requests: [Bool] = []
        var observedReplacement = false
        engine.onUpdate = { [weak engine] snapshot in
            requests.append(snapshot.playbackRequested)
            if engine?.transportSessionForTesting != originalSession && snapshot.hasAudio && !observedReplacement {
                observedReplacement = true
                replacement.fulfill()
            }
        }
        await fulfillment(of: [replacement], timeout: 2)
        XCTAssertFalse(requests.isEmpty)
        XCTAssertTrue(requests.allSatisfy { !$0 })
    }
}
#endif
