import XCTest

/// Native gesture and layout checks use DEBUG fixtures. They deliberately do not
/// claim audio continuity, scheduling, or route behavior was exercised.
final class PlayerInteractionTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMoreMenuUsesNativePresentation() {
        let app = launchFixture("live")
        let more = app.buttons["More controls"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.tap()
        XCTAssertTrue(app.buttons["Sleep Timer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Scheduled Start"].exists)
        XCTAssertTrue(app.buttons["Audio Output"].exists)
        attach(app, named: "more-native-menu")
    }

    @MainActor
    func testLandscapeSliderDoesNotNavigateProgramme() {
        let app = launchFixture("partial-buffer", landscape: true)
        let orientation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [orientation], timeout: 10), .completed)
        exerciseSliderAndPaging(app, attachment: "landscape-slider-and-programme")
    }

    @MainActor
    func testLargeTextSliderDoesNotNavigateProgramme() {
        let app = launchFixture("partial-buffer", largeText: true)
        exerciseSliderAndPaging(app, attachment: "large-text-slider-and-programme")
    }

    @MainActor
    private func launchFixture(_ state: String, landscape: Bool = false, largeText: Bool = false) -> XCUIApplication {
        XCUIDevice.shared.orientation = landscape ? .landscapeRight : .portrait
        let app = XCUIApplication()
        app.launchEnvironment["KUSC_UI_STATE"] = state
        app.launchEnvironment["KUSC_UI_LANDSCAPE"] = landscape ? "1" : "0"
        app.launchEnvironment["KUSC_UI_LARGE_TEXT"] = largeText ? "1" : "0"
        app.launch()
        XCTAssertTrue(app.staticTexts["Native layout fixture"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func exerciseSliderAndPaging(_ app: XCUIApplication, attachment: String) {
        let slider = app.sliders["Listening position in retained audio"]
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        XCTAssertTrue(slider.isHittable, "Retained-audio slider must remain reachable.")
        let left = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        let right = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        // Use real touch drags, not accessibility value changes, to exercise the
        // recognizer boundary between retained-audio seeking and page navigation.
        left.press(forDuration: 0.1, thenDragTo: right)
        XCTAssertFalse(app.staticTexts["Programme layout fixture"].exists)
        right.press(forDuration: 0.1, thenDragTo: left)
        XCTAssertFalse(app.staticTexts["Programme layout fixture"].exists)
        XCTAssertTrue(app.staticTexts["Native layout fixture"].exists)
        attach(app, named: attachment + "-after-slider")

        let artwork = app.descendants(matching: .any).matching(identifier: "player-artwork").firstMatch
        XCTAssertTrue(artwork.waitForExistence(timeout: 5))
        XCTAssertTrue(artwork.isHittable)
        artwork.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo:
                artwork.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        XCTAssertTrue(app.staticTexts["Programme layout fixture"].waitForExistence(timeout: 5))
        attach(app, named: attachment + "-programme")
        let nowPlaying = app.buttons.matching(identifier: "Now Playing").firstMatch
        XCTAssertTrue(nowPlaying.isHittable)
        nowPlaying.tap()
        XCTAssertFalse(app.staticTexts["Programme layout fixture"].exists)
        XCTAssertTrue(app.staticTexts["Native layout fixture"].exists)
    }

    @MainActor
    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
