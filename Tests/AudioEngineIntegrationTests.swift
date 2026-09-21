// These exercise AVFoundation ownership, so they run in the native KUSCTests
// target rather than the portable policy package. No station request is used.
#if DEBUG && canImport(AVFoundation) && !canImport(KUSCCore)
import AVFoundation
import Foundation
import XCTest
@testable import KUSC_SE

@MainActor final class AudioEngineIntegrationTests: XCTestCase {
    private let source = URL(string: "https://example.invalid/kusc-test.m3u8")!

    private func fixedSegments(origin: Date, filenamePrefix: String) -> [AudioSegment] {
        var result: [AudioSegment] = []
        for index in 0..<2 {
            let url: URL = URL(fileURLWithPath: "/nonexistent/\(filenamePrefix)-\(index).aac")
            let offset: TimeInterval = TimeInterval(index) * 10
            let start: Date = origin.addingTimeInterval(offset)
            let end: Date = start.addingTimeInterval(10)
            let segment: AudioSegment = AudioSegment(url: url, start: start, end: end, byteCount: 100)
            result.append(segment)
        }
        return result
    }

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

    func testLiveDuringBufferedToDirectSwitchDoesNotUseTheOutgoingQueue() async throws {
        let engine = RollingAudioEngine()
        defer { engine.stop() }
        var latest: EngineSnapshot?
        engine.onUpdate = { latest = $0 }
        try await engine.start(url: source, retentionMinutes: 5)
        engine.setRetention(minutes: 0)
        engine.goLive()
        XCTAssertEqual(latest?.hasAudio, false,
                       "The queued mode replacement owns the next live join; the outgoing queue must stay local-only")
    }

