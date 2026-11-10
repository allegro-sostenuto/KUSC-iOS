import XCTest

final class BackgroundAudioSessionProbeTests: XCTestCase {
    @MainActor func testRealCategoryChangeWhileAppIsBackgrounded() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PHILHARMONIC_UI_STATE"] = "audio-session-probe"
        app.launch()
        defer { app.terminate() }
        let prepare = app.buttons["audio-probe-prepare"]
        XCTAssertTrue(prepare.waitForExistence(timeout: 10))
        prepare.tap()
        let phase = app.staticTexts["audio-probe-phase"]
        XCTAssertTrue(XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "label == 'prepared'"), evaluatedWith: phase)], timeout: 10) == .completed)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10) || app.state == .runningBackgroundSuspended)
        let hold = expectation(description: "Keep the app backgrounded beyond the initial transition")
        DispatchQueue.global().asyncAfter(deadline: .now() + 35) { hold.fulfill() }
        XCTAssertEqual(XCTWaiter.wait(for: [hold], timeout: 40), .completed)
        app.activate()
        XCTAssertTrue(XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "label == 'complete'"), evaluatedWith: phase)], timeout: 10) == .completed)
        let report = app.staticTexts["audio-probe-report"].label
        let entries = try report.split(separator: "\n").map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
        XCTAssertEqual(entries.count, 4)
        for name in ["background_playback", "background_play_and_record", "background_playback_restore"] {
            let entry = try XCTUnwrap(entries.first { $0["name"] as? String == name })
            XCTAssertEqual(entry["app_state"] as? String, "background")
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(entry["background_elapsed_seconds"] as? Double), 30)
        }
        let attachment = XCTAttachment(string: report)
        attachment.name = "real-background-audio-session-probe"; attachment.lifetime = .keepAlways
        add(attachment)
        print("NATIVE_SPEAKER_PROBE_REPORT\n" + report)
        // A successful category change is evidence the OS failure did NOT
        // reproduce on this simulator. Never turn it into a simulated failure.
    }
}
