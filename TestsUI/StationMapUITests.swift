import XCTest
import UIKit

final class StationMapUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testThreeZoomsSingleCityAndMultipleStationPopup() {
        let app = launch(dark: true)
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        openMap(app)
        XCTAssertFalse(app.buttons["stations-reorder"].exists)
        let map = app.descendants(matching: .any)["stations-map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        capture("station-map-globe-dark")
        for level in ["continent", "country", "globe"] {
            app.buttons["map-zoom-" + level].tap()
            XCTAssertTrue(app.buttons["map-zoom-" + level].isSelected)
            capture("station-map-" + level + "-dark")
        }
        // The marker exercises the actual map, separately from the accessible Cities menu.
        let losAngeles = app.descendants(matching: .any)["map-city-los-angeles"].firstMatch
        XCTAssertTrue(losAngeles.waitForExistence(timeout: 15))
        losAngeles.tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["choose-station"].label.contains("KUSC"))

        app.buttons["choose-station"].tap()
        XCTAssertTrue(app.buttons["stations-mode-map"].isSelected, "Map mode is saved")
        app.buttons["map-cities"].tap()
        app.buttons["map-city-list-paris"].tap()
        let easy = app.buttons["map-station-france-musique-classique-easy"]
        let baroque = app.buttons["map-station-france-musique-la-baroque"]
        XCTAssertTrue(easy.waitForExistence(timeout: 5))
        XCTAssertTrue(baroque.exists)
        capture("station-map-paris-choices-dark")
        baroque.tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["choose-station"].label.contains("La Baroque"))

        app.buttons["choose-station"].tap()
        app.buttons["map-cities"].tap()
        app.buttons["map-city-list-moscow"].tap()
        XCTAssertTrue(app.buttons["map-station-orpheus-large-scale"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["map-station-orpheus-russian-classical"].exists)
        XCTAssertTrue(app.buttons["map-station-orpheus-camerata"].exists)
        capture("station-map-moscow-choices-dark")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(map.exists, "Cancelling a city keeps the map open")
        app.buttons["Back to player"].tap()
        XCTAssertTrue(app.buttons["choose-station"].label.contains("La Baroque"))
    }

    @MainActor func testMapLandscapeAndExistingNativeGridListControls() {
        let app = launch(dark: false)
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        app.buttons["choose-station"].tap()
        app.buttons["stations-mode-list"].tap()
        let kusc = app.buttons["station-kusc"], swiss = app.buttons["station-radio-swiss-classic"]
        XCTAssertGreaterThan(swiss.frame.minY, kusc.frame.maxY)
        capture("station-native-list-light")
        app.buttons["stations-mode-grid"].tap()
        XCTAssertEqual(kusc.frame.minY, swiss.frame.minY, accuracy: 2)
        capture("station-native-grid-light")
        app.buttons["stations-reorder"].tap()
        app.buttons["station-move-later-kusc"].tap()
        app.buttons["stations-mode-map"].tap()
        XCTAssertFalse(app.buttons["stations-reorder"].exists)
        XCUIDevice.shared.orientation = .landscapeRight
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 8), .completed)
        app.buttons["map-zoom-country"].tap()
        capture("station-map-country-landscape-light")
        app.buttons["stations-mode-list"].tap()
        XCTAssertTrue(app.scrollViews["stations-horizontal-scroll"].exists)
        XCTAssertTrue(swiss.isHittable)
        XCTAssertFalse(app.buttons["station-move-later-kusc"].exists, "Map leaves reorder mode")
    }

    @MainActor private func launch(dark: Bool) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["PHILHARMONIC_UI_STATE"] = "paused-live"
        app.launchEnvironment["PHILHARMONIC_UI_ROTATION_DRIVER"] = "xctest"
        app.launchEnvironment["PHILHARMONIC_UI_RESET_STATIONS"] = "1"
        app.launchEnvironment["PHILHARMONIC_UI_DARK"] = dark ? "1" : "0"
        app.launch()
        XCTAssertTrue(app.buttons["choose-station"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor private func openMap(_ app: XCUIApplication) {
        app.buttons["choose-station"].tap()
        app.buttons["stations-mode-map"].tap()
    }

    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
