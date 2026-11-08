import XCTest
import UIKit

final class NativeMotionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testTransportMorphIntermediateShapesAndRepeatedNativeButtonActions() {
        for progress in ["0", "0.5", "1"] {
            let app = launch(extra: ["PHILHARMONIC_UI_TRANSPORT_PROGRESS": progress])
            let play = app.buttons["Play"]
            XCTAssertTrue(play.isHittable)
            capture("transport-morph-\(progress)")
            app.terminate()
        }
        let app = launch(extra: ["PHILHARMONIC_UI_TRANSPORT_TOGGLE": "1", "PHILHARMONIC_UI_DARK": "0"])
        defer { app.terminate() }
        let frame = app.buttons["Play"].frame
        let live = app.buttons["Jump to live"].frame
        for label in ["Play", "Pause", "Play", "Pause"] {
            let button = app.buttons[label]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            XCTAssertEqual(button.frame.midX, frame.midX, accuracy: 1)
            XCTAssertEqual(button.frame.midY, frame.midY, accuracy: 1)
            button.tap()
        }
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["Jump to live"].frame, live)
        capture("transport-morph-live-actions-light")
    }

    @MainActor func testReducedMotionPanelSelectionAndUnsupportedStationKeepControlsFixed() {
        let app = launch(extra: ["PHILHARMONIC_UI_REDUCE_MOTION": "1"])
        defer { app.terminate() }
        let frame = app.buttons["Play"].frame
        app.buttons["programme-page"].tap()
        XCTAssertTrue(app.scrollViews["programme-scroll"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["Play"].frame, frame)
        app.buttons["Next station"].tap()
        XCTAssertTrue(app.scrollViews["now-playing-scroll"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["programme-page"].exists)
        XCTAssertEqual(app.buttons["Play"].frame, frame)
        app.buttons["Previous station"].tap()
        app.buttons["programme-page"].tap()
        app.buttons["now-playing-page"].tap()
        XCTAssertTrue(app.buttons["now-playing-page"].isSelected)
        capture("motion-reduced-player")
    }

    @MainActor private func launch(extra: [String: String] = [:]) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment = ["PHILHARMONIC_UI_STATE": "paused-live", "PHILHARMONIC_UI_DARK": "1",
                                 "PHILHARMONIC_UI_RESET_STATIONS": "1", "PHILHARMONIC_UI_ROTATION_DRIVER": "xctest"]
        for (key, value) in extra { app.launchEnvironment[key] = value }
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
