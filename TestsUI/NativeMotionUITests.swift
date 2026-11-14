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

    @MainActor func testProgrammeUnavailableFeedbackKeepsHomeAndControlsInPlace() {
        for reduceMotion in [false, true] {
            let app = launch(extra: ["PHILHARMONIC_UI_REDUCE_MOTION": reduceMotion ? "1" : "0"])
            defer { app.terminate() }
            app.buttons["Next station"].tap()
            XCTAssertTrue(app.buttons["choose-station"].label.contains("Swiss"))
            let home = app.scrollViews["now-playing-scroll"]
            let notice = app.staticTexts["programme-unavailable-message"]
            let controls = app.buttons["Play"].frame
            let start = home.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.4))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 30, dy: 0)))
            XCTAssertFalse(notice.exists, "Short drags stay below the feedback threshold")
            home.swipeLeft()
            XCTAssertFalse(notice.exists, "The gesture must point toward Programme")
            home.swipeRight()
            XCTAssertTrue(notice.waitForExistence(timeout: 1))
            XCTAssertEqual(notice.label, "Programme unavailable for this station")
            XCTAssertTrue(app.buttons["now-playing-page"].isSelected)
            XCTAssertFalse(app.buttons["programme-page"].exists)
            XCTAssertTrue(app.staticTexts["station-header"].label.contains("Swiss"))
            XCTAssertEqual(app.buttons["Play"].frame, controls)
            capture(reduceMotion ? "programme-unavailable-reduced-motion" : "programme-unavailable-inline")
            app.buttons["Previous station"].tap()
            XCTAssertFalse(notice.exists, "Changing stations clears its previous feedback")
            home.swipeRight()
            XCTAssertTrue(app.buttons["programme-page"].waitForExistence(timeout: 5))
            let opened = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.buttons["programme-page"].isSelected
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [opened], timeout: 5), .completed)
        }
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
