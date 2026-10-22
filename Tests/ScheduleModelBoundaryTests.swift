#if canImport(UIKit) && !canImport(KUSCCore) && DEBUG
import XCTest
import UserNotifications
@testable import KUSC_SE

/// Hosted iOS tests, not Swift Package policy tests. These invoke actual
/// AppModel actions and read the real RollingAudioEngine.volume boundary.
/// The fixture launch environment prevents station networking and audio output.
final class ScheduleModelBoundaryTests: XCTestCase {
    @MainActor func testInterruptedScheduleExpiryKeepsSpeakerOnAutomaticResumeUntilManualPlay() {
        let model = AppModel.shared
        model.configureScheduleForTesting(options: .init(batteryOnlyStop: true),
                                           secondsUntilStart: 10, environment: environment())
        defer { model.finishScheduleForTesting() }
        model.advanceScheduleForTesting(seconds: 10)
        model.simulateScheduledReadinessForTesting()
        model.advanceScheduleForTesting(seconds: 599)
        model.interruptScheduledAudioForTesting()
        model.advanceScheduleForTesting(seconds: 1, activationFails: true)
        XCTAssertFalse(model.scheduleStateForTesting.exists)
        model.advanceScheduleForTesting(seconds: 5, route: headphones, activationFails: false)
        XCTAssertFalse(model.audioRecoveryStateForTesting.interrupted)
        XCTAssertTrue(model.scheduleStateForTesting.speakerSession)
        XCTAssertTrue(model.currentOutputRoute.isBuiltInSpeaker)
        model.simulateScheduledReadinessForTesting()
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
        model.advanceScheduleForTesting(seconds: 30)
        model.runScheduledGainCallbackForTest()
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0.5, accuracy: 0.001)
        model.pauseRemote()
        model.play()
        XCTAssertFalse(model.scheduleStateForTesting.speakerSession, "Explicit Play releases the old schedule's route policy")
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 1)
    }

    @MainActor func testScheduleExpiryDuringStallKeepsSpeakerAndBatteryProtection() {
        let model = AppModel.shared
        model.configureScheduleForTesting(options: .init(batteryOnlyStop: true, lowBatteryMinutes: 1),
                                           secondsUntilStart: 10, environment: environment())
        defer { model.finishScheduleForTesting() }
        model.advanceScheduleForTesting(seconds: 10)
        model.simulateScheduledReadinessForTesting()
        model.advanceScheduleForTesting(seconds: 599)
        model.receiveScheduledSnapshotForTesting(ready: false)
        model.advanceScheduleForTesting(seconds: 1)
        XCTAssertFalse(model.scheduleStateForTesting.exists)
        XCTAssertTrue(model.isPlaying)
        XCTAssertTrue(model.scheduleStateForTesting.speakerSession, "A stalled completed start still owns its speaker session")
        model.simulateScheduledReadinessForTesting()
        model.advanceScheduleForTesting(level: 0.24)
        model.advanceScheduleForTesting(seconds: 59)
        XCTAssertTrue(model.isPlaying)
        model.advanceScheduleForTesting(seconds: 1)
        XCTAssertFalse(model.isPlaying, "Expiry cannot remove battery protection during a temporary stall")
    }

    @MainActor func testStalledLateFadeGetsFullMinuteAfterScheduleExpires() {
        let model = AppModel.shared
        model.configureScheduleForTesting(secondsUntilStart: 10, environment: environment())
        defer { model.finishScheduleForTesting() }
        model.advanceScheduleForTesting(seconds: 600)
        model.simulateScheduledReadinessForTesting()
        model.advanceScheduleForTesting(seconds: 5)
        model.receiveScheduledSnapshotForTesting(ready: false)
        model.advanceScheduleForTesting(seconds: 5)
        XCTAssertFalse(model.scheduleStateForTesting.exists)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
        model.advanceScheduleForTesting(seconds: 120)
        model.simulateScheduledReadinessForTesting()
        model.runScheduledGainCallbackForTest()
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
        model.advanceScheduleForTesting(seconds: 30)
        model.runScheduledGainCallbackForTest()
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0.5, accuracy: 0.001)
        model.advanceScheduleForTesting(seconds: 30)
        model.runScheduledGainCallbackForTest()
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 1)
        XCTAssertNil(model.schedulePhase)
    }

    @MainActor func testStallAfterScheduleExpiryDoesNotConsumeRemainingFade() {
        let model = AppModel.shared
        model.configureScheduleForTesting(secondsUntilStart: 10, environment: environment())
        defer { model.finishScheduleForTesting() }
        model.advanceScheduleForTesting(seconds: 600)
        model.simulateScheduledReadinessForTesting()
        model.advanceScheduleForTesting(seconds: 10)
        model.runScheduledGainCallbackForTest()
        XCTAssertFalse(model.scheduleStateForTesting.exists)
        model.receiveScheduledSnapshotForTesting(ready: false)
        model.runScheduledGainCallbackForTest()
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
        model.advanceScheduleForTesting(seconds: 120)
        model.simulateScheduledReadinessForTesting()
        model.runScheduledGainCallbackForTest()
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
        model.advanceScheduleForTesting(seconds: 30)
        model.runScheduledGainCallbackForTest()
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0.5, accuracy: 0.001)
        model.pauseRemote()
        model.advanceScheduleForTesting(seconds: 120)
        model.runScheduledGainCallbackForTest()
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
        model.play()
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 1, "Explicit Play still overrides the old schedule's fade")
    }

    @MainActor func testUnstartedScheduleExpiresAtTenMinutesAndCannotBeRevived() {
        let model = AppModel.shared
        model.configureScheduleForTesting(options: .init(batteryOnlyStop: true), secondsUntilStart: 10, environment: environment())
        defer { model.finishScheduleForTesting() }
        let id = model.scheduleIDForTesting
        model.advanceScheduleForTesting(seconds: 609)
        XCTAssertTrue(model.scheduleStateForTesting.exists)
        model.advanceScheduleForTesting(seconds: 1)
        XCTAssertFalse(model.scheduleStateForTesting.exists)
        XCTAssertFalse(model.isPlaying)
        XCTAssertNil(model.scheduleDescription)
        XCTAssertNil(model.schedulePhase)
        model.startFromNotification(requestID: id)
        model.reloadScheduleForTesting()
        XCTAssertFalse(model.isPlaying)
        XCTAssertFalse(model.scheduleStateForTesting.exists)
        XCTAssertNotEqual(model.state, .scheduledFadeIn)
    }

    @MainActor func testCompletedScheduleExpiresWithoutInterruptingAudio() {
        let model = AppModel.shared
        model.configureScheduleForTesting(secondsUntilStart: 10, environment: environment())
        defer { model.finishScheduleForTesting() }
        model.advanceScheduleForTesting(seconds: 10)
        model.simulateScheduledReadinessForTesting()
        model.advanceScheduleForTesting(seconds: 60)
        let generation = model.audioRecoveryStateForTesting.engineGeneration
        model.advanceScheduleForTesting(seconds: 540)
        XCTAssertFalse(model.scheduleStateForTesting.exists)
        XCTAssertTrue(model.isPlaying)
        XCTAssertNil(model.scheduleDescription)
        XCTAssertNil(model.schedulePhase)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 1)
        XCTAssertEqual(model.audioRecoveryStateForTesting.engineGeneration, generation)
        XCTAssertEqual(model.state, .playingLive)
    }

    @MainActor func testLateFadeKeepsItsFullMinuteAcrossScheduleExpiry() {
        let model = AppModel.shared
        model.configureScheduleForTesting(secondsUntilStart: 10, environment: environment())
        defer { model.finishScheduleForTesting() }
        model.advanceScheduleForTesting(seconds: 600) // Ten seconds remain in the grace period.
        model.simulateScheduledReadinessForTesting()
        model.advanceScheduleForTesting(seconds: 10)
        model.runScheduledGainCallbackForTest()
        XCTAssertFalse(model.scheduleStateForTesting.exists)
        XCTAssertTrue(model.isPlaying)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 1.0 / 6, accuracy: 0.001)
        model.advanceScheduleForTesting(seconds: 20)
        model.runScheduledGainCallbackForTest()
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0.5, accuracy: 0.001)
        model.advanceScheduleForTesting(seconds: 30)
        model.runScheduledGainCallbackForTest()
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 1)
    }

    @MainActor func testStallClearsFadingLabelAndReadinessRestartsFullMinute() {
        let model = AppModel.shared
        model.configureScheduleForTesting(secondsUntilStart: 10, environment: environment())
        defer { model.finishScheduleForTesting() }
        model.advanceScheduleForTesting(seconds: 10)
        model.simulateScheduledReadinessForTesting()
        model.advanceScheduleForTesting(seconds: 30)
        XCTAssertEqual(model.state, .scheduledFadeIn)
        model.receiveScheduledSnapshotForTesting(ready: false)
        XCTAssertNotEqual(model.state, .scheduledFadeIn)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
        model.advanceScheduleForTesting(seconds: 180)
        model.simulateScheduledReadinessForTesting()
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
        model.advanceScheduleForTesting(seconds: 30)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0.5, accuracy: 0.001)
        model.advanceScheduleForTesting(seconds: 30)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 1)
        model.reloadScheduleForTesting()
        XCTAssertFalse(model.scheduleStateForTesting.exists, "Reopening cannot re-arm a start that already played")
        XCTAssertNotEqual(model.state, .scheduledFadeIn)
    }

    @MainActor func testPausedAndNotificationOnlySchedulesAlsoExpire() {
        let model = AppModel.shared
        defer { model.finishScheduleForTesting() }
        for blockedByPower in [false, true] {
            model.configureScheduleForTesting(options: .init(allowOnBattery: !blockedByPower), secondsUntilStart: 10, environment: environment())
            if !blockedByPower { model.pauseRemote() }
            model.advanceScheduleForTesting(seconds: 611)
            XCTAssertFalse(model.scheduleStateForTesting.exists)
            XCTAssertFalse(model.isPlaying)
            XCTAssertNil(model.scheduleDescription)
        }
    }
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
        XCTAssertEqual(model.currentOutputRoute, headphones)
        XCTAssertTrue(model.sessionStateForTesting.mixing)
        model.advanceScheduleForTesting(seconds: 60)
        XCTAssertTrue(model.currentOutputRoute.isBuiltInSpeaker)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
    }

    @MainActor func testPersistentStartHonorsPauseWithoutCancellationAndStillIgnoresSleep() {
        let model = AppModel.shared
        model.configureScheduleForTesting(options: .init(batteryOnlyStop: true), secondsUntilStart: 10,
                                           environment: environment())
        defer { model.finishScheduleForTesting() }
        model.advanceScheduleForTesting(seconds: 10)
        model.simulateScheduledReadinessForTesting()
        model.advanceScheduleForTesting(seconds: 60)
        XCTAssertTrue(model.scheduleStateForTesting.fullGain)
        model.startSleep(minutes: 1)
        model.pauseRemote()
        XCTAssertFalse(model.isPlaying)
        XCTAssertTrue(model.scheduleStateForTesting.exists)
        model.advanceScheduleForTesting(seconds: 120, route: headphones)
        model.interruptScheduledAudioForTesting()
        model.endAudioInterruptionForTesting(shouldResume: true)
        model.runScheduledGainCallbackForTest()
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
        model.play(); model.goLive()
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

    @MainActor func testPersistentFutureStartAllowsPlayPauseAndStillRunsAtTheDeadline() {
        let model = AppModel.shared
        model.configureScheduleForTesting(options: .init(batteryOnlyStop: true), environment: environment())
        defer { model.finishScheduleForTesting() }
        model.play()
        XCTAssertTrue(model.isPlaying)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 1)
        XCTAssertEqual(model.currentOutputRoute, headphones)
        model.pauseRemote()
        XCTAssertFalse(model.isPlaying)
        XCTAssertTrue(model.scheduleStateForTesting.standby)
        XCTAssertTrue(model.scheduleStateForTesting.exists)
        model.advanceScheduleForTesting(seconds: 60)
        XCTAssertFalse(model.isPlaying)
        model.advanceScheduleForTesting(seconds: 60)
        XCTAssertTrue(model.scheduleStateForTesting.owned)
        XCTAssertTrue(model.isPlaying)
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
        model.advanceScheduleForTesting(seconds: 60)
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
        model.advanceScheduleForTesting(seconds: 10)
        model.simulateScheduledReadinessForTesting()
        model.advanceScheduleForTesting(seconds: 60)
        XCTAssertTrue(model.scheduleStateForTesting.fullGain)
        model.advanceScheduleForTesting(seconds: 3_600)
        XCTAssertTrue(model.isPlaying, "Long periods unplugged above the threshold must remain allowed")
        model.advanceScheduleForTesting(level: 0.24)
        model.advanceScheduleForTesting(seconds: 1_199)
        XCTAssertTrue(model.isPlaying)
        model.advanceScheduleForTesting(seconds: 1)
        XCTAssertFalse(model.isPlaying)
        XCTAssertFalse(model.scheduleStateForTesting.notificationOnly)
        XCTAssertFalse(model.scheduleStateForTesting.exists, "Battery protection must outlive the completed request")
        XCTAssertFalse(model.scheduleStateForTesting.speakerSession)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
    }

    @MainActor func testPowerOptOutRequiresChargingAndReplugResetsLowBatteryCountdown() {
        let model = AppModel.shared
        model.configureScheduleForTesting(options: .init(), environment: environment())
        XCTAssertTrue(model.scheduleStateForTesting.notificationOnly)
        model.configureScheduleForTesting(options: .init(batteryOnlyStop: true), secondsUntilStart: 3_600,
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
            model.advanceScheduleForTesting(seconds: 10, route: other)
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
        model.advanceScheduleForTesting(seconds: 10)
        model.simulateScheduledReadinessForTesting()
        model.advanceScheduleForTesting(seconds: 60)
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

    @MainActor func testPauseDuringPreparationStaysSilentUntilTheScheduledDeadline() {
        let model = AppModel.shared
        model.configureScheduleForTesting(secondsUntilStart: 10, environment: environment())
        defer { model.finishScheduleForTesting() }
        model.pauseRemote()
        model.advanceScheduleForTesting(seconds: 9)
        XCTAssertTrue(model.scheduleStateForTesting.exists)
        XCTAssertFalse(model.isPlaying)
        model.runScheduledGainCallbackForTest()
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
        model.advanceScheduleForTesting(seconds: 1)
        XCTAssertTrue(model.isPlaying)
        XCTAssertTrue(model.scheduleStateForTesting.exists)
    }

    @MainActor func testNormalPauseAfterScheduledFadePreservesTheRewindTransport() {
        let model = AppModel.shared
        model.configureScheduleForTesting(secondsUntilStart: 10, environment: environment())
        defer { model.finishScheduleForTesting() }
        model.advanceScheduleForTesting(seconds: 10)
        model.simulateScheduledReadinessForTesting()
        model.advanceScheduleForTesting(seconds: 60)
        let before = model.audioRecoveryStateForTesting.engineGeneration
        XCTAssertTrue(model.scheduleStateForTesting.fullGain)
        model.pauseRemote()
        XCTAssertTrue(model.scheduleStateForTesting.exists)
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
        XCTAssertEqual(model.audioRecoveryStateForTesting.engineGeneration, before,
                       "A normal Pause must not stop and discard the retained transport after the scheduled fade")
        XCTAssertTrue(model.audioRecoveryStateForTesting.started)
        model.advanceScheduleForTesting(seconds: 120, route: headphones)
        XCTAssertFalse(model.isPlaying)
        model.play()
        XCTAssertTrue(model.isPlaying)
        XCTAssertTrue(model.scheduleStateForTesting.exists)
    }

    @MainActor func testManualPlayDuringPausedPrerollDoesNotWaitForTheScheduledFade() {
        let model = AppModel.shared
        model.configureScheduleForTesting(options: .init(batteryOnlyStop: true), secondsUntilStart: 30,
                                           environment: environment())
        defer { model.finishScheduleForTesting() }
        model.pauseRemote()
        model.play()
        model.simulateScheduledReadinessForTesting()
        XCTAssertTrue(model.isPlaying)
        XCTAssertTrue(model.scheduleStateForTesting.exists)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 1)
    }

    @MainActor func testRelaunchedFuturePersistentStartDoesNotBlockManualPlay() {
        let model = AppModel.shared
        model.configureScheduleForTesting(options: .init(batteryOnlyStop: true), environment: environment())
        defer { model.finishScheduleForTesting() }
        model.play(); model.pauseRemote()
        model.reloadScheduleForTesting()
        XCTAssertFalse(model.isPlaying)
        model.play()
        XCTAssertTrue(model.isPlaying)
        XCTAssertTrue(model.scheduleStateForTesting.exists)
        XCTAssertFalse(model.scheduleStateForTesting.owned)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 1)
    }

    @MainActor func testRelaunchedExpiredPersistentStartHonorsSavedPauseUntilPlay() {
        let model = AppModel.shared
        model.configureScheduleForTesting(options: .init(batteryOnlyStop: true), secondsUntilStart: 10,
                                           environment: environment())
        defer { model.finishScheduleForTesting() }
        model.advanceScheduleForTesting(seconds: 10)
        model.simulateScheduledReadinessForTesting()
        model.advanceScheduleForTesting(seconds: 60)
        model.pauseRemote()
        model.reloadScheduleForTesting()
        model.advanceScheduleForTesting(seconds: 120, route: headphones)
        XCTAssertFalse(model.isPlaying)
        XCTAssertFalse(model.scheduleStateForTesting.exists)
        model.play()
        model.simulateScheduledReadinessForTesting()
        XCTAssertTrue(model.isPlaying)
        XCTAssertEqual(model.currentOutputRoute, headphones)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 1)
    }

    @MainActor func testFutureNotificationOnlyStartDoesNotBlockOrdinaryPlayWhileUnplugged() {
        let model = AppModel.shared
        model.configureScheduleForTesting(options: .init(allowOnBattery: false), environment: environment())
        defer { model.finishScheduleForTesting() }
        model.reloadScheduleForTesting()
        XCTAssertTrue(model.scheduleStateForTesting.notificationOnly)
        model.play()
        XCTAssertTrue(model.isPlaying)
        XCTAssertTrue(model.scheduleStateForTesting.exists)
        XCTAssertFalse(model.scheduleStateForTesting.owned)
        XCTAssertEqual(model.currentOutputRoute, headphones)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 1)
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

    @MainActor func testStandbyAndPrerollMixUntilTheScheduledTimeThenTakeFocus() {
        let model = AppModel.shared
        var power = environment()
        power.otherAudioPlaying = true
        model.configureScheduleForTesting(environment: power)
        defer { model.finishScheduleForTesting() }
        XCTAssertTrue(model.sessionStateForTesting.mixing)
        XCTAssertEqual(model.sessionStateForTesting.exclusiveAttempts, 0)
        model.advanceScheduleForTesting(seconds: 60)
        model.simulateScheduledReadinessForTesting()
        model.advanceScheduleForTesting(seconds: 59)
        XCTAssertEqual(model.currentOutputRoute, headphones)
        XCTAssertEqual(model.sessionStateForTesting.exclusiveAttempts, 0)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
        model.advanceScheduleForTesting(seconds: 1)
        XCTAssertFalse(model.sessionStateForTesting.mixing)
        XCTAssertTrue(model.currentOutputRoute.isBuiltInSpeaker)
        XCTAssertGreaterThan(model.sessionStateForTesting.exclusiveAttempts, 0)
        model.simulateScheduledReadinessForTesting()
        model.advanceScheduleForTesting(seconds: 30)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0.5, accuracy: 0.001)
        model.advanceScheduleForTesting(seconds: 30)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 1)
    }

    @MainActor func testDelayedScheduledTakeoverCannotSkipTheFullMinuteFade() {
        let model = AppModel.shared
        defer { model.finishScheduleForTesting() }
        for output in [ScheduledOutputPreference.speaker, .init(route: headphones), .currentOutput] {
            for delay in [0.0, 9.0, 35.0, 500.0] {
                model.configureScheduleForTesting(output: output, secondsUntilStart: 10, environment: environment(plugged: true))
                model.simulateScheduledReadinessForTesting() // Ready during muted preroll.
                model.advanceScheduleForTesting(seconds: 10 + delay)
                XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0,
                               "Takeover must discard readiness from the old mixable session")
                XCTAssertFalse(model.scheduleStateForTesting.fullGain)
                model.simulateScheduledReadinessForTesting() // Fresh sample on the chosen output.
                XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
                model.advanceScheduleForTesting(seconds: 30)
                XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0.5, accuracy: 0.001)
                model.advanceScheduleForTesting(seconds: 30)
                XCTAssertEqual(model.scheduledGainBoundaryState.gain, 1)
                model.finishScheduleForTesting()
            }
        }
    }

    @MainActor func testReadinessAfterTakeoverGetsAFullFadeInsteadOfRemainingDeadline() {
        let model = AppModel.shared
        model.configureScheduleForTesting(secondsUntilStart: 10, environment: environment())
        defer { model.finishScheduleForTesting() }
        model.advanceScheduleForTesting(seconds: 10)
        model.advanceScheduleForTesting(seconds: 9) // Audio is still waiting after session takeover.
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
        model.simulateScheduledReadinessForTesting()
        model.advanceScheduleForTesting(seconds: 6)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0.1, accuracy: 0.001)
        model.advanceScheduleForTesting(seconds: 24)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0.5, accuracy: 0.001)
        model.advanceScheduleForTesting(seconds: 30)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 1)
    }

    @MainActor func testFutureScheduleDoesNotTakeAudioBackFromAnotherApp() {
        let model = AppModel.shared
        model.configureScheduleForTesting(secondsUntilStart: 180, environment: environment())
        defer { model.finishScheduleForTesting() }
        model.play()
        let exclusive = model.sessionStateForTesting.exclusiveAttempts
        model.interruptScheduledAudioForTesting()
        model.advanceScheduleForTesting(seconds: 5, otherAudioPlaying: true)
        model.advanceScheduleForTesting(seconds: 60)
        XCTAssertTrue(model.sessionStateForTesting.mixing)
        XCTAssertEqual(model.sessionStateForTesting.exclusiveAttempts, exclusive)
        XCTAssertTrue(model.scheduleStateForTesting.exists)
        XCTAssertFalse(model.isAudible)
        model.advanceScheduleForTesting(seconds: 115)
        XCTAssertGreaterThan(model.sessionStateForTesting.exclusiveAttempts, exclusive)
        XCTAssertTrue(model.currentOutputRoute.isBuiltInSpeaker)
    }

    @MainActor func testPlayOverridesStaleInterruptionAndAutomaticPowerRestrictions() {
        let model = AppModel.shared
        var power = environment(level: 0.1)
        power.otherAudioPlaying = true
        model.configureScheduleForTesting(options: .init(allowOnBattery: false), secondsUntilStart: -1, environment: power)
        defer { model.finishScheduleForTesting() }
        model.interruptScheduledAudioForTesting()
        model.play()
        XCTAssertFalse(model.audioRecoveryStateForTesting.interrupted)
        XCTAssertTrue(model.isPlaying)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 1)
        model.advanceScheduleForTesting(seconds: 10)
        XCTAssertTrue(model.isPlaying, "Automatic schedule policy must not undo explicit Play")
        model.pauseRemote()
        model.advanceScheduleForTesting(seconds: 30)
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
    }

    @MainActor func testSelectedOutputStandbySurvivesOtherAppAndTakesFocusAtTarget() {
        let model = AppModel.shared
        model.configureScheduleForTesting(output: .init(route: headphones, fallback: .notifyOnly),
                                           secondsUntilStart: 180, environment: environment())
        defer { model.finishScheduleForTesting() }
        model.interruptScheduledAudioForTesting()
        model.advanceScheduleForTesting(seconds: 5, otherAudioPlaying: true)
        XCTAssertTrue(model.sessionStateForTesting.mixing)
        XCTAssertFalse(model.scheduleStateForTesting.notificationOnly)
        model.advanceScheduleForTesting(seconds: 175)
        XCTAssertGreaterThan(model.sessionStateForTesting.exclusiveAttempts, 0)
        XCTAssertEqual(model.currentOutputRoute, headphones)
        XCTAssertTrue(model.scheduleStateForTesting.owned)
    }

    @MainActor func testExplicitPlayRetriesEveryFiveSecondsAndPauseCancelsRetries() {
        let model = AppModel.shared
        model.configureScheduleForTesting(secondsUntilStart: 3_600, environment: environment())
        defer { model.finishScheduleForTesting() }
        model.advanceScheduleForTesting(activationFails: true)
        model.interruptScheduledAudioForTesting()
        model.play()
        let first = model.sessionStateForTesting.exclusiveAttempts
        for _ in 0..<12 {
            let previous = model.sessionStateForTesting.exclusiveAttempts
            model.advanceScheduleForTesting(seconds: 4)
            XCTAssertEqual(model.sessionStateForTesting.exclusiveAttempts, previous)
            model.advanceScheduleForTesting(seconds: 1)
            XCTAssertEqual(model.sessionStateForTesting.exclusiveAttempts, previous + 1)
        }
        XCTAssertEqual(model.sessionStateForTesting.exclusiveAttempts, first + 12)
        model.advanceScheduleForTesting(seconds: 14)
        XCTAssertEqual(model.sessionStateForTesting.exclusiveAttempts, first + 12)
        model.advanceScheduleForTesting(seconds: 1, activationFails: false)
        XCTAssertFalse(model.audioRecoveryStateForTesting.interrupted)
        XCTAssertTrue(model.isPlaying)
        model.pauseRemote()
        let stopped = model.sessionStateForTesting.exclusiveAttempts
        model.advanceScheduleForTesting(seconds: 30)
        XCTAssertEqual(model.sessionStateForTesting.exclusiveAttempts, stopped)
        XCTAssertFalse(model.isPlaying)
    }

    @MainActor func testChangedOutputRetriesPendingExplicitPlayImmediately() {
        let model = AppModel.shared
        model.configureScheduleForTesting(environment: environment())
        defer { model.finishScheduleForTesting() }
        model.advanceScheduleForTesting(activationFails: true)
        model.play()
        XCTAssertTrue(model.audioRecoveryStateForTesting.interrupted)
        model.advanceScheduleForTesting(route: speaker, activationFails: false)
        XCTAssertFalse(model.audioRecoveryStateForTesting.interrupted)
        XCTAssertTrue(model.isPlaying)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 1)
    }

    @MainActor func testHeadsUpReminderUsesTwoMinuteLeadAndOpensCancellationWithoutPlaying() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let request = ScheduledStartRequest(date: now.addingTimeInterval(600), output: .speaker)
        let reminder = NotificationCoordinator.shared.headsUpNotification(request, now: now)
        XCTAssertEqual((reminder.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval, 480)
        XCTAssertEqual(reminder.content.userInfo["action"] as? String, "manage-schedule")
        XCTAssertEqual(reminder.content.userInfo["scheduleID"] as? String, request.id.uuidString)
        let short = ScheduledStartRequest(date: now.addingTimeInterval(30))
        XCTAssertEqual((NotificationCoordinator.shared.headsUpNotification(short, now: now).trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval, 1)
        let model = AppModel.shared
        model.configureScheduleForTesting(environment: environment())
        defer { model.finishScheduleForTesting() }
        model.openScheduleCancellation(requestID: UUID())
        XCTAssertNil(model.scheduleManagementRequest)
        model.openScheduleCancellation(requestID: model.scheduleIDForTesting)
        XCTAssertNotNil(model.scheduleManagementRequest)
        XCTAssertTrue(model.scheduleStateForTesting.exists)
        XCTAssertFalse(model.isPlaying)
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

    @MainActor func testManualPlaybackRecoversDuringFinalMinuteAndAfterSavedStart() {
        let model = AppModel.shared
        for secondsUntilStart in [TimeInterval(30), -30] {
            model.configureScheduleForTesting(secondsUntilStart: secondsUntilStart, environment: environment())
            model.play()
            model.interruptScheduledAudioForTesting()
            model.endAudioInterruptionForTesting(shouldResume: true)
            XCTAssertFalse(model.audioRecoveryStateForTesting.interrupted)
            XCTAssertTrue(model.isPlaying)
            XCTAssertEqual(model.scheduledGainBoundaryState.gain, 1)
            XCTAssertFalse(model.scheduleStateForTesting.owned)
            model.finishScheduleForTesting()
        }
    }

    @MainActor func testCancelingSleepCannotUnmuteTheRealScheduledGainBoundary() {
        let model = AppModel.shared
        model.configureScheduledGainBoundaryTest(schedule: 0, sleep: 0.4)
        defer { model.finishScheduleForTesting() }
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
        defer { model.finishScheduleForTesting() }
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
        defer { model.finishScheduleForTesting() }
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
        defer { model.finishScheduleForTesting() }
        model.pauseRemote()
        model.runScheduledGainCallbackForTest()
        let result = model.scheduledGainBoundaryState
        XCTAssertFalse(result.wantsPlayback)
        XCTAssertTrue(result.ownsPlayback)
        XCTAssertTrue(result.hasSchedule)
        XCTAssertEqual(result.gain, 0)
        XCTAssertTrue(result.trace.allSatisfy { $0 == 0 })
        model.cancelSchedule()
    }
}
#endif
