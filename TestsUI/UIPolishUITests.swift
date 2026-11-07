import XCTest
import UIKit

/// Focused app UI checks only; no stream playback or widget changes are exercised.
final class UIPolishUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testTransportWrapsAndLogoFallbackFollowsTheStation() {
        let app = launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let artwork = app.descendants(matching: .any).matching(identifier: "player-artwork").firstMatch
        XCTAssertTrue(artwork.waitForExistence(timeout: 5))
        XCTAssertEqual(artwork.label, "KUSC station logo")
        capture("polish-logo-kusc-dark")
        app.buttons["Next station"].tap()
        XCTAssertTrue(app.buttons["choose-station"].label.contains("Swiss"))
        XCTAssertEqual(artwork.label, "Radio Swiss Classic station logo")
        XCTAssertFalse(app.buttons["programme-page"].exists)
        app.scrollViews["now-playing-scroll"].swipeRight()
        XCTAssertTrue(app.buttons["now-playing-page"].isSelected)
        app.buttons["Previous station"].tap()
        app.buttons["Previous station"].tap()
        XCTAssertTrue(app.buttons["choose-station"].label.contains("Oude Muziek"))
        XCTAssertEqual(artwork.label, "Concertzender · Oude Muziek station logo")
        XCTAssertTrue(app.buttons["Play"].isHittable)
        capture("polish-previous-wrap-logo-dark")
        app.buttons["Next station"].tap()
        XCTAssertTrue(app.buttons["choose-station"].label.contains("KUSC"))
        XCTAssertTrue(app.staticTexts["station-header"].label.contains("KUSC"))
        XCUIDevice.shared.orientation = .landscapeRight
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["programme-page"].exists)
        XCTAssertTrue(app.buttons["Play"].isHittable)
        capture("polish-landscape-logo-controls-dark")
    }

    @MainActor func testSettingsLargeTextKeepsQualityAndNativeAppearanceReachable() {
        let app = launch(extra: ["PHILHARMONIC_UI_LARGE_TEXT": "1"])
        defer { app.terminate() }
        app.buttons["Settings"].tap()
        let swiss = app.buttons["quality-menu-radio-swiss-classic"]
        reach(swiss, app: app)
        XCTAssertTrue((swiss.value as? String)?.contains("96 kbps") == true)
        capture("polish-settings-accessibility-dark")
        // The native picker is near the end of the seventeen-row Quality group.
        let appearance = app.descendants(matching: .any).matching(identifier: "appearance-picker").firstMatch
        reach(appearance, app: app)
        capture("polish-settings-interface-accessibility-dark")
        appearance.tap()
        let light = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Light")).firstMatch
        XCTAssertTrue(light.waitForExistence(timeout: 5))
        light.tap()
        let back = app.navigationBars["Appearance"].buttons["Settings"]
        if back.exists { back.tap() }
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(appearance.label.contains("Light") || (appearance.value as? String)?.contains("Light") == true)
        capture("polish-settings-interface-accessibility-light")
    }

    @MainActor func testIntermediateHeaderLayoutsUseHorizontalAndVerticalAxes() {
        let cases: [(String, [String: String])] = [
            ("polish-header-next-half", ["PHILHARMONIC_UI_HEADER_POSITION": "0.5"]),
            ("polish-header-previous-half", ["PHILHARMONIC_UI_HEADER_POSITION": "-0.5"]),
            ("polish-header-program-horizontal", ["PHILHARMONIC_UI_PANEL_FRACTION": "0.65"])
        ]
        for (name, environment) in cases {
            let app = launch(extra: environment)
            XCTAssertTrue(app.staticTexts["station-header"].waitForExistence(timeout: 5))
            capture(name)
            app.terminate()
        }
    }

    @MainActor private func launch(extra: [String: String] = [:]) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment = ["PHILHARMONIC_UI_STATE": "paused-live", "PHILHARMONIC_UI_DARK": "1",
                                 "PHILHARMONIC_UI_RESET_STATIONS": "1", "PHILHARMONIC_UI_ROTATION_DRIVER": "xctest"]
        for (key, value) in extra { app.launchEnvironment[key] = value }
        app.launch()
        XCTAssertTrue(app.buttons["choose-station"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor private func reach(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<24 {
            if element.exists, element.frame.minY.isFinite,
               app.frame.contains(CGPoint(x: element.frame.midX, y: element.frame.midY)), element.isHittable { return }
            app.swipeUp()
        }
        capture("polish-unreachable-settings-row")
        XCTFail("Settings row is not reachable: " + element.identifier)
    }

    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
