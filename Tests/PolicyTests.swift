import Foundation
import XCTest
#if canImport(KUSCCore)
@testable import KUSCCore
#else
@testable import KUSC_SE
#endif

final class BufferPolicyTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_000_000)

    private func date(_ seconds: TimeInterval) -> Date { origin.addingTimeInterval(seconds) }
    private func segment(_ start: TimeInterval, _ end: TimeInterval, bytes: Int = 100) -> AudioSegment {
        AudioSegment(url: URL(fileURLWithPath: "/tmp/\(start).aac"),
                     start: date(start), end: date(end), byteCount: bytes)
    }

    func testRetentionExcludesExpiredPrefixWithoutDeletingPlayableRemainder() {
        let segments = [segment(0, 30), segment(30, 70), segment(70, 100)]
        let result = BufferRetention.trim(segments, live: date(100), minutes: 1)
        XCTAssertEqual(result.retained.map(\.id), Array(segments.suffix(2)).map(\.id))
        XCTAssertEqual(result.expired.map(\.id), [segments[0].id])
        XCTAssertEqual(result.window, BufferWindow(oldest: date(40), live: date(100)))
        XCTAssertFalse(result.window!.contains(date(39)))
        XCTAssertEqual(BufferRetention.seekTarget(date(35), result: result), date(40))
    }

    func testExactCutoffIsExpiredAndZeroRetentionKeepsNoFiles() {
        let segments = [segment(0, 40), segment(40, 100)]
        let trimmed = BufferRetention.trim(segments, live: date(100), minutes: 1)
        XCTAssertEqual(trimmed.retained.count, 1)
        let disabled = BufferRetention.trim(segments, live: date(100), minutes: 0)
        XCTAssertTrue(disabled.retained.isEmpty)
        XCTAssertEqual(disabled.expired.count, 2)
        XCTAssertNil(disabled.window)
        XCTAssertNil(BufferRetention.seekTarget(date(50), result: disabled))
    }

    func testRetentionSettingIsCappedToFifteenMinutes() {
        let result = BufferRetention.trim([segment(0, 1_000)], live: date(1_000), minutes: 99)
        XCTAssertEqual(result.window?.oldest, date(100))
    }

    func testMalformedAndFutureSegmentsCannotBecomePlayable() {
        let valid = segment(80, 100)
        let segments = [segment(30, 20), valid, segment(110, 130)]
        let result = BufferRetention.trim(segments, live: date(100), minutes: 15)
        XCTAssertEqual(result.retained, [valid])
        XCTAssertEqual(result.expired.count, 2)
    }

    func testHardStorageAndSegmentBoundsPreferRecentAudio() {
        let segments = [segment(0, 10), segment(10, 20), segment(20, 30)]
        let bytes = BufferRetention.trim(segments, live: date(30), minutes: 15, byteLimit: 200)
        XCTAssertEqual(bytes.retained, Array(segments.suffix(2)))
        let count = BufferRetention.trim(segments, live: date(30), minutes: 15, segmentLimit: 1)
        XCTAssertEqual(count.retained, [segments[2]])
        XCTAssertEqual(count.window?.oldest, date(20))
    }

    func testSeekingClampsBothEndsAndSkipsMissingAudio() {
        let result = BufferRetention.trim([segment(20, 40), segment(60, 80)],
                                          live: date(80), minutes: 15)
        XCTAssertEqual(BufferRetention.seekTarget(date(-10), result: result), date(20))
        XCTAssertEqual(BufferRetention.seekTarget(date(30), result: result), date(30))
        XCTAssertEqual(BufferRetention.seekTarget(date(50), result: result), date(60))
        XCTAssertEqual(BufferRetention.seekTarget(date(100), result: result), date(80))
    }

    func testResumeLiveAndResumeWherePausedIncludingAgedOutCursor() {
        let window = BufferWindow(oldest: date(40), live: date(100))
        XCTAssertEqual(ResumePolicy.target(mode: .live, pausedAt: date(70), window: window), date(100))
        XCTAssertEqual(ResumePolicy.target(mode: .wherePaused, pausedAt: date(70), window: window), date(70))
        XCTAssertEqual(ResumePolicy.target(mode: .wherePaused, pausedAt: date(10), window: window), date(40))
        XCTAssertEqual(ResumePolicy.target(mode: .wherePaused, pausedAt: nil, window: window), date(100))
    }
}

