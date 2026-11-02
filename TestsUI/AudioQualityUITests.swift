import XCTest
import UIKit

final class AudioQualityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testAdvancedQualityChoiceAndPausedPlaybackInLightAndDark() {
        for dark in [false, true] {
            XCUIDevice.shared.orientation = .portrait
            let app = XCUIApplication()
            app.launchEnvironment["PHILHARMONIC_UI_STATE"] = "paused-live"
            app.launchEnvironment["PHILHARMONIC_UI_RESET_STATIONS"] = "1"
            app.launchEnvironment["PHILHARMONIC_UI_DARK"] = dark ? "1" : "0"
            app.launch()
            defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
            XCTAssertTrue(app.buttons["choose-station"].waitForExistence(timeout: 5))
            app.buttons["choose-station"].tap()
            app.buttons["station-radio-swiss-classic"].tap()
            app.buttons["Back to player"].tap()
            app.buttons["Settings"].tap()
            app.buttons["Advanced"].tap()
            let standard = app.segmentedControls.buttons["Standard"]
            let high = app.segmentedControls.buttons["High"]
            XCTAssertTrue(standard.waitForExistence(timeout: 5))
            XCTAssertTrue(standard.isSelected)
            XCTAssertEqual(app.staticTexts["selected-audio-quality"].label, "AAC · 96 kbps")
            high.tap()
            XCTAssertTrue(high.isSelected)
            XCTAssertEqual(app.staticTexts["selected-audio-quality"].label, "AAC · 192 kbps")
            capture("audio-quality-high" + (dark ? "-dark" : "-light"))
            standard.tap()
            XCTAssertTrue(standard.isSelected)
            XCTAssertEqual(app.staticTexts["selected-audio-quality"].label, "AAC · 96 kbps")
            capture("audio-quality-standard" + (dark ? "-dark" : "-light"))
            app.navigationBars.buttons["Settings"].tap()
            app.buttons["Close"].tap()
            XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Pause"].exists)
        }
    }

    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
