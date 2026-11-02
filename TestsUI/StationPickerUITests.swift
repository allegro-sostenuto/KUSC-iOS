import XCTest
import UIKit

/// Silent native UI fixtures exercise selection/order/rotation; stream playback
/// and physical output remain separate native audio and device checks.
final class StationPickerUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testGridListRotationAndHorizontalReachability() {
        for dark in [false, true] {
            let app = launch(dark: dark)
            defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
            app.buttons["choose-station"].tap()
            let kusc = app.buttons["station-kusc"]
            let swiss = app.buttons["station-radio-swiss-classic"]
            XCTAssertTrue(kusc.waitForExistence(timeout: 5))
            XCTAssertEqual(kusc.frame.minY, swiss.frame.minY, accuracy: 2, "Grid has two entries per row")
            capture("stations-grid-portrait" + (dark ? "-dark" : ""))
            app.buttons["stations-mode-list"].tap()
            XCTAssertGreaterThan(swiss.frame.minY, kusc.frame.maxY, "List has one entry per row")
            capture("stations-list-portrait" + (dark ? "-dark" : ""))
            rotate(.landscapeRight, app: app)
            XCTAssertTrue(app.scrollViews["stations-horizontal-scroll"].exists)
            XCTAssertFalse(app.scrollViews["stations-vertical-scroll"].exists)
            capture("stations-list-landscape" + (dark ? "-dark" : ""))
            app.buttons["stations-reorder"].tap()
            app.buttons["station-move-later-kusc"].tap()
            reach("kusc", app: app, horizontal: true)
            XCTAssertTrue(kusc.isSelected)
            capture("stations-list-landscape-reordered" + (dark ? "-dark" : ""))
            app.buttons["station-move-earlier-kusc"].tap()
            app.buttons["stations-reorder"].tap()
            reach("hr-klasik", app: app, horizontal: true)
            XCTAssertTrue(app.buttons["station-hr-klasik"].isHittable, "Horizontal list reaches the last entry")
            app.buttons["stations-mode-grid"].tap()
            // A new presentation starts with its first row; selection and order stay saved.
            app.buttons["Back to player"].tap()
            app.buttons["choose-station"].tap()
            XCTAssertTrue(kusc.waitForExistence(timeout: 5))
            XCTAssertEqual(kusc.frame.minY, swiss.frame.minY, accuracy: 2)
            capture("stations-grid-landscape" + (dark ? "-dark" : ""))
            app.buttons["stations-reorder"].tap()
            app.buttons["station-move-later-kusc"].tap()
            XCTAssertLessThan(swiss.frame.minX, kusc.frame.minX)
            capture("stations-grid-landscape-reordered" + (dark ? "-dark" : ""))
            app.buttons["station-move-earlier-kusc"].tap()
            app.buttons["stations-reorder"].tap()
            reach("hr-klasik", app: app, horizontal: true)
            app.buttons["station-hr-klasik"].tap()
            rotate(.portrait, app: app)
            XCTAssertTrue(app.buttons["stations-mode-grid"].isSelected)
            app.buttons["Back to player"].tap()
            XCTAssertTrue(app.buttons["choose-station"].label.contains("HR Klasik"))
            XCTAssertTrue(app.buttons["Play"].isHittable, "Selecting a station preserves paused intent")
        }
    }

    @MainActor
    func testReorderAcrossModesPersistsAndStationTransportUsesSavedOrder() {
        let app = launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        app.buttons["choose-station"].tap()
        app.buttons["stations-reorder"].tap()
        app.buttons["station-move-later-kusc"].tap()
        let swiss = app.buttons["station-radio-swiss-classic"]
        let kusc = app.buttons["station-kusc"]
        XCTAssertLessThan(swiss.frame.minX, kusc.frame.minX)
        capture("stations-grid-reordered")
        app.buttons["stations-mode-list"].tap()
        XCTAssertLessThan(swiss.frame.minY, kusc.frame.minY)
        app.buttons["station-move-earlier-kusc"].tap()
        XCTAssertLessThan(kusc.frame.minY, swiss.frame.minY)
        capture("stations-list-reordered")
        app.buttons["station-move-later-kusc"].tap()
        app.buttons["stations-reorder"].tap()
        swiss.tap()
        app.buttons["Back to player"].tap()
        XCTAssertTrue(app.buttons["choose-station"].label.contains("Swiss"))
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "PHILHARMONIC_UI_RESET_STATIONS")
        app.launch()
        XCTAssertTrue(app.buttons["choose-station"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["choose-station"].label.contains("Swiss"))
        app.buttons["Next station"].tap()
        XCTAssertTrue(app.buttons["choose-station"].label.contains("KUSC"))
        app.buttons["Previous station"].tap()
        XCTAssertTrue(app.buttons["choose-station"].label.contains("Swiss"))
        app.buttons["Previous station"].tap()
        XCTAssertTrue(app.buttons["choose-station"].label.contains("HR Klasik"), "Previous wraps to the catalogue end")
        app.buttons["Next station"].tap()
        XCTAssertTrue(app.buttons["choose-station"].label.contains("Swiss"), "Next wraps to the saved first entry")
        app.buttons["choose-station"].tap()
        XCTAssertTrue(app.buttons["stations-mode-list"].isSelected)
        XCTAssertLessThan(swiss.frame.minY, kusc.frame.minY)
        XCTAssertTrue(app.buttons["Play"].exists == false, "The picker is a dedicated page")
    }

    @MainActor
    func testDragReordersInGridAndListWithoutSelectingStation() {
        let app = launch()
        defer { app.terminate() }
        app.buttons["choose-station"].tap()
        let kusc = app.buttons["station-kusc"]
        let swiss = app.buttons["station-radio-swiss-classic"]
        kusc.press(forDuration: 0.8, thenDragTo: swiss)
        let gridChanged = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            swiss.frame.minX < kusc.frame.minX
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [gridChanged], timeout: 5), .completed)
        XCTAssertTrue(kusc.isSelected, "Dragging changes order without changing the selected station")
        capture("stations-grid-drag-reordered")
        app.buttons["stations-mode-list"].tap()
        swiss.press(forDuration: 0.8, thenDragTo: kusc)
        let listChanged = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            kusc.frame.minY < swiss.frame.minY
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [listChanged], timeout: 5), .completed)
        XCTAssertTrue(kusc.isSelected)
        capture("stations-list-drag-reordered")
        app.buttons["Back to player"].tap()
        XCTAssertTrue(app.buttons["Play"].isHittable)
        XCTAssertTrue(app.buttons["choose-station"].label.contains("KUSC"))
    }

    @MainActor
    private func launch(dark: Bool = false) -> XCUIApplication {
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

    @MainActor
    private func reach(_ id: String, app: XCUIApplication, horizontal: Bool) {
        for _ in 0..<12 {
            if app.buttons["station-" + id].isHittable { return }
            if horizontal { app.scrollViews["stations-horizontal-scroll"].swipeLeft() }
            else { app.scrollViews["stations-vertical-scroll"].swipeUp() }
        }
        XCTFail("Station was not reachable: " + id)
    }

    @MainActor
    private func rotate(_ orientation: UIDeviceOrientation, app: XCUIApplication) {
        XCUIDevice.shared.orientation = orientation
        let landscape = orientation.isLandscape
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (app.frame.width > app.frame.height) == landscape
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 10), .completed)
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
