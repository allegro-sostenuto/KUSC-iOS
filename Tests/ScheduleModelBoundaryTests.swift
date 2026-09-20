#if canImport(UIKit) && !canImport(KUSCCore) && DEBUG
import XCTest
@testable import KUSC_SE

/// Hosted iOS tests, not Swift Package policy tests. These invoke actual
/// AppModel actions and read the real RollingAudioEngine.volume boundary.
/// The fixture launch environment prevents station networking and audio output.
final class ScheduleModelBoundaryTests: XCTestCase {
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
