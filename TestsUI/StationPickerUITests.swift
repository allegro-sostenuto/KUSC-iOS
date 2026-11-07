import XCTest
import UIKit

/// Silent native UI fixtures exercise selection/order/rotation; stream playback
/// and physical output remain separate native audio and device checks.
final class StationPickerUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testSixAddedStationsAreReachableAndSelectWithoutStartingPlayback() {
        let app = launch(dark: true)
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        app.buttons["choose-station"].tap()
        app.buttons["stations-mode-list"].tap()
        for id in ["yle-klassinen", "rete-toscana-classica", "wfmt", "romania-muzical",
                   "rtp-opera", "concertzender-oude-muziek"] {
            reach(id, app: app, horizontal: false)
            let station = app.buttons["station-" + id]
            station.tap()
            XCTAssertTrue(station.isSelected)
        }
        capture("stations-six-added-list-portrait-dark")
        app.buttons["Back to player"].tap()
        XCTAssertTrue(app.buttons["choose-station"].label.contains("Oude Muziek"))
        XCTAssertTrue(app.buttons["Play"].isHittable)
        app.buttons["choose-station"].tap()
        app.buttons["stations-mode-grid"].tap()
        rotate(.landscapeRight, app: app)
        reach("concertzender-oude-muziek", app: app, horizontal: true)
        XCTAssertTrue(app.buttons["station-concertzender-oude-muziek"].isSelected)
        capture("stations-six-added-grid-landscape-dark")
        app.buttons["Back to player"].tap()
        XCTAssertTrue(app.buttons["Play"].isHittable)
    }

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
            reach("concertzender-oude-muziek", app: app, horizontal: true)
            XCTAssertTrue(app.buttons["station-concertzender-oude-muziek"].isHittable, "Horizontal list reaches the last entry")
            reach("kusc", app: app, horizontal: true, forward: false)
            XCTAssertTrue(kusc.isSelected, "Reverse scrolling cannot select another station")
            XCTAssertTrue((kusc.value as? String)?.contains("position 1") == true,
                          "Reverse scrolling cannot reorder the catalogue")
            app.buttons["stations-mode-grid"].tap()
            // A new presentation starts with its first row; selection and order stay saved.
            app.buttons["Back to player"].tap()
            XCTAssertTrue(app.scrollViews["now-playing-scroll"].isHittable)
            XCTAssertFalse(app.scrollViews["programme-scroll"].isHittable,
                           "Picker swipes must never open Program underneath its page")
            XCTAssertTrue(app.buttons["choose-station"].label.contains("KUSC"))
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
            reach("concertzender-oude-muziek", app: app, horizontal: true)
            reach("kusc", app: app, horizontal: true, forward: false)
            XCTAssertTrue(kusc.isSelected)
            XCTAssertTrue((kusc.value as? String)?.contains("position 1") == true)
            reach("concertzender-oude-muziek", app: app, horizontal: true)
            app.buttons["station-concertzender-oude-muziek"].tap()
            rotate(.portrait, app: app)
            XCTAssertTrue(app.buttons["stations-mode-grid"].isSelected)
            app.buttons["Back to player"].tap()
            XCTAssertTrue(app.buttons["choose-station"].label.contains("Oude Muziek"))
            XCTAssertTrue(app.buttons["Play"].isHittable, "Selecting a station preserves paused intent")
            XCTAssertTrue(app.buttons["now-playing-page"].isSelected)
            XCTAssertFalse(app.scrollViews["programme-scroll"].isHittable)
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
        XCTAssertTrue(app.buttons["choose-station"].label.contains("Oude Muziek"), "Previous wraps to the catalogue end")
        app.buttons["Next station"].tap()
        XCTAssertTrue(app.buttons["choose-station"].label.contains("Swiss"), "Next wraps to the saved first entry")
        app.buttons["choose-station"].tap()
        XCTAssertTrue(app.buttons["stations-mode-list"].isSelected)
        XCTAssertLessThan(swiss.frame.minY, kusc.frame.minY)
        XCTAssertFalse(app.buttons["Play"].isHittable, "The picker covers the player controls")
    }

    @MainActor
    func testDragReordersInGridAndListWithoutSelectingStation() {
        let app = launch()
        defer { app.terminate() }
        app.buttons["choose-station"].tap()
        app.buttons["stations-reorder"].tap()
        let kusc = app.buttons["station-kusc"]
        let swiss = app.buttons["station-radio-swiss-classic"]
        kusc.press(forDuration: 1.2, thenDragTo: swiss, withVelocity: .slow, thenHoldForDuration: 0.3)
        let gridChanged = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            swiss.frame.minX < kusc.frame.minX
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [gridChanged], timeout: 5), .completed)
        XCTAssertTrue(kusc.isSelected, "Dragging changes order without changing the selected station")
        capture("stations-grid-drag-reordered")
        app.buttons["stations-mode-list"].tap()
        swiss.press(forDuration: 1.2, thenDragTo: kusc, withVelocity: .slow, thenHoldForDuration: 0.3)
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
    func testAccessibilityLandscapeGridAndListKeepNamesAndReorderControlsReachable() {
        let app = launch(largeText: true)
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        app.buttons["choose-station"].tap()
        rotate(.landscapeRight, app: app)
        app.buttons["stations-reorder"].tap()
        for mode in ["grid", "list"] {
            app.buttons["stations-mode-" + mode].tap()
            // Reopening retains mode/order and returns the horizontal roll to
            // its first row, so each presentation independently reaches the end.
            app.buttons["Back to player"].tap()
            app.buttons["choose-station"].tap()
            app.buttons["stations-reorder"].tap()
            reach("orpheus-russian-classical", app: app, horizontal: true)
            let station = app.buttons["station-orpheus-russian-classical"]
            let move = app.buttons["station-move-earlier-orpheus-russian-classical"]
            let scroll = app.scrollViews["stations-horizontal-scroll"]
            XCTAssertTrue(station.label.contains("Russian Classical Music"))
            XCTAssertTrue(move.isHittable)
            XCTAssertGreaterThanOrEqual(station.frame.minY, scroll.frame.minY - 1)
            XCTAssertLessThanOrEqual(move.frame.maxY, scroll.frame.maxY + 1,
                                     "The reorder footer must fit the short landscape viewport")
            capture("stations-" + mode + "-landscape-accessibility3-reorder")
            move.tap()
            // Selecting and moving are separate actions even at large text.
            app.buttons["Back to player"].tap()
            XCTAssertTrue(app.buttons["choose-station"].label.contains("KUSC"))
            XCTAssertTrue(app.buttons["Play"].isHittable)
            app.buttons["choose-station"].tap()
            app.buttons["stations-reorder"].tap()
        }
    }

    @MainActor
    private func launch(dark: Bool = false, largeText: Bool = false) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["PHILHARMONIC_UI_STATE"] = "paused-live"
        app.launchEnvironment["PHILHARMONIC_UI_ROTATION_DRIVER"] = "xctest"
        app.launchEnvironment["PHILHARMONIC_UI_RESET_STATIONS"] = "1"
        app.launchEnvironment["PHILHARMONIC_UI_DARK"] = dark ? "1" : "0"
        app.launchEnvironment["PHILHARMONIC_UI_LARGE_TEXT"] = largeText ? "1" : "0"
        app.launch()
        XCTAssertTrue(app.buttons["choose-station"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func reach(_ id: String, app: XCUIApplication, horizontal: Bool, forward: Bool = true) {
        let station = app.buttons["station-" + id]
        let scroll = app.scrollViews[horizontal ? "stations-horizontal-scroll" : "stations-vertical-scroll"]
        for _ in 0..<32 {
            // Lazy stacks expose placeholder accessibility entries before their
            // native views exist. Asking XCTest for a placeholder's activation
            // point throws instead of returning false, so first require a real
            // finite frame and an on-screen centre inside this scroll viewport.
            if station.exists {
                let frame = station.frame
                let viewport = scroll.frame.intersection(app.frame)
                if frame.minX.isFinite, frame.minY.isFinite,
                   frame.width.isFinite, frame.height.isFinite,
                   frame.width > 0, frame.height > 0,
                   viewport.contains(CGPoint(x: frame.midX, y: frame.midY)),
                   station.isHittable { return }
            }
            if horizontal {
                if forward { scroll.swipeLeft() } else { scroll.swipeRight() }
            } else {
                if forward { scroll.swipeUp() } else { scroll.swipeDown() }
            }
        }
        capture("unreachable-station-" + id)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "unreachable-station-hierarchy-" + id
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
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
