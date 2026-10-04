#if canImport(UIKit) && !canImport(KUSCCore) && DEBUG
import XCTest
@testable import KUSC_SE

/// Hosted iOS tests, not Swift Package policy tests. These invoke actual
/// AppModel actions and read the real RollingAudioEngine.volume boundary.
/// The fixture launch environment prevents station networking and audio output.
final class ScheduleModelBoundaryTests: XCTestCase {
    private var headphones: ObservedAudioRoute {
        .init(ports: [.init(uid: "bt:1", type: "BluetoothA2DP", name: "Headphones")])
    }
    private var speaker: ObservedAudioRoute {
        .init(ports: [.init(uid: "speaker", type: "Speaker", name: "iPhone")])
    }
    @MainActor private func environment(plugged: Bool = false, level: Double = 0.8) -> AppModel.ScheduleTestEnvironment {
        .init(now: Date(timeIntervalSince1970: 1_800_000_000), uptime: 5_000,
              plugged: plugged, level: level, route: headphones)
    }

    @MainActor func testSpeakerStandbySurvivesHeadphoneDisconnectAndInterruptionWithoutResumeHint() {
        let model = AppModel.shared
        model.configureScheduleForTesting(environment: environment())
        defer { model.finishScheduleForTesting() }
        XCTAssertTrue(model.scheduleStateForTesting.standby)
        model.interruptScheduledAudioForTesting()
        model.advanceScheduleForTesting(route: speaker)
        XCTAssertTrue(model.scheduleStateForTesting.exists)
        XCTAssertFalse(model.scheduleStateForTesting.notificationOnly)
        model.endAudioInterruptionForTesting(shouldResume: false)
        XCTAssertTrue(model.scheduleStateForTesting.standby)
        model.advanceScheduleForTesting(seconds: 60, route: headphones)
        XCTAssertTrue(model.scheduleStateForTesting.owned)
        XCTAssertTrue(model.currentOutputRoute.isBuiltInSpeaker)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
    }