final class PlaybackTimelineTests: XCTestCase {
    private func item(_ n: Int, end: Date? = nil) -> ProgrammeItem {
        ProgrammeItem(id: String(n), start: Date(timeIntervalSince1970: Double(n * 60)),
                      end: end, work: "Work \(n)")
    }

    func testMetadataTracksHeardAudioInsteadOfNewestStationUpdate() {
        var timeline = PlaybackTimeline(items: [item(1), item(2)])
        timeline.merge([item(3), item(4)])
        XCTAssertEqual(timeline.item(at: Date(timeIntervalSince1970: 90))?.id, "1")
        XCTAssertEqual(timeline.item(at: Date(timeIntervalSince1970: 120))?.id, "2")
        XCTAssertEqual(timeline.item(at: Date(timeIntervalSince1970: 250))?.id, "4")
        XCTAssertNil(timeline.item(at: Date(timeIntervalSince1970: 0)))
    }

    func testExplicitEndLeavesSpeechGapAndExactNextStartResolvesNextPiece() {
        let timeline = PlaybackTimeline(items: [item(1, end: Date(timeIntervalSince1970: 90)), item(2)])
        XCTAssertNotNil(timeline.item(at: Date(timeIntervalSince1970: 89)))
        XCTAssertNil(timeline.item(at: Date(timeIntervalSince1970: 90)))
        XCTAssertNil(timeline.item(at: Date(timeIntervalSince1970: 110)))
        XCTAssertEqual(timeline.item(at: Date(timeIntervalSince1970: 120))?.id, "2")
    }

    func testProgrammeContextReanchorsOnSeekWithFivePreviousAndTenUpcoming() {
        let timeline = PlaybackTimeline(items: (0..<30).map { item($0) })
        let context = timeline.context(at: Date(timeIntervalSince1970: 600))
        XCTAssertEqual(context.current?.id, "10")
        XCTAssertEqual(context.previous.map(\.id), ["9", "8", "7", "6", "5"])
        XCTAssertEqual(context.upcoming.map(\.id), (11...20).map(String.init))
        let earlier = timeline.context(at: Date(timeIntervalSince1970: 60))
        XCTAssertEqual(earlier.previous.map(\.id), ["0"])
        XCTAssertEqual(earlier.upcoming.first?.id, "2")
    }

    func testMergingRefreshesStableIdentityAndBoundsCache() {
        var timeline = PlaybackTimeline(items: (0..<300).map { item($0) })
        XCTAssertEqual(timeline.items.count, 256)
        XCTAssertEqual(timeline.items.first?.id, "44")
        var update = item(299)
        update.performers = "Updated performer"
        timeline.merge([update, update])
        XCTAssertEqual(timeline.items.count, 256)
        XCTAssertEqual(timeline.items.last?.performers, "Updated performer")
    }

    func testTitleIncludesMovementOnlyWhenSupplied() {
        var piece = item(0)
        XCTAssertEqual(piece.title, "Work 0")
        piece.movement = "  "
        XCTAssertEqual(piece.title, "Work 0")
        piece.movement = "II. Andante"
        XCTAssertEqual(piece.title, "Work 0 — II. Andante")
    }
}

