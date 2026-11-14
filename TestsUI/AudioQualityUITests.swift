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
            let presets = app.segmentedControls["quality-presets"]
            let highest = presets.buttons["Highest"]
            XCTAssertTrue(highest.waitForExistence(timeout: 5))
            reach(highest, in: app, towardTop: true)
            highest.tap()
            XCTAssertTrue(highest.isSelected)
            let swiss = app.buttons["quality-menu-radio-swiss-classic"]
            reach(swiss, in: app, towardTop: false)
            expectValue("192 kbps", of: swiss)
            let balanced = presets.buttons["Balanced"]
            reach(balanced, in: app, towardTop: true)
            balanced.tap()
            XCTAssertTrue(balanced.isSelected)
            reach(swiss, in: app, towardTop: false)
            expectValue("96 kbps", of: swiss)
            let lowest = presets.buttons["Lowest"]
            reach(lowest, in: app, towardTop: true)
            lowest.tap()
            XCTAssertTrue(lowest.isSelected)
            reach(swiss, in: app, towardTop: false)
            swiss.tap()
            app.buttons["AAC · 192 kbps"].tap()
            expectValue("192 kbps", of: swiss)
            reach(highest, in: app, towardTop: true)
            XCTAssertFalse(presets.buttons.allElementsBoundByIndex.contains { $0.isSelected },
                           "Manual station choices leave every native segment unselected")
            capture(largeText ? "quality-custom-accessibility3-dark" : "quality-custom-dark")
            balanced.tap()
            XCTAssertTrue(balanced.isSelected)
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
                if frame.height > 0, frame.minY < navigationBottom + 2 {
                    app.swipeDown()
                    continue
                }
                if frame.height > 0, frame.maxY > app.frame.maxY - 30 {
                    app.swipeUp()
                    continue
                }
            }
            if towardTop { app.swipeDown() } else { app.swipeUp() }
        }
        capture("quality-unreachable-\(button.identifier)")
        XCTFail("Control not fully visible: \(button.identifier), frame: \(button.frame)")
    }

    @MainActor private func expectValue(_ text: String, of element: XCUIElement) {
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (element.value as? String)?.contains(text) == true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed,
                       "Expected \(text), received \(String(describing: element.value))")
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
            app.cells["station-radio-swiss-classic"].tap()
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
            expectValue("96 kbps", of: swiss)
            capture("quality-channel-list" + (dark ? "-dark" : "-light"))
            swiss.tap()
            XCTAssertTrue(app.buttons["AAC · 192 kbps"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons["MP3 · 128 kbps"].exists)
            XCTAssertTrue(app.buttons["AAC · 96 kbps"].exists)
            capture("quality-bitrate-dropdown" + (dark ? "-dark" : "-light"))
            app.buttons["AAC · 192 kbps"].tap()
            expectValue("192 kbps", of: swiss)
            app.buttons["Close"].tap()
            XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Pause"].exists)
            app.buttons["Settings"].tap()
            expectValue("192 kbps", of: swiss)
            swiss.tap()
            app.buttons["MP3 · 128 kbps"].tap()
            expectValue("MP3 · 128 kbps", of: swiss)
            swiss.tap()
            app.buttons["AAC · 96 kbps"].tap()
            expectValue("96 kbps", of: swiss)
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
