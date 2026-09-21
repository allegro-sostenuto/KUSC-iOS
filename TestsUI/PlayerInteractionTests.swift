import XCTest
import UIKit

/// Native gesture and layout checks use DEBUG fixtures. They deliberately do not
/// claim audio continuity, scheduling, or route behavior was exercised.
final class PlayerInteractionTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureNativeLayouts() {
        // A failed state should preserve the remaining evidence. XCTest still
        // fails this test, and the artifact collector rejects missing captures.
        continueAfterFailure = true
        let states = ["live", "dark", "programme", "settings", "sleep", "schedule",
                      "schedule-output", "minimal", "reconnecting", "output", "paused",
                      "no-artwork", "unavailable-programme", "partial-buffer", "paused-buffer",
                      "scheduled-silent", "scheduled-fade", "unavailable-output"]
        var fixtures = states.map { CaptureFixture(name: $0, state: $0) }
        fixtures += [
            CaptureFixture(name: "landscape", state: "live", landscape: true),
            CaptureFixture(name: "minimal-landscape", state: "minimal", landscape: true),
            CaptureFixture(name: "large-text", state: "live", largeText: true),
            CaptureFixture(name: "programme-large-text", state: "programme", largeText: true),
            CaptureFixture(name: "schedule-large-text", state: "schedule", largeText: true),
            CaptureFixture(name: "sleep-large-text", state: "sleep", largeText: true),
            CaptureFixture(name: "settings-dark", state: "settings", dark: true),
            CaptureFixture(name: "sleep-dark", state: "sleep", dark: true),
            CaptureFixture(name: "schedule-output-dark", state: "schedule-output", dark: true)
        ]
        var regularSheetTitleHeights: [String: CGFloat] = [:]
        for fixture in fixtures {
            XCTContext.runActivity(named: "Capture " + fixture.name) { _ in
                let app = startFixture(fixture)
                defer { app.terminate() }
                guard waitForFixture(fixture, in: app) else {
                    XCTFail("Native UI did not become ready: \(fixture.name)")
                    attach(app, named: "failed-readiness-" + fixture.name)
                    return
                }
                if fixture.largeText && fixture.state == "live" {
                    XCTAssertTrue(app.staticTexts["Native layout fixture"].isHittable,
                                  "The work title must remain visible below artwork at accessibility text sizes.")
                }
                if fixture.state == "sleep" {
                    XCTAssertTrue(app.buttons["timer-primary-action"].isHittable,
                                  "Sleep timer action must stay visible without scrolling.")
                } else if ["schedule", "schedule-output"].contains(fixture.state) {
                    XCTAssertTrue(app.buttons["schedule-primary-action"].isHittable,
                                  "Schedule action must stay visible without scrolling.")
                }
                if ["sleep", "schedule"].contains(fixture.state) {
                    let title = app.staticTexts[fixture.state == "sleep" ? "Sleep Timer" : "Scheduled Start"]
                    if fixture.largeText {
                        if let regularHeight = regularSheetTitleHeights[fixture.state] {
                            XCTAssertGreaterThan(title.frame.height, regularHeight * 1.4,
                                                 "Accessibility text must visibly enlarge the presented sheet title.")
                        } else {
                            XCTFail("Missing regular-size sheet comparison: \(fixture.state)")
                        }
                        if fixture.state == "sleep" {
                            XCTAssertLessThan(title.frame.minY, app.frame.height * 0.3,
                                              "The accessibility sleep sheet must open at the large detent.")
                        }
                    } else {
                        regularSheetTitleHeights[fixture.state] = title.frame.height
                    }
                }
                // app.frame is the logical interface orientation, checked by
                // waitForFixture. Preserve the complete native screen: an app
                // screenshot can incorrectly crop the landscape window to a
                // portrait rectangle on some simulator versions.
                attach(app, named: "capture-" + fixture.name, fixture: fixture)
            }
        }
    }

    @MainActor
    func testDiagnosticsCaptureCanBeStartedStoppedAndSharedFromSettings() {
        let app = launchFixture("settings")
        let diagnostics = app.buttons["Playback Diagnostics"]
        for _ in 0..<4 {
            if diagnostics.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(diagnostics.isHittable)
        diagnostics.tap()
        let start = app.buttons["Start New Capture"]
        let stop = app.buttons["Stop Capture"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertTrue(start.isEnabled)
        XCTAssertFalse(stop.isEnabled)
        start.tap()
        XCTAssertTrue(app.staticTexts["Recording"].waitForExistence(timeout: 5))
        XCTAssertFalse(start.isEnabled)
        XCTAssertTrue(stop.isEnabled)
        attach(app, named: "capture-diagnostics-recording",
               fixture: CaptureFixture(name: "diagnostics-recording", state: "settings"))
        stop.tap()
        XCTAssertTrue(app.staticTexts["Ready"].waitForExistence(timeout: 5))
        let copy = app.buttons["Copy Report"]
        for _ in 0..<5 {
            if copy.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(copy.isHittable)
        XCTAssertTrue(copy.isEnabled, "Stopping capture must preserve the report for copying.")
        XCTAssertTrue(app.buttons["Share Report"].isEnabled)
        copy.tap()
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
        attach(app, named: "more-native-menu", fixture: CaptureFixture(name: "more", state: "live"))
    }

    @MainActor
    func testHistoryKeepsGrowingAfterEarlyScrub() {
        let app = launchFixture("growing-buffer")
        let slider = app.sliders["Listening position in retained audio"]
        let history = app.staticTexts.matching(identifier: "retained-audio-history").firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        let left = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        let right = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        right.press(forDuration: 0.1, thenDragTo: left)
        XCTAssertFalse(((slider.value as? String) ?? "").contains("Preview"))
        assertHistoryAdvances(history)
        assertHistoryAdvances(history)
        slider.adjust(toNormalizedSliderPosition: 0.55)
        XCTAssertFalse(((slider.value as? String) ?? "").contains("Preview"))
        assertHistoryAdvances(history)
    }

    @MainActor
    private func assertHistoryAdvances(_ history: XCUIElement) {
        let previous = history.label
        let update = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            history.label != previous
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [update], timeout: 5), .completed,
                       "Acquired history must continue growing after a scrub before retention fills.")
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
        let fixture = CaptureFixture(name: state, state: state, landscape: landscape, largeText: largeText)
        let app = startFixture(fixture)
        XCTAssertTrue(waitForFixture(fixture, in: app))
        return app
    }

    private struct CaptureFixture {
        let name: String
        let state: String
        var landscape = false
        var largeText = false
        var dark = false
    }

    @MainActor
    private func startFixture(_ fixture: CaptureFixture) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["KUSC_UI_STATE"] = fixture.state
        app.launchEnvironment["KUSC_UI_ROTATION_DRIVER"] = "xctest"
        app.launchEnvironment["KUSC_UI_LANDSCAPE"] = fixture.landscape ? "1" : "0"
        app.launchEnvironment["KUSC_UI_LARGE_TEXT"] = fixture.largeText ? "1" : "0"
        app.launchEnvironment["KUSC_UI_DARK"] = fixture.dark ? "1" : "0"
        app.launch()
        if fixture.landscape { XCUIDevice.shared.orientation = .landscapeRight }
        return app
    }

    @MainActor
    private func waitForFixture(_ fixture: CaptureFixture, in app: XCUIApplication) -> Bool {
        let marker: XCUIElement
        switch fixture.state {
        case "settings": marker = app.switches["Auto-play on launch"]
        case "sleep": marker = app.staticTexts["Sleep Timer"]
        case "schedule": marker = app.staticTexts["Start once"]
        case "schedule-output": marker = app.staticTexts["Audio Output"]
        case "output", "unavailable-output": marker = app.staticTexts["Audio Output"]
        case "paused": marker = app.buttons["Keep counting"]
        case "programme": marker = app.staticTexts["Programme layout fixture"]
        case "unavailable-programme": marker = app.staticTexts["Previous pieces are unavailable."]
        case "minimal": marker = app.buttons["Pause"]
        case "no-artwork": marker = app.buttons["Play"]
        default: marker = app.buttons["More controls"]
        }
        guard marker.waitForExistence(timeout: 20) else { return false }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            marker.isHittable && ((app.frame.width > app.frame.height) == fixture.landscape)
        }, object: nil)
        return XCTWaiter.wait(for: [ready], timeout: 10) == .completed
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
    private func attach(_ app: XCUIApplication, named name: String, fixture: CaptureFixture? = nil) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let fixture else { return }
        let frame = app.frame
        let metadata: [String: Any] = [
            "capture": fixture.name,
            "captureSource": "XCUIScreen.main",
            "fixtureState": fixture.state,
            "requestedOrientation": fixture.landscape ? "landscape" : "portrait",
            "logicalFrame": ["width": Double(frame.width), "height": Double(frame.height)],
            "deviceOrientation": XCUIDevice.shared.orientation.rawValue,
            "uiImageOrientation": screenshot.image.imageOrientation.rawValue,
            "uiImageSize": ["width": Double(screenshot.image.size.width), "height": Double(screenshot.image.size.height)],
            "uiImageScale": Double(screenshot.image.scale)
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
            let evidence = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            evidence.name = "capture-metadata-" + fixture.name
            evidence.lifetime = .keepAlways
            add(evidence)
        } catch {
            XCTFail("Could not record native capture metadata: \(error)")
        }
    }
}
