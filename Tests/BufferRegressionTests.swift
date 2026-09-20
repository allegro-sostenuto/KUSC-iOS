import Foundation
import XCTest
#if canImport(KUSCCore)
@testable import KUSCCore
#else
@testable import KUSC_SE
#endif

final class BufferRegressionTests: XCTestCase {
    private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }
    private func segment(_ start: TimeInterval, _ end: TimeInterval, discontinuity: Bool = false) -> AudioSegment {
        AudioSegment(url: URL(fileURLWithPath: "/tmp/\(start).aac"), start: date(start), end: date(end),
                     byteCount: 100, discontinuity: discontinuity)
    }
    private func retained(_ segments: [AudioSegment], minutes: Int = 15) -> RetentionResult {
        BufferRetention.trim(segments, live: segments.last!.end, minutes: minutes)
    }

    func testLiveButtonAndRightEdgeUseOneSafeTarget() {
        let result = retained([segment(0, 10), segment(10, 20)])
        var clock = LivePlaybackClock()
        let target = clock.target(in: result, uptime: 100)!
        XCTAssertEqual(target, date(6))
        XCTAssertEqual(LivePlaybackClock.seekTarget(result.window!.live, liveTarget: target, result: result), target)
        XCTAssertEqual(LivePlaybackClock.seekTarget(date(100), liveTarget: target, result: result), target)
        XCTAssertEqual(result.window!.live.timeIntervalSince(target), 14)
    }

    func testSegmentArrivalDoesNotMoveLiveTargetByOneSegment() {
        var clock = LivePlaybackClock()
        let initial = retained([segment(0, 10), segment(10, 20)])
        XCTAssertEqual(clock.target(in: initial, uptime: 100), date(6))
        XCTAssertEqual(clock.target(in: initial, uptime: 102), date(8))
        let next = retained([segment(0, 10), segment(10, 20), segment(20, 30)])
        XCTAssertEqual(clock.target(in: next, uptime: 102), date(8))
        XCTAssertEqual(clock.target(in: next, uptime: 110), date(16))
    }

    func testMissingNextSegmentCapsTargetAndDoesNotAccumulateCatchupJump() {
        var clock = LivePlaybackClock()
        let initial = retained([segment(0, 10), segment(10, 20)])
        _ = clock.target(in: initial, uptime: 100)
        XCTAssertEqual(clock.target(in: initial, uptime: 120), date(18))
        XCTAssertEqual(clock.target(in: initial, uptime: 130), date(18))
        let next = retained([segment(0, 10), segment(10, 20), segment(20, 30)])
        XCTAssertEqual(clock.target(in: next, uptime: 130), date(18))
        XCTAssertEqual(clock.target(in: next, uptime: 131), date(19))
    }

    func testShortOrGappedAvailableSuffixNeverBorrowsMissingHeadroom() {
        var clock = LivePlaybackClock()
        let result = retained([segment(0, 10), segment(50, 53)])
        XCTAssertEqual(clock.target(in: result, uptime: 100), date(50))
        XCTAssertEqual(LivePlaybackClock.seekTarget(date(25), liveTarget: date(50), result: result), date(50))
    }

    func testRecoveryCannotLeaveTheLiveDefinitionMinutesBehindDownloadedAudio() {
        var clock = LivePlaybackClock()
        let initial = retained([segment(0, 10), segment(10, 20)])
        _ = clock.target(in: initial, uptime: 100)
        _ = clock.target(in: initial, uptime: 130)
        let recovered = retained((0..<12).map { segment(Double($0 * 10), Double(($0 + 1) * 10)) })
        XCTAssertEqual(clock.target(in: recovered, uptime: 130), date(106))
        // The separate heard clock is untouched; a delayed listener stays delayed.
        var cursor = ConfirmedPlaybackCursor()
        cursor.record(date(18))
        XCTAssertEqual(cursor.position, date(18))
    }

    func testExplicitDiscontinuityDefinesNewLiveSuffix() {
        var clock = LivePlaybackClock()
        let result = retained([segment(0, 10), segment(10, 13, discontinuity: true)])
        XCTAssertEqual(clock.target(in: result, uptime: 100), date(10))
    }

    func testGapSeekPublishesNextPlayablePositionInsteadOfRequest() {
        let result = retained([segment(0, 10), segment(20, 30), segment(30, 40)])
        let resolved = LivePlaybackClock.seekTarget(date(15), liveTarget: date(32), result: result)
        XCTAssertEqual(resolved, date(20))
        var cursor = ConfirmedPlaybackCursor()
        cursor.record(date(5))
        // An outstanding preview is not a media sample.
        XCTAssertEqual(cursor.position, date(5))
        cursor.record(resolved, confirmingSeek: true)
        XCTAssertEqual(cursor.position, date(20))
    }

    func testExhaustedQueueRetainsFinalCursorAndRejectsBackwardItemSamples() {
        var cursor = ConfirmedPlaybackCursor()
        cursor.record(date(19))
        cursor.record(date(20))
        cursor.record(nil)
        cursor.record(date(10))
        XCTAssertEqual(cursor.position, date(20))
        cursor.record(date(20.25))
        XCTAssertEqual(cursor.position, date(20.25))
        cursor.record(date(5), confirmingSeek: true)
        XCTAssertEqual(cursor.position, date(5))
    }

    func testRapidSeeksPauseAndLiveRejectObsoleteCompletions() {
        var requests = PlaybackSeekGeneration()
        let a = requests.begin()
        let b = requests.begin()
        XCTAssertFalse(requests.accepts(a))
        XCTAssertTrue(requests.accepts(b))
        requests.invalidate() // Pause or teardown.
        XCTAssertFalse(requests.accepts(b))
        let live = requests.begin()
        XCTAssertFalse(requests.accepts(a))
        XCTAssertFalse(requests.accepts(b))
        XCTAssertTrue(requests.accepts(live))
        requests.invalidate() // Completion is consumed once.
        XCTAssertFalse(requests.accepts(live))
    }

    func testStaleAcquisitionCannotClaimLiveAndIntentionalRewindStaysDelayed() {
        XCTAssertTrue(LivePlaybackClock.isAtLive(heardAt: date(12), liveTarget: date(12), acquisitionIsStale: false))
        XCTAssertFalse(LivePlaybackClock.isAtLive(heardAt: date(12), liveTarget: date(12), acquisitionIsStale: true))
        XCTAssertFalse(LivePlaybackClock.isAtLive(heardAt: date(10), liveTarget: date(12), acquisitionIsStale: false))
    }

    func testAvailableRangeUsesCollectedHistoryAndEveryRetentionValue() {
        for minutes in 0...15 {
            var clock = LivePlaybackClock()
            let result = retained([segment(0, 10), segment(10, 20)], minutes: minutes)
            if minutes == 0 { XCTAssertNil(clock.target(in: result, uptime: 100)) }
            else {
                let live = clock.target(in: result, uptime: 100)!
                XCTAssertEqual(live.timeIntervalSince(result.window!.oldest), 6)
            }
        }
    }

    func testPollingDoesNotAddSleepToSlowDownloads() {
        XCTAssertEqual(AcquisitionPollPolicy.delay(targetDuration: 10, elapsed: 0), 2)
        XCTAssertEqual(AcquisitionPollPolicy.delay(targetDuration: 10, elapsed: 1.75), 0.25)
        XCTAssertEqual(AcquisitionPollPolicy.delay(targetDuration: 10, elapsed: 3), 0)
        XCTAssertEqual(AcquisitionPollPolicy.delay(targetDuration: 4, elapsed: 0.2), 0.8, accuracy: 0.0001)
    }

    func testQueuePreservesFilesWithAcceptedTimestampOverlap() {
        let first = segment(0, 10)
        let overlap = segment(9.8, 19.8)
        let third = segment(19.8, 29.8)
        let fourth = segment(29.8, 39.8)
        let files = [first, overlap, third, fourth]
        XCTAssertEqual(BufferQueuePolicy.followers(after: first, retained: files,
            alreadyQueued: [first.id], limit: 3), [overlap, third, fourth])
        XCTAssertEqual(BufferQueuePolicy.followers(after: first, retained: files,
            alreadyQueued: [first.id, overlap.id], limit: 2), [third, fourth])
        XCTAssertTrue(BufferQueuePolicy.followers(after: fourth, retained: files,
            alreadyQueued: [fourth.id], limit: 3).isEmpty)
    }

    func testQueueCanFollowAnExpiredTailWithoutReplayingEarlierFiles() {
        let expired = segment(0, 10)
        let files = [segment(9.8, 19.8), segment(19.8, 29.8)]
        XCTAssertEqual(BufferQueuePolicy.followers(after: expired, retained: files,
            alreadyQueued: [], limit: 4), files)
    }

    func testTenSecondSegmentCadenceMaintainsHeadroomAcrossAMinute() {
        var clock = LivePlaybackClock()
        var files = [segment(0, 10), segment(10, 20)]
        let initial = clock.target(in: retained(files), uptime: 100)!
        XCTAssertEqual(initial, date(6))
        // New ten-second segments arrive with an additional two-second delay.
        // The actual player can advance continuously without reaching the end.
        for second in 1...60 {
            if second >= 12 && (second - 12) % 10 == 0 {
                let end = files.last!.end.timeIntervalSince1970
                files.append(segment(end, end + 10))
            }
            let actual = initial.addingTimeInterval(Double(second))
            XCTAssertLessThan(actual, files.last!.end)
            let live = clock.target(in: retained(files), uptime: 100 + Double(second))!
            XCTAssertEqual(live, actual)
        }
    }
}
