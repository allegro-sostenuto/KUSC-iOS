import Foundation
import XCTest
#if canImport(KUSCCore)
@testable import KUSCCore
#else
@testable import KUSC_SE
#endif

final class ScheduleRegressionTests: XCTestCase {
    private let target = Date(timeIntervalSince1970: 1_000_000)

    func testRealPrerollStartsAtSixtySecondsNotAtSelectedTime() {
        XCTAssertFalse(ScheduledStartPolicy.shouldPrepare(target: target, now: target.addingTimeInterval(-60.001)))
        XCTAssertTrue(ScheduledStartPolicy.shouldPrepare(target: target, now: target.addingTimeInterval(-60)))
        XCTAssertTrue(ScheduledStartPolicy.shouldPrepare(target: target, now: target.addingTimeInterval(-12)))
    }

    func testOnTimeCapturedGainTraceHasFiftySilentSecondsAndTenSecondRamp() {
        let envelope = ScheduledGainEnvelope(target: target, readyAt: target.addingTimeInterval(-60), uptime: 100)
        let trace = (0...1800).map { envelope.gain(at: 100 + Double($0) / 30) }
        XCTAssertTrue(trace.prefix(1501).allSatisfy { $0 == 0 })
        XCTAssertGreaterThan(trace[1501], 0)
        XCTAssertEqual(trace[1650], 0.5, accuracy: 0.0001)
        XCTAssertEqual(trace[1800], 1)
        XCTAssertGreaterThan(Set(trace.suffix(300)).count, 250, "The fade must not be a one-second staircase")
        XCTAssertTrue(zip(trace, trace.dropFirst()).allSatisfy { $0.0 <= $0.1 })
    }

    func testShortLeadKeepsOriginalFadeAndTargetDeadlines() {
        let envelope = ScheduledGainEnvelope(target: target, readyAt: target.addingTimeInterval(-20), uptime: 100)
        XCTAssertEqual(envelope.gain(at: 110), 0)
        XCTAssertEqual(envelope.gain(at: 115), 0.5)
        XCTAssertEqual(envelope.gain(at: 120), 1)
    }

    func testReadinessInsideFadeStartsAtZeroAndUsesRemainingTime() {
        let envelope = ScheduledGainEnvelope(target: target, readyAt: target.addingTimeInterval(-4), uptime: 100)
        XCTAssertEqual(envelope.gain(at: 100), 0)
        XCTAssertEqual(envelope.gain(at: 102), 0.5)
        XCTAssertEqual(envelope.gain(at: 104), 1)
    }

    func testReadinessAtOrAfterTargetAndNotificationTapGetOnlyTenSecondFade() {
        for delay in [0.0, 1.0, 120.0, 3_600.0] {
            let envelope = ScheduledGainEnvelope(target: target, readyAt: target.addingTimeInterval(delay), uptime: 100)
            XCTAssertEqual(envelope.gain(at: 100), 0)
            XCTAssertEqual(envelope.gain(at: 105), 0.5)
            XCTAssertTrue(envelope.isComplete(at: 110))
            XCTAssertEqual(envelope.gain(at: 110), 1)
        }
    }

    func testUptimeEnvelopeCannotReverseWhenWallClockChanges() {
        let envelope = ScheduledGainEnvelope(target: target, readyAt: target.addingTimeInterval(-5), uptime: 900)
        // The ready-to-target interval is anchored once. Later clock/time-zone
        // notifications do not replace this value while audio remains ready.
        XCTAssertEqual(envelope.startUptime, 900)
        XCTAssertEqual(envelope.endUptime, 905)
        XCTAssertEqual(envelope.gain(at: 901), 0.2, accuracy: 0.0001)
        XCTAssertEqual(envelope.gain(at: 904), 0.8, accuracy: 0.0001)
        XCTAssertEqual(envelope.gain(at: 910), 1)
    }

    func testSleepAndPauseRemainAuthoritativeDuringScheduledFade() {
        XCTAssertEqual(ScheduledStartPolicy.composedGain(schedule: 0, sleep: 1, muted: false), 0)
        XCTAssertEqual(ScheduledStartPolicy.composedGain(schedule: 0.5, sleep: 0.4, muted: false), 0.2, accuracy: 0.0001)
        XCTAssertEqual(ScheduledStartPolicy.composedGain(schedule: 1, sleep: 0, muted: false), 0)
        XCTAssertEqual(ScheduledStartPolicy.composedGain(schedule: 1, sleep: 1, muted: true), 0)
        // Canceling a sleep envelope cannot unmute a scheduled silent pre-roll.
        XCTAssertEqual(ScheduledStartPolicy.composedGain(schedule: 0, sleep: 1, muted: false), 0)
    }

    func testPreferredRouteMatchesIdentityAndTransportNotFriendlyName() {
        let chosen = route("bt:1", "BluetoothA2DP", "Living Room")
        let preference = ScheduledOutputPreference(route: chosen)
        XCTAssertEqual(preference.fallback, .notifyOnly)
        XCTAssertTrue(preference.permits(route("bt:1", "BluetoothA2DP", "Renamed Speaker")))
        XCTAssertFalse(preference.permits(route("bt:2", "BluetoothA2DP", "Living Room")))
        XCTAssertFalse(preference.permits(route("bt:1", "AirPlay", "Living Room")))
        XCTAssertFalse(preference.permits(route("speaker", "Speaker", "iPhone")))
    }

