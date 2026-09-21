#if DEBUG && canImport(AVFoundation) && !canImport(KUSCCore)
import AVFoundation
import Foundation
import XCTest
@testable import KUSC_SE

@MainActor final class BufferedAudioRendererTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_789_900_000)
    private var rendererFailure: Error?
    private weak var observedRenderer: BufferedAudioRenderer?

    private func observeFailures(from renderer: BufferedAudioRenderer) {
        rendererFailure = nil
        observedRenderer = renderer
        renderer.onFailure = { [weak self] in self?.rendererFailure = $0 }
    }

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("kusc-renderer-\(UUID().uuidString)", isDirectory: true)
    }

    private func segments(_ files: BufferedAudioTestFixture.Files) -> [AudioSegment] {
        var start = origin
        return files.segments.enumerated().map { index, url -> AudioSegment in
            let end: Date = start.addingTimeInterval(files.segmentDurations[index])
            defer { start = end }
            return AudioSegment(url: url, start: start, end: end, byteCount: 1_000)
        }
    }

    private func activateAudio() throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
        try AVAudioSession.sharedInstance().setActive(true)
    }

    private func waitUntil(_ description: String, timeout: TimeInterval = 8,
                           condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), rendererFailure == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        if let rendererFailure {
            XCTFail("\(description): \(rendererFailure as NSError)")
            throw rendererFailure
        }
        guard condition() else {
            let state = observedRenderer.map {
                "seeking=\($0.isSeeking) playing=\($0.isPlaying) hasAudio=\($0.hasAudio) " +
                    "segments=\($0.statisticsForTesting.segments) resets=\($0.statisticsForTesting.resets) " +
                    "time=\($0.currentSeconds) prepared=\($0.preparedMediaForTesting)"
            } ?? "renderer unavailable"
            XCTFail("\(description): \(state)")
            throw AudioStreamError.stalled
        }
    }

    func testOrdinaryAACSegmentsShareOneDecoderAndAdvanceAcrossBothBoundaries() async throws {
        try activateAudio()
        let path = directory()
        let files = try BufferedAudioTestFixture.make(in: path)
        let media = segments(files)
        let renderer = BufferedAudioRenderer()
        defer { renderer.stop(); try? FileManager.default.removeItem(at: path) }
        observeFailures(from: renderer)
        renderer.volume = 0.35
        renderer.updateSegments(media)
        var confirmed = false
        renderer.seek(to: origin.addingTimeInterval(0.1), playing: true) { _ in confirmed = true }
        try await waitUntil("The real AAC renderer becomes ready") { confirmed }
        try await waitUntil("Playback crosses the second compressed-file boundary") {
            (renderer.position ?? self.origin) > media[2].start.addingTimeInterval(0.15)
        }
        XCTAssertNil(rendererFailure)
        XCTAssertEqual(renderer.statisticsForTesting.segments, 3)
        XCTAssertEqual(renderer.statisticsForTesting.resets, 1,
                       "Storage boundaries must append packets without flushing the decoder")
        XCTAssertEqual(renderer.statisticsForTesting.gain, 0.35)
        XCTAssertGreaterThan(try XCTUnwrap(renderer.position), media[2].start)
    }

    func testPausedSeekAcceptsPlayBeforePacketsFinishPreparing() async throws {
        try activateAudio()
        let path = directory()
        // Leave real media after both native audio starts. A four-second finite
        // fixture can be exhausted by the simulator's output/preroll latency.
        let files = try BufferedAudioTestFixture.make(in: path, duration: 12)
        let media = segments(files)
        let renderer = BufferedAudioRenderer()
        defer { renderer.stop(); try? FileManager.default.removeItem(at: path) }
        observeFailures(from: renderer)
        renderer.updateSegments(media)
        let target = origin.addingTimeInterval(0.2)
        renderer.seek(to: target, playing: false) { _ in }
        XCTAssertTrue(renderer.isSeeking)
        renderer.play() // AppModel issues Play immediately after a paused seek/Live.
        try await waitUntil("Latest play intent survives asynchronous seek readiness") {
            renderer.isPlaying && (renderer.position ?? self.origin) > target
        }
        renderer.pause()
        let paused = try XCTUnwrap(renderer.position)
        let last = try XCTUnwrap(media.last)
        XCTAssertGreaterThan(last.end.timeIntervalSince(paused), 4,
                             "Resume must be tested with audio remaining, not at the finite fixture's end")
        print("Renderer pause/resume cursor=\(paused.timeIntervalSince(origin)) prepared=\(renderer.preparedMediaForTesting)")
        let resets = renderer.statisticsForTesting.resets
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(renderer.position, paused)
        XCTAssertFalse(renderer.statisticsForTesting.requested)
        renderer.play()
        try await waitUntil("Ordinary resume keeps the prepared decoder and advances its cursor") {
            renderer.isPlaying && (renderer.position ?? paused) > paused.addingTimeInterval(0.05)
        }
        XCTAssertEqual(renderer.statisticsForTesting.resets, resets)
    }

    func testDeepPausedSeekWithLongPrerollBecomesReadyWithoutAdvancing() async throws {
        try activateAudio()
        let path = directory()
        let files = try BufferedAudioTestFixture.make(in: path, segmentCount: 2, duration: 30)
        let media = segments(files)
        let renderer = BufferedAudioRenderer()
        defer { renderer.stop(); try? FileManager.default.removeItem(at: path) }
        observeFailures(from: renderer)
        renderer.updateSegments(media)
        let target = media[1].start.addingTimeInterval(10)
        var confirmed: Date?
        renderer.seek(to: target, playing: false) { confirmed = $0 }
        try await waitUntil("A deep paused seek prepares with bounded packet preroll", timeout: 12) {
            confirmed != nil
        }
        XCTAssertEqual(confirmed, target)
        XCTAssertFalse(renderer.isPlaying)
        XCTAssertFalse(renderer.statisticsForTesting.requested)
        XCTAssertEqual(renderer.position?.timeIntervalSince(target) ?? -1, 0, accuracy: 0.001)
        let firstPacket = try XCTUnwrap(renderer.preparedMediaForTesting.first)
        XCTAssertGreaterThanOrEqual(firstPacket, renderer.currentSeconds - 1 - 1024.0 / 44_100)
        XCTAssertLessThan(firstPacket, renderer.currentSeconds - 0.9)
        XCTAssertEqual(renderer.statisticsForTesting.segments, 1,
                       "A deep seek should not read an entire preceding storage file")
    }

    func testPausedSeekNearLongSegmentBoundaryKeepsOnlyBoundedPreviousPackets() async throws {
        try activateAudio()
        let path = directory()
        let files = try BufferedAudioTestFixture.make(in: path, segmentCount: 2, duration: 30)
        let media = segments(files)
        let renderer = BufferedAudioRenderer()
        defer { renderer.stop(); try? FileManager.default.removeItem(at: path) }
        observeFailures(from: renderer)
        renderer.updateSegments(media)
        let target = media[1].start.addingTimeInterval(0.1)
        var confirmed: Date?
        renderer.seek(to: target, playing: false) { confirmed = $0 }
        try await waitUntil("A boundary seek prepares using only the preceding file's last packets", timeout: 12) {
            confirmed != nil
        }
        XCTAssertEqual(confirmed, target)
        XCTAssertFalse(renderer.isPlaying)
        XCTAssertEqual(renderer.position?.timeIntervalSince(target) ?? -1, 0, accuracy: 0.001)
        let firstPacket = try XCTUnwrap(renderer.preparedMediaForTesting.first)
        XCTAssertGreaterThanOrEqual(firstPacket, renderer.currentSeconds - 1 - 1024.0 / 44_100)
        XCTAssertLessThan(firstPacket, renderer.currentSeconds - 0.9)
        XCTAssertEqual(renderer.statisticsForTesting.segments, 2)
        XCTAssertEqual(renderer.statisticsForTesting.resets, 1)
    }

    func testPausedSeekIntoShortTailCanPrepareWhenContiguousAudioArrives() async throws {
        try activateAudio()
        let path = directory()
        // Expose only the first half initially. All later files remain cuts of
        // the same encoder stream, so arrival does not justify a decoder reset.
        let files = try BufferedAudioTestFixture.make(in: path, segmentCount: 6, duration: 8)
        let media = segments(files)
        let initial = Array(media.prefix(3))
        let target = initial[2].start
        XCTAssertLessThan(initial[2].end.timeIntervalSince(target), 1.5)
        let renderer = BufferedAudioRenderer()
        defer { renderer.stop(); try? FileManager.default.removeItem(at: path) }
        observeFailures(from: renderer)
        renderer.updateSegments(initial)
        var confirmed: Date?
        renderer.seek(to: target, playing: false) { confirmed = $0 }
        try await waitUntil("The short retained tail is fully enqueued while paused") {
            renderer.statisticsForTesting.segments == 2 &&
                renderer.preparedMediaForTesting.pendingBatches == 0 && renderer.hasAudio
        }
        // Reliable-start thresholds vary by output route. Either an already
        // confirmed seek or one waiting for more packets is valid at this point.
        let resets = renderer.statisticsForTesting.resets
        XCTAssertFalse(renderer.isPlaying)
        XCTAssertFalse(renderer.statisticsForTesting.requested)
        renderer.updateSegments(media)
        try await waitUntil("A contiguous successor completes preparation without a replacing seek") {
            confirmed == target && renderer.statisticsForTesting.segments >= 3
        }
        XCTAssertFalse(renderer.isSeeking)
        XCTAssertFalse(renderer.isPlaying)
        XCTAssertFalse(renderer.statisticsForTesting.requested)
        XCTAssertEqual(renderer.position?.timeIntervalSince(target) ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(renderer.statisticsForTesting.resets, resets)
    }

    func testAutomaticOutputFlushPreservesPausedIntentAndComposedGain() async throws {
        try activateAudio()
        let path = directory()
        let files = try BufferedAudioTestFixture.make(in: path)
        let renderer = BufferedAudioRenderer()
        defer { renderer.stop(); try? FileManager.default.removeItem(at: path) }
        observeFailures(from: renderer)
        renderer.volume = 0
        renderer.updateSegments(segments(files))
        let target = origin.addingTimeInterval(0.3)
        renderer.seek(to: target, playing: false) { _ in }
        try await waitUntil("Paused seek prepares the actual renderer") { !renderer.isSeeking }
        let resets = renderer.statisticsForTesting.resets
        renderer.simulateOutputFlushForTesting()
        try await waitUntil("Output recovery finishes while paused") { !renderer.isSeeking }
        XCTAssertEqual(renderer.statisticsForTesting.resets, resets + 1)
        XCTAssertEqual(renderer.volume, 0)
        XCTAssertFalse(renderer.isPlaying)
        XCTAssertFalse(renderer.statisticsForTesting.requested)
        XCTAssertEqual(renderer.position?.timeIntervalSince(target) ?? -1, 0, accuracy: 0.001)
    }

    func testNewSourceDiscontinuityWaitsUntilPreviousAudioIsConsumedBeforeReset() async throws {
        try activateAudio()
        let path = directory()
        let files = try BufferedAudioTestFixture.make(in: path, segmentCount: 2)
        let ordinary = segments(files)
        let shifted = AudioSegment(url: ordinary[1].url,
                                   start: ordinary[1].start.addingTimeInterval(30),
                                   end: ordinary[1].end.addingTimeInterval(30), byteCount: 1_000,
                                   discontinuity: true)
        let renderer = BufferedAudioRenderer()
        defer { renderer.stop(); try? FileManager.default.removeItem(at: path) }
        observeFailures(from: renderer)
        renderer.updateSegments([ordinary[0], shifted])
        renderer.seek(to: origin.addingTimeInterval(0.1), playing: false) { _ in }
        try await waitUntil("First epoch prepares") { !renderer.isSeeking }
        XCTAssertEqual(renderer.statisticsForTesting.resets, 1)
        XCTAssertEqual(renderer.statisticsForTesting.segments, 1)
        renderer.play()
        try await waitUntil("Source boundary resets only after the first epoch ends") {
            renderer.statisticsForTesting.resets == 2 && !renderer.isSeeking
        }
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(renderer.position), shifted.start)
        XCTAssertEqual(renderer.statisticsForTesting.segments, 2)
    }

    func testCancelledOrExpiredReadCannotCompleteAnObsoleteSeekOrFailPlayback() async throws {
        let path = directory()
        let files = try BufferedAudioTestFixture.make(in: path)
        let media = segments(files)
        let packets = try await BufferedAudioSampleSource.load(url: media[0].url)
        var release: CheckedContinuation<BufferedAudioSamples, Never>?
        let renderer = BufferedAudioRenderer { _ in
            await withCheckedContinuation { release = $0 }
        }
        defer { renderer.stop(); release?.resume(returning: packets); try? FileManager.default.removeItem(at: path) }
        observeFailures(from: renderer)
        var completed = false
        renderer.updateSegments(media)
        renderer.seek(to: origin.addingTimeInterval(0.1), playing: true) { _ in completed = true }
        try await waitUntil("Reader is pending") { release != nil }
        renderer.pause()
        renderer.updateSegments([]) // The file expired while paused and opening.
        let pending = release
        release = nil
        pending?.resume(returning: packets) // Simulate a reader completing after cancellation.
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertFalse(completed)
        XCTAssertNil(rendererFailure)
        XCTAssertFalse(renderer.isPlaying)
        XCTAssertFalse(renderer.hasAudio)
        XCTAssertFalse(renderer.isSeeking)
    }
}
#endif
