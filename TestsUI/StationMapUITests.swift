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
        XCTAssertTrue(map.exists, "Selecting a city must stay in Stations")
        let chicago = app.descendants(matching: .any)["map-city-chicago"].firstMatch
        XCTAssertTrue(chicago.waitForExistence(timeout: 10))
        let before = chicago.frame
        chicago.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (chicago.value as? String) == "Selected"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        XCTAssertEqual(chicago.frame.midX, before.midX, accuracy: 2, "Selection must not recenter the map")
        XCTAssertEqual(chicago.frame.midY, before.midY, accuracy: 2)
        XCTAssertTrue(app.buttons["stations-mode-map"].isSelected)
        app.buttons["map-cities"].tap()
        app.buttons["map-city-list-paris"].tap()
        let easy = app.buttons["map-station-france-musique-classique-easy"]
        let baroque = app.buttons["map-station-france-musique-la-baroque"]
        XCTAssertTrue(easy.waitForExistence(timeout: 5))
        XCTAssertTrue(baroque.exists)
        capture("station-map-paris-choices-dark")
        baroque.tap()
        XCTAssertTrue(app.buttons["map-cities"].waitForExistence(timeout: 5), "A station choice returns to the existing map")
        app.buttons["map-cities"].tap()
        app.buttons["map-city-list-paris"].tap()
        XCTAssertTrue(baroque.waitForExistence(timeout: 5))
        XCTAssertTrue(baroque.isSelected)
        app.buttons["Cancel"].tap()
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
        XCTAssertTrue(app.buttons["Play"].isHittable)
    }

    @MainActor func testPinchZoomFollowsThresholdsAndSettingsChoosesPoliticalOrSatellite() {
        let app = launch(dark: true)
        defer { app.terminate() }
        openMap(app)
        let map = app.descendants(matching: .any)["stations-map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        // Use genuine MapKit gestures, with no test-only camera driver.
        for _ in 0..<4 {
            if app.buttons["map-zoom-continent"].isSelected || app.buttons["map-zoom-country"].isSelected { break }
            map.pinch(withScale: 1.6, velocity: 1)
        }
        XCTAssertFalse(app.buttons["map-zoom-globe"].isSelected)
        capture("station-map-satellite-manual-zoom")
        for _ in 0..<4 {
            if app.buttons["map-zoom-country"].isSelected { break }
            map.pinch(withScale: 2, velocity: 1)
        }
        XCTAssertTrue(app.buttons["map-zoom-country"].isSelected)
        capture("station-map-satellite-country-gesture")
        for _ in 0..<7 {
            if app.buttons["map-zoom-globe"].isSelected { break }
            map.pinch(withScale: 0.4, velocity: -1)
        }
        XCTAssertTrue(app.buttons["map-zoom-globe"].isSelected)
        capture("station-map-satellite-globe-gesture")
        app.buttons["Back to player"].tap()
        app.buttons["Settings"].tap()
        let style = app.descendants(matching: .any).matching(identifier: "station-map-style").firstMatch
        for _ in 0..<10 {
            if style.exists, style.isHittable, style.frame.maxY < app.frame.maxY - 30 { break }
            app.swipeUp()
        }
        XCTAssertTrue(style.isHittable)
        style.tap()
        capture("station-map-style-settings")
        let political = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Political")).firstMatch
        XCTAssertTrue(political.waitForExistence(timeout: 5))
        political.tap()
        let back = app.navigationBars["Map Style"].buttons["Settings"]
        if back.exists { back.tap() }
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(style.label.contains("Political") || (style.value as? String)?.contains("Political") == true)
        app.buttons["Close"].tap()
        app.buttons["choose-station"].tap()
        capture("station-map-political-globe")
        app.buttons["map-zoom-continent"].tap()
        capture("station-map-political-continent")
        app.buttons["map-zoom-country"].tap()
        capture("station-map-political-country")
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