final class SleepPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private var heard: Date { now.addingTimeInterval(-420) }
    private func heardPlus(_ interval: TimeInterval) -> Date { heard.addingTimeInterval(interval) }

    func testReliableMovementCompletesWithinTenMinutesUsingDelayedAudioClock() {
        let decision = SleepPolicy.evaluate(now: now, heardAt: heard, movementEnd: heardPlus(300),
                                             movementEndReliable: true, nextStart: nil)
        XCTAssertEqual(decision, .stopAt(now.addingTimeInterval(300)))
    }

    func testReliableMovementAtTenMinuteBoundaryCompletesButLongerFades() {
        XCTAssertEqual(SleepPolicy.evaluate(now: now, heardAt: heard, movementEnd: heardPlus(600),
                                             movementEndReliable: true, nextStart: nil),
                       .stopAt(now.addingTimeInterval(600)))
        XCTAssertEqual(SleepPolicy.evaluate(now: now, heardAt: heard, movementEnd: heardPlus(601),
                                             movementEndReliable: true, nextStart: nil),
                       .fade(start: now, end: now.addingTimeInterval(60)))
    }

    func testUnknownMovementUsesNextStartAndFadesForLastMinute() {
        XCTAssertEqual(SleepPolicy.evaluate(now: now, heardAt: heard, movementEnd: heardPlus(900),
                                             movementEndReliable: false, nextStart: heardPlus(300)),
                       .fade(start: now.addingTimeInterval(240), end: now.addingTimeInterval(300)))
    }

    func testImminentNextStartCompressesFade() {
        XCTAssertEqual(SleepPolicy.evaluate(now: now, heardAt: heard, movementEnd: nil,
                                             movementEndReliable: false, nextStart: heardPlus(20)),
                       .fade(start: now, end: now.addingTimeInterval(20)))
        XCTAssertEqual(SleepPolicy.gain(at: now.addingTimeInterval(10),
                                       fadeStart: now, fadeEnd: now.addingTimeInterval(20)), 0.5)
    }

    func testFallbackMoreThanTenMinutesAwayFadesImmediately() {
        XCTAssertEqual(SleepPolicy.evaluate(now: now, heardAt: heard, movementEnd: nil,
                                             movementEndReliable: false, nextStart: heardPlus(601)),
                       .fade(start: now, end: now.addingTimeInterval(60)))
    }

    func testMissingMetadataRetriesForOnlyOneMinuteThenFades() {
        XCTAssertEqual(SleepPolicy.evaluate(now: now, heardAt: heard, movementEnd: nil,
                                             movementEndReliable: false, nextStart: nil),
                       .retry(until: now.addingTimeInterval(60)))
        let at59 = now.addingTimeInterval(59)
        XCTAssertEqual(SleepPolicy.evaluate(now: at59, heardAt: heardPlus(59), movementEnd: nil,
                                             movementEndReliable: false, nextStart: nil, retryStartedAt: now),
                       .retry(until: now.addingTimeInterval(60)))
        let at60 = now.addingTimeInterval(60)
        XCTAssertEqual(SleepPolicy.evaluate(now: at60, heardAt: heardPlus(60), movementEnd: nil,
                                             movementEndReliable: false, nextStart: nil, retryStartedAt: now),
                       .fade(start: at60, end: now.addingTimeInterval(120)))
    }

    func testNewMetadataDuringRetryDeterminesEndpointAndPastFallbackIsIgnored() {
        let later = now.addingTimeInterval(30)
        XCTAssertEqual(SleepPolicy.evaluate(now: later, heardAt: heardPlus(30), movementEnd: nil,
                                             movementEndReliable: false, nextStart: heardPlus(100), retryStartedAt: now),
                       .fade(start: now.addingTimeInterval(40), end: now.addingTimeInterval(100)))
        XCTAssertEqual(SleepPolicy.evaluate(now: now, heardAt: heard, movementEnd: nil,
                                             movementEndReliable: false, nextStart: heardPlus(-10)),
                       .retry(until: now.addingTimeInterval(60)))
    }

    func testLinearGainClampsOutsideFadeAndStopsAtZeroDurationEndpoint() {
        let end = now.addingTimeInterval(60)
        XCTAssertEqual(SleepPolicy.gain(at: now.addingTimeInterval(-1), fadeStart: now, fadeEnd: end), 1)
        XCTAssertEqual(SleepPolicy.gain(at: now.addingTimeInterval(30), fadeStart: now, fadeEnd: end), 0.5)
        XCTAssertEqual(SleepPolicy.gain(at: end, fadeStart: now, fadeEnd: end), 0)
        XCTAssertEqual(SleepPolicy.gain(at: end.addingTimeInterval(1), fadeStart: now, fadeEnd: end), 0)
        XCTAssertEqual(SleepPolicy.gain(at: now, fadeStart: now, fadeEnd: now), 0)
    }
}

