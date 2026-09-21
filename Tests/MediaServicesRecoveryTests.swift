#if canImport(UIKit) && !canImport(KUSCCore) && DEBUG
import XCTest
@testable import KUSC_SE

/// Hosted coordinator regressions. Only the network/session-start boundary is
/// intercepted; resets still invalidate the real engine and its transport clock.
final class MediaServicesRecoveryTests: XCTestCase {
    @MainActor func testPausedResetClearsObsoleteTransportAndNextPlayReconnects() {
        let model = AppModel.shared
        model.configureAudioRecoveryForTesting(playing: false)
        defer { model.finishAudioRecoveryForTesting() }
        let before = model.audioRecoveryStateForTesting

        model.resetMediaServicesForTesting()

        let reset = model.audioRecoveryStateForTesting
        XCTAssertNotEqual(reset.engineGeneration, before.engineGeneration)
        XCTAssertNotEqual(reset.connectionGeneration, before.connectionGeneration)
        XCTAssertFalse(reset.started)
        XCTAssertEqual(reset.connections, 0)
        XCTAssertFalse(model.isPlaying)
        XCTAssertNil(reset.pausedAt)
        XCTAssertNil(model.bufferWindow)
        XCTAssertNil(model.transportClock.sample.heardAt)
        XCTAssertEqual(model.state, .pausedLive)
        XCTAssertTrue(model.scheduledGainBoundaryState.trace.allSatisfy { $0 == 0 })

        model.play()
        XCTAssertTrue(model.isPlaying)
        XCTAssertTrue(model.audioRecoveryStateForTesting.started)
        XCTAssertEqual(model.audioRecoveryStateForTesting.connections, 1)
        XCTAssertEqual(model.state, .connecting)
    }

    @MainActor func testResetDuringInterruptionWaitsForRecommendedResumeThenReconnects() {
        let model = AppModel.shared
        model.configureAudioRecoveryForTesting(playing: true, interrupted: true)
        defer { model.finishAudioRecoveryForTesting() }

        model.resetMediaServicesForTesting()
        XCTAssertTrue(model.isPlaying)
        XCTAssertTrue(model.audioRecoveryStateForTesting.interrupted)
        XCTAssertFalse(model.audioRecoveryStateForTesting.started)
        XCTAssertEqual(model.audioRecoveryStateForTesting.connections, 0)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
        XCTAssertEqual(model.state, .interrupted)

        model.endAudioInterruptionForTesting(shouldResume: true)
        XCTAssertFalse(model.audioRecoveryStateForTesting.interrupted)
        XCTAssertEqual(model.audioRecoveryStateForTesting.connections, 1)
        XCTAssertTrue(model.isPlaying)
        XCTAssertEqual(model.state, .connecting)
    }

    @MainActor func testResetDuringInterruptionDoesNotRestartWhenResumeIsDenied() {
        let model = AppModel.shared
        model.configureAudioRecoveryForTesting(playing: true, interrupted: true)
        defer { model.finishAudioRecoveryForTesting() }

        model.resetMediaServicesForTesting()
        model.endAudioInterruptionForTesting(shouldResume: false)

        XCTAssertFalse(model.isPlaying)
        XCTAssertFalse(model.audioRecoveryStateForTesting.started)
        XCTAssertEqual(model.audioRecoveryStateForTesting.connections, 0)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
        XCTAssertTrue(model.scheduledGainBoundaryState.trace.allSatisfy { $0 == 0 })
    }

    @MainActor func testActiveScheduledResetPreservesRequestAndMutesBeforeRestart() {
        let model = AppModel.shared
        model.configureAudioRecoveryForTesting(playing: true, scheduled: true)
        defer { model.finishAudioRecoveryForTesting() }
        let priorSamples = model.scheduledGainBoundaryState.trace.count
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0.4)

        model.resetMediaServicesForTesting()

        let gain = model.scheduledGainBoundaryState
        XCTAssertTrue(gain.hasSchedule)
        XCTAssertTrue(gain.ownsPlayback)
        XCTAssertTrue(gain.wantsPlayback)
        XCTAssertEqual(gain.gain, 0)
        let resetTrace = gain.trace.dropFirst(priorSamples)
        XCTAssertFalse(resetTrace.isEmpty)
        XCTAssertTrue(resetTrace.allSatisfy { $0 == 0 })
        XCTAssertEqual(model.audioRecoveryStateForTesting.connections, 1)
    }

    @MainActor func testPendingScheduleSurvivesPausedResetWithoutStartingPlayback() {
        let model = AppModel.shared
        model.configureAudioRecoveryForTesting(playing: false, scheduled: true)
        defer { model.finishAudioRecoveryForTesting() }

        model.resetMediaServicesForTesting()

        XCTAssertTrue(model.scheduledGainBoundaryState.hasSchedule)
        XCTAssertFalse(model.scheduledGainBoundaryState.ownsPlayback)
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(model.audioRecoveryStateForTesting.connections, 0)
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
    }
}
#endif
