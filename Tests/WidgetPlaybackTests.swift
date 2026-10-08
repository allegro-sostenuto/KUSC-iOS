#if canImport(UIKit) && !canImport(KUSCCore) && DEBUG
import XCTest
@testable import KUSC_SE

final class WidgetPlaybackTests: XCTestCase {
    @MainActor func testWidgetActionsAreExplicitAndOverrideStaleInterruption() async throws {
        guard #available(iOS 17.0, *) else { return }
        let model = AppModel.shared
        model.configureAudioRecoveryForTesting(playing: false, interrupted: true)
        defer { model.finishAudioRecoveryForTesting() }
        _ = try await SetKUSCWidgetPlaybackIntent(playing: true).perform()
        XCTAssertTrue(model.isPlaying)
        XCTAssertFalse(model.audioRecoveryStateForTesting.interrupted)
        _ = try await SetKUSCWidgetPlaybackIntent(playing: true).perform()
        XCTAssertTrue(model.isPlaying, "Repeated Play from a stale widget must not pause")
        _ = try await SetKUSCWidgetPlaybackIntent(playing: false).perform()
        XCTAssertFalse(model.isPlaying)
        _ = try await SetKUSCWidgetPlaybackIntent(playing: false).perform()
        XCTAssertFalse(model.isPlaying, "Repeated Pause must not restart audio")
    }

    @MainActor func testWidgetPauseKeepsScheduledStart() {
        let model = AppModel.shared
        model.configureScheduleForTesting(options: .init(batteryOnlyStop: true), secondsUntilStart: 120,
            environment: .init(now: Date(), uptime: 5000, plugged: true, level: 0.8,
                               route: .init(ports: [.init(uid: "speaker", type: "Speaker", name: "iPhone")])))
        defer { model.finishScheduleForTesting() }
        model.setPlaybackFromWidget(false)
        XCTAssertFalse(model.isPlaying)
        XCTAssertTrue(model.scheduleStateForTesting.exists)
        model.advanceScheduleForTesting(seconds: 120)
        model.simulateScheduledReadinessForTesting()
        XCTAssertTrue(model.isPlaying)
    }

    func testLegacyWidgetLinksRequireExactPlaybackAction() {
        XCTAssertEqual(WidgetPlaybackLink.action(for: URL(string: "kusc-classic://playback/play")!, scheme: "kusc-classic"), true)
        XCTAssertEqual(WidgetPlaybackLink.action(for: URL(string: "kusc-classic://playback/pause")!, scheme: "kusc-classic"), false)
        for url in ["kusc-modern://playback/play", "kusc-classic://schedule/delete", "kusc-classic://playback/play?extra=1"] {
            XCTAssertNil(WidgetPlaybackLink.action(for: URL(string: url)!, scheme: "kusc-classic"))
        }
    }
}
#endif