final class TimingPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testReconnectStopsAtOneMinuteRatherThanRestartingItsDeadline() {
        let policy = ReconnectPolicy(startedAt: now)
        XCTAssertEqual(policy.decision(at: now), .retry(elapsed: 0))
        XCTAssertEqual(policy.decision(at: now.addingTimeInterval(59)), .retry(elapsed: 59))
        XCTAssertEqual(policy.decision(at: now.addingTimeInterval(60)), .stop)
        XCTAssertEqual(policy.decision(at: now.addingTimeInterval(120)), .stop)
    }

    func testPluggedStandbyAndInitialBatteryOnlyNotification() {
        XCTAssertEqual(StandbyPolicy.update(now: now, isPluggedIn: true, batteryLevel: 0.1,
                                            unpluggedAt: nil, wasStandingBy: false),
                       .standby(unpluggedAt: nil))
        XCTAssertEqual(StandbyPolicy.update(now: now, isPluggedIn: false, batteryLevel: 1,
                                            unpluggedAt: nil, wasStandingBy: false), .notificationOnly)
    }

    func testUnplugGraceStartsOnceAndExpiresAtTenMinutes() {
        XCTAssertEqual(StandbyPolicy.update(now: now, isPluggedIn: false, batteryLevel: 0.8,
                                            unpluggedAt: nil, wasStandingBy: true),
                       .standby(unpluggedAt: now))
        XCTAssertEqual(StandbyPolicy.update(now: now.addingTimeInterval(599), isPluggedIn: false,
                                            batteryLevel: 0.8, unpluggedAt: now, wasStandingBy: true),
                       .standby(unpluggedAt: now))
        XCTAssertEqual(StandbyPolicy.update(now: now.addingTimeInterval(600), isPluggedIn: false,
                                            batteryLevel: 0.8, unpluggedAt: now, wasStandingBy: true), .notificationOnly)
    }

    func testReplugClearsUnplugDeadline() {
        XCTAssertEqual(StandbyPolicy.update(now: now.addingTimeInterval(500), isPluggedIn: true,
                                            batteryLevel: 0.5, unpluggedAt: now, wasStandingBy: true),
                       .standby(unpluggedAt: nil))
    }

    func testThirtyPercentBoundaryAndUnknownBattery() {
        XCTAssertEqual(StandbyPolicy.update(now: now, isPluggedIn: false, batteryLevel: 0.30,
                                            unpluggedAt: now, wasStandingBy: true),
                       .standby(unpluggedAt: now))
        for level in [0.2999, -1.0, Double.nan] {
            XCTAssertEqual(StandbyPolicy.update(now: now, isPluggedIn: false, batteryLevel: level,
                                                unpluggedAt: now, wasStandingBy: true), .notificationOnly)
        }
    }

    func testSchedulesAreStrictlyFutureAndAtMostTwentyFourHoursAway() {
        XCTAssertFalse(StandbyPolicy.isValidSchedule(now, now: now))
        XCTAssertFalse(StandbyPolicy.isValidSchedule(now.addingTimeInterval(-1), now: now))
        XCTAssertTrue(StandbyPolicy.isValidSchedule(now.addingTimeInterval(1), now: now))
        XCTAssertTrue(StandbyPolicy.isValidSchedule(now.addingTimeInterval(86_400), now: now))
        XCTAssertFalse(StandbyPolicy.isValidSchedule(now.addingTimeInterval(86_401), now: now))
    }

    func testScheduledStartIsNoOpWhenAlreadyPlaying() {
        XCTAssertFalse(StandbyPolicy.shouldStartScheduled(alreadyPlaying: true))
        XCTAssertTrue(StandbyPolicy.shouldStartScheduled(alreadyPlaying: false))
    }
}
