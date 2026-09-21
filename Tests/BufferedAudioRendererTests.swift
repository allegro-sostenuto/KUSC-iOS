#if DEBUG && canImport(AVFoundation) && !canImport(KUSCCore)
import AVFoundation
import Foundation
import XCTest
@testable import KUSC_SE

@MainActor final class BufferedAudioRendererTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_789_900_000)

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("kusc-renderer-\(UUID().uuidString)", isDirectory: true)
    }

    private func segments(_ files: BufferedAudioTestFixture.Files) -> [AudioSegment] {
        var start = origin
        return files.segments.enumerated().map { index, url in
            let end = start.addingTimeInterval(files.segmentDurations[index])
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
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        guard condition() else {
            XCTFail(description)
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
        renderer.volume = 0.35
        var errors: [Error] = []
        renderer.onFailure = { errors.append($0) }
        renderer.updateSegments(media)
        var confirmed = false
        renderer.seek(to: origin.addingTimeInterval(0.1), playing: true) { _ in confirmed = true }
        try await waitUntil("The real AAC renderer becomes ready") { confirmed || !errors.isEmpty }
        try await waitUntil("Playback crosses the second compressed-file boundary") {
            (renderer.position ?? self.origin) > media[2].start.addingTimeInterval(0.15) || !errors.isEmpty
        }
        XCTAssertTrue(errors.isEmpty, "\(errors)")
        XCTAssertEqual(renderer.statisticsForTesting.segments, 3)
        XCTAssertEqual(renderer.statisticsForTesting.resets, 1,
                       "Storage boundaries must append packets without flushing the decoder")
        XCTAssertEqual(renderer.statisticsForTesting.gain, 0.35)
        XCTAssertGreaterThan(try XCTUnwrap(renderer.position), media[2].start)
    }

    func testPausedSeekAcceptsPlayBeforePacketsFinishPreparing() async throws {
        try activateAudio()
        let path = directory()
        let files = try BufferedAudioTestFixture.make(in: path)
        let renderer = BufferedAudioRenderer()
        defer { renderer.stop(); try? FileManager.default.removeItem(at: path) }
        renderer.updateSegments(segments(files))
        let target = origin.addingTimeInterval(0.2)
        renderer.seek(to: target, playing: false) { _ in }
        XCTAssertTrue(renderer.isSeeking)
        renderer.play() // AppModel issues Play immediately after a paused seek/Live.
        try await waitUntil("Latest play intent survives asynchronous seek readiness") {
            renderer.isPlaying && (renderer.position ?? self.origin) > target
        }
        renderer.pause()
        let paused = renderer.position
        let resets = renderer.statisticsForTesting.resets
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(renderer.position, paused)
        XCTAssertFalse(renderer.statisticsForTesting.requested)
        renderer.play()
        try await waitUntil("Ordinary resume keeps the prepared decoder") { renderer.isPlaying }
        XCTAssertEqual(renderer.statisticsForTesting.resets, resets)
    }

    func testDeepPausedSeekWithLongPrerollBecomesReadyWithoutAdvancing() async throws {
        try activateAudio()
        let path = directory()
        let files = try BufferedAudioTestFixture.make(in: path, segmentCount: 2, duration: 30)
        let media = segments(files)
        let renderer = BufferedAudioRenderer()
        defer { renderer.stop(); try? FileManager.default.removeItem(at: path) }
        renderer.updateSegments(media)
        let target = media[1].start.addingTimeInterval(10)
        var confirmed: Date?
        renderer.seek(to: target, playing: false) { confirmed = $0 }
        try await waitUntil("A paused seek can decode through more than 25 seconds of preroll", timeout: 12) {
            confirmed != nil
        }
        XCTAssertEqual(confirmed, target)
        XCTAssertFalse(renderer.isPlaying)
        XCTAssertFalse(renderer.statisticsForTesting.requested)
        XCTAssertEqual(renderer.position?.timeIntervalSince(target) ?? -1, 0, accuracy: 0.001)
    }

    func testAutomaticOutputFlushPreservesPausedIntentAndComposedGain() async throws {
        try activateAudio()
        let path = directory()
        let files = try BufferedAudioTestFixture.make(in: path)
        let renderer = BufferedAudioRenderer()
        defer { renderer.stop(); try? FileManager.default.removeItem(at: path) }
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
        var completed = false
        var errors: [Error] = []
        renderer.onFailure = { errors.append($0) }
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
        XCTAssertTrue(errors.isEmpty)
        XCTAssertFalse(renderer.isPlaying)
        XCTAssertFalse(renderer.hasAudio)
        XCTAssertFalse(renderer.isSeeking)
    }
}
#endif
