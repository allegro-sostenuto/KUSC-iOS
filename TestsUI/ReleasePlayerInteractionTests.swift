import XCTest
import UIKit

/// Exercise the delivered configuration without DEBUG fixture/probe views.
final class ReleasePlayerInteractionTests: XCTestCase {
    @MainActor func testFirstSwipeAndReturnWithoutFixtureProbe() throws {
        #if DEBUG
        throw XCTSkip("This smoke check requires the uninstrumented Release configuration.")
        #else
        #if !targetEnvironment(simulator)
        throw XCTSkip("Run only on the disposable simulator created by the check script.")
        #endif
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        app.launch()
        XCTAssertTrue(app.buttons["choose-station"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "panel-gesture-trace").firstMatch.exists)
        let player = app.scrollViews["now-playing-scroll"]
        XCTAssertTrue(player.waitForExistence(timeout: 10))
        XCTAssertTrue(player.isHittable)
        let controls = ["Jump to live", "More controls", "Next station", "Previous station"]
        let frames = controls.map { app.buttons[$0].frame }
        let start = player.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.35))
        let end = player.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.42))
        start.press(forDuration: 0.05, thenDragTo: end)
        let opened = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.buttons["programme-page"].isSelected && app.scrollViews["programme-scroll"].isHittable && !player.isHittable
        }, object: nil)
        let result = XCTWaiter.wait(for: [opened], timeout: 8)
        capture("release-first-swipe", app: app)
        XCTAssertEqual(result, .completed, "The first diagonal swipe must work without a DEBUG fixture or probe")
        for (name, frame) in zip(controls, frames) {
            XCTAssertEqual(app.buttons[name].frame.minX, frame.minX, accuracy: 1)
            XCTAssertEqual(app.buttons[name].frame.minY, frame.minY, accuracy: 1)
        }
        let programme = app.scrollViews["programme-scroll"]
        programme.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: programme.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)))
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.buttons["now-playing-page"].isSelected && player.isHittable && !programme.isHittable
        }, object: nil)
        let returnResult = XCTWaiter.wait(for: [returned], timeout: 8)
        capture("release-first-return", app: app)
        XCTAssertEqual(returnResult, .completed)
        #endif
    }

    @MainActor private func capture(_ name: String, app: XCUIApplication) {
        let picture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        picture.name = name; picture.lifetime = .keepAlways; add(picture)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + "-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
    }
}