    func testLiveWhilePausedThenPlayPreservesThePendingLiveSeek() {
        let engine = RollingAudioEngine()
        defer { engine.stop() }
        var latest: EngineSnapshot?
        engine.onUpdate = { latest = $0 }
        let origin = Date(timeIntervalSince1970: 1_000_000)
        let files: [AudioSegment] = fixedSegments(origin: origin, filenamePrefix: "kusc-fixture")
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
        let files: [AudioSegment] = fixedSegments(origin: origin, filenamePrefix: "kusc-startup")
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

    func testEmptyRendererRefillsAlreadyDownloadedAudioWithoutAnotherArrival() async throws {
        // This fixture bypasses AppModel, which normally activates the output
        // session before preparing a renderer (including a paused seek).
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
        try AVAudioSession.sharedInstance().setActive(true)
        let engine = RollingAudioEngine()
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("kusc-refill-\(UUID().uuidString)")
        defer { engine.stop(); try? FileManager.default.removeItem(at: path) }
        var latest: EngineSnapshot?
        engine.onUpdate = { latest = $0 }
        let origin = Date(timeIntervalSince1970: 1_000_000)
        // Match the station's roughly ten-second storage segments. Seeking the
        // last third of a four-second finite clip leaves only 1.4 seconds for
        // native reliable-start preroll, conflating refill with input starvation.
        let fixture = try BufferedAudioTestFixture.make(in: path, duration: 30)
        var start = origin
        let files: [AudioSegment] = fixture.segments.enumerated().map { index, url -> AudioSegment in
            let end: Date = start.addingTimeInterval(fixture.segmentDurations[index])
            defer { start = end }
            return AudioSegment(url: url, start: start, end: end, byteCount: 100)
        }
        let consumedEnd = files[2].start
        engine.configureBufferedTransportForTesting(segments: files, pausedAt: consumedEnd)
        XCTAssertEqual(latest?.hasAudio, false)
        let ready = expectation(description: "Retained successor packets prepare without another download")
        var fulfilled = false
        var failure: Error?
        engine.onFailure = { error in
            failure = error
            if !fulfilled { fulfilled = true; ready.fulfill() }
        }
        engine.onUpdate = { snapshot in
            latest = snapshot
            if snapshot.isReady && !snapshot.isSeeking && !fulfilled {
                fulfilled = true
                ready.fulfill()
            }
        }
        engine.refillBufferedQueueForTesting()
        XCTAssertEqual(latest?.pendingSeekAt, consumedEnd)
        await fulfillment(of: [ready], timeout: 8)
        if let failure { throw failure }
        if latest?.isReady != true, let renderer = engine.bufferedTransportForTesting {
            print("Refill renderer seeking=\(renderer.isSeeking) hasAudio=\(renderer.hasAudio) " +
                  "statistics=\(renderer.statisticsForTesting) prepared=\(renderer.preparedMediaForTesting)")
        }
        XCTAssertEqual(latest?.isReady, true)
        XCTAssertEqual(latest?.hasAudio, true)
        XCTAssertEqual(latest?.heardAt, consumedEnd)
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

    func testPausedPendingSeekExpiryCanResumeAtRetainedAudioAndRejectLateRead() async throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
        try AVAudioSession.sharedInstance().setActive(true)
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("kusc-seek-expiry-\(UUID().uuidString)")
        let fixture = try BufferedAudioTestFixture.make(in: path, segmentCount: 2)
        let origin = Date(timeIntervalSince1970: 1_000_000)
        func files(start: Date, urls: [URL]) -> [AudioSegment] {
            var cursor = start
            return urls.enumerated().map { index, url -> AudioSegment in
                let end: Date = cursor.addingTimeInterval(fixture.segmentDurations[index])
                defer { cursor = end }
                return AudioSegment(url: url, start: cursor, end: end, byteCount: 100)
            }
        }
        let old = files(start: origin, urls: fixture.segments)
        let packets = try await BufferedAudioSampleSource.load(url: old[0].url)
        let engine = RollingAudioEngine()
        var release: CheckedContinuation<BufferedAudioSamples, Never>?
        defer {
            engine.stop()
            release?.resume(returning: packets)
            try? FileManager.default.removeItem(at: path)
        }
        var firstRead = true
        let readStarted = expectation(description: "Paused seek starts reading")
        var latest: EngineSnapshot?
        engine.onUpdate = { latest = $0 }
        engine.volume = 0.2
        engine.configureBufferedTransportForTesting(segments: old, pausedAt: origin.addingTimeInterval(0.1)) { url in
            if firstRead {
                firstRead = false
                return await withCheckedContinuation { release = $0; readStarted.fulfill() }
            }
            return try await BufferedAudioSampleSource.load(url: url)
        }
        engine.goLive()
        await fulfillment(of: [readStarted], timeout: 3)
        let freshURLs: [URL] = try fixture.segments.enumerated().map { index, url -> URL in
            let copy: URL = path.appendingPathComponent("fresh-\(index).aac")
            try FileManager.default.copyItem(at: url, to: copy)
            return copy
        }
        let fresh = files(start: origin.addingTimeInterval(1_000), urls: freshURLs)
        for segment in fresh { engine.acceptBufferedSegmentForTesting(segment) }
        if let pending = latest?.pendingSeekAt {
            XCTAssertGreaterThanOrEqual(pending, fresh[0].start,
                                       "A replacement seek may prepare retained media, but the expired target is revoked")
        }
        let playing = expectation(description: "Play resolves to the surviving retention window")
        var fulfilled = false
        engine.onUpdate = { snapshot in
            latest = snapshot
            if snapshot.isPlaying && !fulfilled { fulfilled = true; playing.fulfill() }
        }
        engine.play()
        // The obsolete task deliberately returns despite cancellation.
        let oldRead = release
        release = nil
        oldRead?.resume(returning: packets)
        await fulfillment(of: [playing], timeout: 8)
        XCTAssertEqual(latest?.isSeeking, false)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(latest?.heardAt), fresh[0].start)
        XCTAssertEqual(engine.bufferedTransportForTesting?.volume, 0.2)
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
