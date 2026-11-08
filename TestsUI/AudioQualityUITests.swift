import XCTest
import UIKit

final class AudioQualityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testGlobalPresetsKeepActualBitratesAndPausedIntent() {
        for largeText in [false, true] {
            let app = XCUIApplication()
            XCUIDevice.shared.orientation = .portrait
            app.launchEnvironment["PHILHARMONIC_UI_STATE"] = "paused-live"
            app.launchEnvironment["PHILHARMONIC_UI_RESET_STATIONS"] = "1"
            app.launchEnvironment["PHILHARMONIC_UI_DARK"] = "1"
            app.launchEnvironment["PHILHARMONIC_UI_LARGE_TEXT"] = largeText ? "1" : "0"
            app.launch()
            defer { app.terminate() }
            XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
            app.buttons["Settings"].tap()
            let highest = app.buttons["quality-preset-highest"]
            XCTAssertTrue(highest.waitForExistence(timeout: 5))
            reach(highest, in: app, towardTop: true)
            highest.tap()
            XCTAssertTrue(highest.isSelected)
            let swiss = app.buttons["quality-menu-radio-swiss-classic"]
            reach(swiss, in: app, towardTop: false)
            XCTAssertTrue((swiss.value as? String)?.contains("192 kbps") == true)
            // Each stacked button needs its own visible bounds, below the navigation bar.
            let balanced = app.buttons["quality-preset-balanced"]
            reach(balanced, in: app, towardTop: true)
            balanced.tap()
            XCTAssertTrue(balanced.isSelected)
            reach(swiss, in: app, towardTop: false)
            XCTAssertTrue((swiss.value as? String)?.contains("96 kbps") == true)
            let lowest = app.buttons["quality-preset-lowest"]
            reach(lowest, in: app, towardTop: true)
            lowest.tap()
            XCTAssertTrue(lowest.isSelected)
            capture(largeText ? "quality-presets-accessibility3-dark" : "quality-presets-dark")
            app.buttons["Close"].tap()
            XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Pause"].exists)
        }
    }

    @MainActor private func reach(_ button: XCUIElement, in app: XCUIApplication, towardTop: Bool) {
        for _ in 0..<6 {
            if button.exists {
                let frame = button.frame
                let navigationBottom = app.navigationBars.firstMatch.frame.maxY
                if frame.minY >= navigationBottom + 2, frame.maxY <= app.frame.maxY - 30,
                   button.isHittable { return }
            }
            if towardTop { app.swipeDown() } else { app.swipeUp() }
        }
        XCTFail("Control not fully visible: \(button.identifier)")
    }

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
