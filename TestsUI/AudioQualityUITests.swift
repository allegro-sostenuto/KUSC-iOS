import XCTest
import UIKit

final class AudioQualityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testChannelBitrateDropdownsAndPausedPlaybackInLightAndDark() {
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
            let swiss = app.buttons["quality-menu-radio-swiss-classic"]
            XCTAssertTrue(swiss.waitForExistence(timeout: 5))
            let fixed = app.buttons["quality-menu-kusc"]
            XCTAssertTrue(fixed.exists)
            XCTAssertFalse(fixed.isEnabled)
            XCTAssertEqual(fixed.frame.minX, swiss.frame.minX, accuracy: 1, "Fixed and selectable qualities share one column")
            XCTAssertEqual(fixed.frame.maxX, swiss.frame.maxX, accuracy: 1)
            XCTAssertEqual(fixed.frame.height, swiss.frame.height, accuracy: 1)
            XCTAssertTrue((swiss.value as? String)?.contains("96 kbps") == true)
            capture("quality-channel-list" + (dark ? "-dark" : "-light"))
            swiss.tap()
            XCTAssertTrue(app.buttons["AAC · 192 kbps"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons["MP3 · 128 kbps"].exists)
            XCTAssertTrue(app.buttons["AAC · 96 kbps"].exists)
            capture("quality-bitrate-dropdown" + (dark ? "-dark" : "-light"))
            app.buttons["AAC · 192 kbps"].tap()
            XCTAssertTrue((swiss.value as? String)?.contains("192 kbps") == true)
            app.buttons["Close"].tap()
            XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Pause"].exists)
            app.buttons["Settings"].tap()
            XCTAssertTrue((swiss.value as? String)?.contains("192 kbps") == true)
            swiss.tap()
            app.buttons["MP3 · 128 kbps"].tap()
            XCTAssertTrue((swiss.value as? String)?.contains("MP3 · 128 kbps") == true)
            swiss.tap()
            app.buttons["AAC · 96 kbps"].tap()
            XCTAssertTrue((swiss.value as? String)?.contains("96 kbps") == true)
            app.buttons["Close"].tap()
            XCTAssertTrue(app.buttons["Play"].isHittable)
        }
    }

    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
