#if canImport(UIKit) && !canImport(PhilharmonicCore) && DEBUG
import XCTest
@testable import Philharmonic_SE

final class WidgetPlaybackTests: XCTestCase {
    @MainActor func testWidgetActionsAreExplicitAndOverrideStaleInterruption() async throws {
        guard #available(iOS 17.0, *) else { return }
        let model = AppModel.shared
        model.configureAudioRecoveryForTesting(playing: false, interrupted: true)
        defer { model.finishAudioRecoveryForTesting() }
        _ = try await SetPhilharmonicWidgetPlaybackIntent(playing: true).perform()
        XCTAssertTrue(model.isPlaying)
        XCTAssertFalse(model.audioRecoveryStateForTesting.interrupted)
        _ = try await SetPhilharmonicWidgetPlaybackIntent(playing: true).perform()
        XCTAssertTrue(model.isPlaying, "Repeated Play from a stale widget must not pause")
        _ = try await SetPhilharmonicWidgetPlaybackIntent(playing: false).perform()
        XCTAssertFalse(model.isPlaying)
        _ = try await SetPhilharmonicWidgetPlaybackIntent(playing: false).perform()
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

    func testStationWidgetLinksAcceptOnlyOneExplicitIdentity() {
        let valid = URL(string: "kusc-classic://playback/play?station=sr-p2")!
        XCTAssertEqual(WidgetPlaybackLink.action(for: valid, scheme: "kusc-classic"), true)
        XCTAssertEqual(WidgetPlaybackLink.stationID(for: valid), "sr-p2")
        for address in ["kusc-classic://playback/play?station=", "kusc-classic://playback/play?station=kusc&station=sr-p2",
                        "kusc-classic://playback/play?station=kusc&extra=1"] {
            XCTAssertNil(WidgetPlaybackLink.action(for: URL(string: address)!, scheme: "kusc-classic"))
        }
    }
}
#endif