    @MainActor func testPersistentStartIgnoresTransportAndSleepButDeletionStopsIt() {
        let model = AppModel.shared
        model.configureScheduleForTesting(options: .init(batteryOnlyStop: true), secondsUntilStart: 10,
                                           environment: environment())
        defer { model.finishScheduleForTesting() }
        model.simulateScheduledReadinessForTesting()
        model.advanceScheduleForTesting(seconds: 10)
        XCTAssertTrue(model.scheduleStateForTesting.fullGain)
        model.startSleep(minutes: 1)
        model.pauseRemote(); model.play(); model.goLive()
        model.seek(to: Date())
        model.advanceScheduleForTesting(seconds: 120)
        model.runScheduledGainCallbackForTest()
        XCTAssertTrue(model.scheduleStateForTesting.exists)
        XCTAssertTrue(model.isPlaying)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 1)
        model.cancelSchedule()
        model.advanceScheduleForTesting(seconds: 120)
        XCTAssertFalse(model.scheduleStateForTesting.exists)
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
    }

    @MainActor func testPersistentStandbyAlsoIgnoresPauseBeforePreparation() {
        let model = AppModel.shared
        model.configureScheduleForTesting(options: .init(batteryOnlyStop: true), environment: environment())
        defer { model.finishScheduleForTesting() }
        model.pauseRemote()
        XCTAssertTrue(model.scheduleStateForTesting.standby)
        XCTAssertTrue(model.scheduleStateForTesting.exists)
        model.advanceScheduleForTesting(seconds: 60)
        XCTAssertTrue(model.scheduleStateForTesting.owned)
    }

    @MainActor func testSpeakerScheduleWaitsForSessionPermissionAndRecoversWithoutEndedEvent() {
        let model = AppModel.shared
        model.configureScheduleForTesting(options: .init(batteryOnlyStop: true), secondsUntilStart: 10,
                                           environment: environment())
        defer { model.finishScheduleForTesting() }
        model.interruptScheduledAudioForTesting()
        model.advanceScheduleForTesting(seconds: 15, activationFails: true)
        XCTAssertTrue(model.scheduleStateForTesting.exists)
        XCTAssertFalse(model.scheduleStateForTesting.notificationOnly)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
        model.advanceScheduleForTesting(seconds: 5, activationFails: false)
        XCTAssertFalse(model.audioRecoveryStateForTesting.interrupted)
        model.simulateScheduledReadinessForTesting()
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
        model.advanceScheduleForTesting(seconds: 10)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 1)
    }

    @MainActor func testSilentStandbyRecoversBeforePreparationWithoutEndedEvent() {
        let model = AppModel.shared
        model.configureScheduleForTesting(secondsUntilStart: 3_600, environment: environment())
        defer { model.finishScheduleForTesting() }
        model.interruptScheduledAudioForTesting()
        model.advanceScheduleForTesting(seconds: 5, activationFails: true)
        XCTAssertFalse(model.scheduleStateForTesting.standby)
        model.advanceScheduleForTesting(seconds: 5, activationFails: false)
        XCTAssertTrue(model.scheduleStateForTesting.standby)
        XCTAssertFalse(model.scheduleStateForTesting.owned)
        XCTAssertFalse(model.scheduleStateForTesting.notificationOnly)
        XCTAssertFalse(model.audioRecoveryStateForTesting.interrupted)
    }

    @MainActor func testBatterySafeguardContinuesAfterScheduledFadeCompletes() {
        let model = AppModel.shared
        model.configureScheduleForTesting(options: .init(batteryOnlyStop: true), secondsUntilStart: 10,
                                           environment: environment())
        defer { model.finishScheduleForTesting() }
        model.simulateScheduledReadinessForTesting()
        model.advanceScheduleForTesting(seconds: 10)
        XCTAssertTrue(model.scheduleStateForTesting.fullGain)
        model.advanceScheduleForTesting(seconds: 3_600)
        XCTAssertTrue(model.isPlaying, "Long periods unplugged above the threshold must remain allowed")
        model.advanceScheduleForTesting(level: 0.24)
        model.advanceScheduleForTesting(seconds: 1_199)
        XCTAssertTrue(model.isPlaying)
        model.advanceScheduleForTesting(seconds: 1)
        XCTAssertFalse(model.isPlaying)
        XCTAssertTrue(model.scheduleStateForTesting.notificationOnly)
        XCTAssertTrue(model.scheduleStateForTesting.exists, "Battery stop must leave the request visible for deletion")
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
    }

    @MainActor func testPowerOptOutRequiresChargingAndReplugResetsLowBatteryCountdown() {
        let model = AppModel.shared
        model.configureScheduleForTesting(options: .init(), environment: environment())
        XCTAssertTrue(model.scheduleStateForTesting.notificationOnly)
        model.configureScheduleForTesting(options: .init(batteryOnlyStop: true), secondsUntilStart: 10,
                                           environment: environment(level: 0.2))
        defer { model.finishScheduleForTesting() }
        model.advanceScheduleForTesting(seconds: 1_199, plugged: true)
        XCTAssertNil(model.scheduleStateForTesting.lowSince)
        model.advanceScheduleForTesting(seconds: 2, plugged: false)
        model.advanceScheduleForTesting(seconds: 1_199)
        XCTAssertFalse(model.scheduleStateForTesting.notificationOnly)
        model.advanceScheduleForTesting(seconds: 1)
        XCTAssertTrue(model.scheduleStateForTesting.notificationOnly)
    }

    @MainActor func testSelectedOutputLossUsesOnlyTheChosenFallback() {
        let model = AppModel.shared
        defer { model.finishScheduleForTesting() }
        for fallback in [ScheduleFallback.notifyOnly, .speaker] {
            model.configureScheduleForTesting(output: .init(route: headphones, fallback: fallback),
                                               secondsUntilStart: 10, environment: environment())
            XCTAssertEqual(model.currentOutputRoute, headphones)
            let other = ObservedAudioRoute(ports: [.init(uid: "bt:2", type: "BluetoothA2DP", name: "Other headphones")])
            model.advanceScheduleForTesting(route: other)
            if fallback == .notifyOnly {
                XCTAssertTrue(model.scheduleStateForTesting.notificationOnly)
                XCTAssertFalse(model.isPlaying)
            } else {
                XCTAssertFalse(model.scheduleStateForTesting.notificationOnly)
                XCTAssertTrue(model.currentOutputRoute.isBuiltInSpeaker)
                XCTAssertTrue(model.isPlaying)
            }
        }
    }

    @MainActor func testUnchangedSpeakerRouteNotificationDoesNotRestartFullVolume() {
        let model = AppModel.shared
        model.configureScheduleForTesting(secondsUntilStart: 10, environment: environment())
        defer { model.finishScheduleForTesting() }
        model.simulateScheduledReadinessForTesting()
        model.advanceScheduleForTesting(seconds: 10)
        model.advanceScheduleForTesting(route: speaker)
        XCTAssertTrue(model.scheduleStateForTesting.fullGain)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 1)
    }

    @MainActor func testPersistentConnectionFailureKeepsRetryingPastOrdinaryTimeout() {
        let model = AppModel.shared
        model.configureScheduleForTesting(options: .init(batteryOnlyStop: true), secondsUntilStart: 10,
                                           environment: environment())
        defer { model.finishScheduleForTesting() }
        model.failScheduledConnectionForTesting()
        XCTAssertTrue(model.scheduleStateForTesting.exists)
        XCTAssertFalse(model.scheduleStateForTesting.notificationOnly)
        XCTAssertFalse(model.scheduleStateForTesting.owned)
        let previous = model.audioRecoveryStateForTesting.connections
        model.advanceScheduleForTesting(seconds: 15)
        XCTAssertTrue(model.scheduleStateForTesting.owned)
        XCTAssertGreaterThan(model.audioRecoveryStateForTesting.connections, previous)
    }

    @MainActor func testNormalSpeakerModeStillAllowsManualPause() {
        let model = AppModel.shared
        model.configureScheduleForTesting(secondsUntilStart: 10, environment: environment())
        defer { model.finishScheduleForTesting() }
        model.pauseRemote()
        model.advanceScheduleForTesting(seconds: 60)
        XCTAssertFalse(model.scheduleStateForTesting.exists)
        XCTAssertFalse(model.isPlaying)
    }

    @MainActor func testDeletingDuringInterruptionRejectsLateResumeAndRouteEvents() {
        let model = AppModel.shared
        model.configureScheduleForTesting(options: .init(batteryOnlyStop: true), secondsUntilStart: 10,
                                           environment: environment())
        defer { model.finishScheduleForTesting() }
        model.interruptScheduledAudioForTesting()
        model.cancelSchedule()
        let connections = model.audioRecoveryStateForTesting.connections
        model.endAudioInterruptionForTesting(shouldResume: true)
        model.advanceScheduleForTesting(seconds: 120, route: headphones)
        XCTAssertFalse(model.scheduleStateForTesting.exists)
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(model.audioRecoveryStateForTesting.connections, connections)
    }

    @MainActor func testOrdinaryAudioResumesBeforeFutureSpeakerScheduleIsDue() {
        let model = AppModel.shared
        model.configureScheduleForTesting(environment: environment())
        defer { model.finishScheduleForTesting() }
        model.play()
        model.interruptScheduledAudioForTesting()
        model.endAudioInterruptionForTesting(shouldResume: true)
        XCTAssertTrue(model.isPlaying)
        XCTAssertTrue(model.scheduleStateForTesting.exists)
        XCTAssertFalse(model.scheduleStateForTesting.owned)
        XCTAssertEqual(model.currentOutputRoute, headphones)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 1)
    }

    @MainActor func testCancelingSleepCannotUnmuteTheRealScheduledGainBoundary() {
        let model = AppModel.shared
        model.configureScheduledGainBoundaryTest(schedule: 0, sleep: 0.4)
        model.cancelSleep()
        let result = model.scheduledGainBoundaryState
        XCTAssertTrue(result.wantsPlayback)
        XCTAssertTrue(result.ownsPlayback)
        XCTAssertTrue(result.hasSchedule)
        XCTAssertEqual(result.gain, 0)
        XCTAssertTrue(result.trace.allSatisfy { $0 == 0 })
        model.cancelSchedule()
    }

    @MainActor func testPausingSleepCannotRestoreFullGainDuringPreroll() {
        let model = AppModel.shared
        model.configureScheduledGainBoundaryTest(schedule: 0, sleep: 0.25)
        model.choosePausedTimer(.pauseTimer)
        let result = model.scheduledGainBoundaryState
        XCTAssertTrue(result.ownsPlayback)
        XCTAssertEqual(result.gain, 0)
        XCTAssertTrue(result.trace.allSatisfy { $0 == 0 })
        model.cancelSchedule()
    }

    @MainActor func testScheduleCancelMutesBeforeResettingItsEnvelope() {
        let model = AppModel.shared
        model.configureScheduledGainBoundaryTest(schedule: 0.5, sleep: 0.4)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0.2, accuracy: 0.0001)
        let setupSamples = model.scheduledGainBoundaryState.trace.count
        model.cancelSchedule()
        let result = model.scheduledGainBoundaryState
        XCTAssertFalse(result.wantsPlayback)
        XCTAssertFalse(result.ownsPlayback)
        XCTAssertFalse(result.hasSchedule)
        XCTAssertEqual(result.gain, 0)
        let cancelTrace = result.trace.dropFirst(setupSamples)
        XCTAssertFalse(cancelTrace.isEmpty)
        XCTAssertTrue(cancelTrace.allSatisfy { $0 == 0 }, "Every model-to-engine gain write during cancellation must remain muted")
    }

    @MainActor func testLateGainCallbackCannotResumeAfterManualPause() {
        let model = AppModel.shared
        model.configureScheduledGainBoundaryTest(schedule: 0, sleep: 1)
        model.pauseRemote()
        model.runScheduledGainCallbackForTest()
        let result = model.scheduledGainBoundaryState
        XCTAssertFalse(result.wantsPlayback)
        XCTAssertFalse(result.ownsPlayback)
        XCTAssertFalse(result.hasSchedule)
        XCTAssertEqual(result.gain, 0)
        XCTAssertTrue(result.trace.allSatisfy { $0 == 0 })
    }
}
#endif