    func testRouteLossOnlyAllowsExplicitCurrentOutputFallback() {
        let chosen = route("airplay:1", "AirPlay", "Home")
        let phone = route("speaker", "Speaker", "iPhone")
        XCTAssertFalse(ScheduledOutputPreference(route: chosen).permits(phone))
        XCTAssertTrue(ScheduledOutputPreference(route: chosen, fallback: .currentOutput).permits(phone))
        XCTAssertTrue(ScheduledOutputPreference.currentOutput.permits(phone))
        XCTAssertFalse(ScheduledOutputPreference.currentOutput.permits(.init(ports: [])))
    }

    func testMultiOutputRequiresTheWholeObservedSetAndUnknownUIDCannotBePinned() {
        let first = route("airplay:1", "AirPlay", "Room A")
        let second = route("airplay:2", "AirPlay", "Room B")
        let group = ObservedAudioRoute(ports: first.ports + second.ports)
        XCTAssertTrue(group.matches(.init(ports: second.ports + first.ports)))
        XCTAssertFalse(group.matches(first))
        let ambiguous = route("", "AirPlay", "Room A")
        XCTAssertFalse(ambiguous.isIdentifiable)
        XCTAssertNil(ScheduledOutputPreference(route: ambiguous).route)
        let duplicate = ObservedAudioRoute(ports: first.ports + first.ports)
        XCTAssertFalse(duplicate.isIdentifiable)
        XCTAssertFalse(duplicate.matches(first), "Duplicate UID/transport pairs cannot identify a multi-output set")
        XCTAssertNil(ScheduledOutputPreference(route: duplicate).route)
    }

    func testPersistentOneTimeSchedulePreservesGenerationDeadlineAndOutput() throws {
        let original = ScheduledStartRequest(date: target,
            output: .init(route: route("bt:1", "BluetoothA2DP", "Speaker"), fallback: .notifyOnly))
        let restored = try JSONDecoder().decode(ScheduledStartRequest.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored, original)
        XCTAssertNotEqual(ScheduledStartRequest(date: target).id, original.id)
    }

    func testCanceledAndSupersededNotificationSetupsCannotAcquirePlayback() {
        var generation = ScheduleGeneration()
        let firstRequest = generation.begin()
        XCTAssertTrue(generation.accepts(firstRequest))
        let replacement = generation.begin()
        XCTAssertFalse(generation.accepts(firstRequest), "A delayed notification authorization may not restore the older schedule")
        XCTAssertTrue(generation.accepts(replacement))
        generation.invalidate() // Pause, manual Play, Live, seek, or explicit cancel.
        XCTAssertFalse(generation.accepts(replacement), "An explicit transport action wins over pending scheduling work")
    }

    func testAlreadyPlayingScheduleIsConsumedWithoutNewPlaybackIntent() {
        XCTAssertFalse(StandbyPolicy.shouldStartScheduled(alreadyPlaying: true))
        XCTAssertTrue(StandbyPolicy.shouldStartScheduled(alreadyPlaying: false))
    }

    @MainActor func testOlderNotificationCompletionCannotRemoveNewerFallback() async throws {
        let writer = ScheduledNotificationWrites()
        let id = UUID()
        var continuation: CheckedContinuation<Void, Never>?
        var trace: [String] = []
        let first = writer.submit(id: id, write: {
            trace.append("first started")
            await withCheckedContinuation { continuation = $0 }
            trace.append("first written")
        }, remove: { trace.append("removed") })
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        XCTAssertNotNil(continuation)
        let second = writer.submit(id: id, write: { trace.append("latest written") }, remove: { trace.append("removed") })
        continuation?.resume()
        try await first.value
        try await second.value
        XCTAssertEqual(trace, ["first started", "first written", "latest written"])
    }

    @MainActor func testCancelRemovesAStillCompletingNotificationWrite() async throws {
        let writer = ScheduledNotificationWrites()
        let id = UUID()
        var continuation: CheckedContinuation<Void, Never>?
        var present = false
        let task = writer.submit(id: id, write: {
            await withCheckedContinuation { continuation = $0 }
            present = true
        }, remove: { present = false })
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        XCTAssertNotNil(continuation)
        writer.cancel(id: id) { present = false }
        continuation?.resume()
        try await task.value
        XCTAssertFalse(present, "A late system add cannot resurrect a canceled notification")
    }

    @MainActor func testCancelThenRetrySerializesAgainstTheCanceledSystemAdd() async throws {
        let writer = ScheduledNotificationWrites()
        let id = UUID()
        var continuation: CheckedContinuation<Void, Never>?
        var content: String?
        let first = writer.submit(id: id, write: {
            await withCheckedContinuation { continuation = $0 }
            content = "obsolete"
        }, remove: { content = nil })
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        XCTAssertNotNil(continuation)
        writer.cancel(id: id) { content = nil }
        let replacement = writer.submit(id: id, write: { content = "replacement" }, remove: { content = nil })
        continuation?.resume()
        try await first.value
        try await replacement.value
        XCTAssertEqual(content, "replacement")
    }

    private func route(_ uid: String, _ type: String, _ name: String) -> ObservedAudioRoute {
        .init(ports: [.init(uid: uid, type: type, name: name)])
    }
}
