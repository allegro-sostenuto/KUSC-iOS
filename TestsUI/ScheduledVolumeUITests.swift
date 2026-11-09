import XCTest

final class ScheduledVolumeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testSpeakerVolumeSetupSaveAndCancelInBothAppearances() {
        for dark in [false, true] {
            let app = XCUIApplication()
            app.launchEnvironment["PHILHARMONIC_UI_STATE"] = "schedule-volume"
            app.launchEnvironment["PHILHARMONIC_UI_DARK"] = dark ? "1" : "0"
            app.launch()
            let row = app.buttons["scheduled-start-volume"]
            for _ in 0..<5 {
                if row.isHittable { break }
                app.scrollViews.firstMatch.swipeUp()
            }
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
            let done = app.buttons["speaker-volume-done"]
            XCTAssertTrue(done.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["speaker-volume-value"].exists)
            capture("speaker-volume-setup-" + (dark ? "dark" : "light"))
            done.tap()
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            XCTAssertFalse(row.label.contains("Not set"))
            capture("scheduled-volume-saved-" + (dark ? "dark" : "light"))
            row.tap()
            XCTAssertTrue(done.waitForExistence(timeout: 5))
            app.buttons["speaker-volume-cancel"].tap()
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIApplication().screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
