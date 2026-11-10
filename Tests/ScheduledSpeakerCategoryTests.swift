#if canImport(UIKit) && !canImport(PhilharmonicCore) && DEBUG
import XCTest
import AVFoundation
@testable import Philharmonic_SE

/// Replays the captured set_category rejection through the actual coordinator.
/// This injects the phone's error; it does not reproduce an iOS policy decision.
final class ScheduledSpeakerCategoryTests: XCTestCase {
    @MainActor func testCapturedAlreadySpeakerFailureMustNotPreventScheduledPlayback() async throws {
        let model = AppModel.shared
        let oldStation = model.selectedStation.id
        model.selectStation("yle-klassinen")
        defer { model.finishScheduleForTesting(); model.selectStation(oldStation) }
        model.configureScheduleForTesting(secondsUntilStart: -551.548,
                                          environment: environment(route: speaker))
        let id = try XCTUnwrap(model.scheduleIDForTesting).uuidString
        for _ in 0..<8 {
            if model.scheduleStateForTesting.owned { model.simulateScheduledReadinessForTesting() }
            model.advanceScheduleForTesting(seconds: 6)
        }
        let playingBeforeExpiry = model.isPlaying
        let connections = model.audioRecoveryStateForTesting.connections
        let categories = model.sessionCategoriesForTesting
        model.advanceScheduleForTesting(seconds: 1.1)
        let report = try await model.diagnostics.makeHistoryReport()
        let events = try String(contentsOf: report, encoding: .utf8).split(separator: "\n").compactMap {
            try? JSONDecoder().decode(PlaybackDebugJournal.Event.self, from: Data($0.utf8))
        }.filter { $0.scheduleID == id }
        let attachment = XCTAttachment(string: events.map {
            "\($0.timestamp) \($0.name) \($0.details)"
        }.joined(separator: "\n"))
        attachment.name = "captured-speaker-category-replay"; attachment.lifetime = .keepAlways
        add(attachment)
        let failures = events.filter { $0.name == "audio_session_activation_failed" }
        print("SPEAKER_REPLAY playing=\(playingBeforeExpiry) connections=\(connections) category_failures=\(failures.count) expired=\(events.contains { $0.name == "scheduled_start_expired_without_playing" })")
        XCTAssertTrue(playingBeforeExpiry, "Already Speaker + allowed playback must start despite a rejected, unnecessary recording-category change")
        XCTAssertGreaterThan(connections, 0)
        XCTAssertFalse(categories.contains(.playAndRecord), "No speaker rerouting is needed for the captured output")
        XCTAssertTrue(failures.isEmpty)
        XCTAssertFalse(events.contains { $0.name == "scheduled_start_expired_without_playing" })
    }

    @MainActor func testRejectedCategoryOnHeadphonesStillWaitsWithoutPlayingOnWrongOutput() {
        let model = AppModel.shared
        defer { model.finishScheduleForTesting() }
        model.configureScheduleForTesting(secondsUntilStart: -1, environment: environment(route: headphones))
        XCTAssertFalse(model.isPlaying)
        XCTAssertFalse(model.scheduleStateForTesting.owned)
        XCTAssertTrue(model.scheduleStateForTesting.standby)
        XCTAssertTrue(model.sessionStateForTesting.mixing)
        XCTAssertTrue(model.sessionCategoriesForTesting.contains(.playAndRecord))
        XCTAssertEqual(model.sessionCategoriesForTesting.last, .playback)
        XCTAssertEqual(model.currentOutputRoute, headphones)
        XCTAssertEqual(model.audioRecoveryStateForTesting.connections, 0)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
    }

    @MainActor func testAlreadySpeakerStillRequiresActivationAndPreservesForegroundFocus() {
        let model = AppModel.shared
        for backgrounded in [true, false] {
            var power = environment(route: speaker)
            power.backgrounded = backgrounded; power.activationFails = true
            model.configureScheduleForTesting(secondsUntilStart: -1, environment: power)
            defer { model.finishScheduleForTesting() }
            XCTAssertFalse(model.isPlaying)
            XCTAssertFalse(model.scheduleStateForTesting.owned)
            XCTAssertEqual(model.audioRecoveryStateForTesting.connections, 0)
            XCTAssertTrue(model.sessionCategoriesForTesting.allSatisfy { $0 == .playback })
            if backgrounded { XCTAssertEqual(model.sessionStateForTesting.exclusiveAttempts, 0) }
            else { XCTAssertGreaterThan(model.sessionStateForTesting.exclusiveAttempts, 0) }
        }
    }

    @MainActor func testEstablishedSpeakerOverrideIsNotDroppedDuringReadinessOrFade() {
        let model = AppModel.shared
        var power = environment(route: headphones); power.speakerCategoryFails = false
        model.configureScheduleForTesting(secondsUntilStart: -1, environment: power)
        defer { model.finishScheduleForTesting() }
        XCTAssertTrue(model.isPlaying)
        XCTAssertTrue(model.currentOutputRoute.isBuiltInSpeaker)
        XCTAssertTrue(model.scheduleStateForTesting.speakerSession)
        model.simulateScheduledReadinessForTesting()
        model.advanceScheduleForTesting(seconds: 60)
        XCTAssertTrue(model.sessionCategoriesForTesting.allSatisfy { $0 == .playAndRecord })
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 1)
    }

    @MainActor func testAlreadySpeakerPlaybackStopsIfNewHeadphonesCannotBeRerouted() {
        let model = AppModel.shared
        model.configureScheduleForTesting(secondsUntilStart: -1, environment: environment(route: speaker))
        defer { model.finishScheduleForTesting() }
        XCTAssertTrue(model.isPlaying)
        model.simulateScheduledReadinessForTesting()
        let connections = model.audioRecoveryStateForTesting.connections
        model.advanceScheduleForTesting(seconds: 1, route: headphones)
        XCTAssertFalse(model.isPlaying)
        XCTAssertFalse(model.scheduleStateForTesting.owned)
        XCTAssertEqual(model.currentOutputRoute, headphones)
        XCTAssertTrue(model.sessionCategoriesForTesting.contains(.playAndRecord))
        XCTAssertEqual(model.audioRecoveryStateForTesting.connections, connections)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
    }

    private var speaker: ObservedAudioRoute {
        .init(ports: [.init(uid: "speaker", type: "Speaker", name: "iPhone")])
    }
    private var headphones: ObservedAudioRoute {
        .init(ports: [.init(uid: "bt:1", type: "BluetoothA2DPOutput", name: "Headphones")])
    }
    @MainActor private func environment(route: ObservedAudioRoute) -> AppModel.ScheduleTestEnvironment {
        var result = AppModel.ScheduleTestEnvironment(now: Date(timeIntervalSince1970: 1_794_245_940.548),
            uptime: 177_214.041, plugged: true, level: 0.8, route: route)
        result.backgrounded = true
        result.speakerCategoryFails = true
        return result
    }
}
#endif
