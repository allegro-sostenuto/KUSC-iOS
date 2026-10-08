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
            CaptureFixture(name: "schedule-output-dark", state: "schedule-output", dark: true),
            CaptureFixture(name: "schedule-power", state: "schedule-power"),
            CaptureFixture(name: "schedule-power-dark", state: "schedule-power", dark: true)
        ]
        var regularSheetTitleHeights: [String: CGFloat] = [:]
        for layout in ["playback", "artwork", "details", "everything"] {
            fixtures.append(CaptureFixture(name: "widget-" + layout, state: "widget-" + layout))
            fixtures.append(CaptureFixture(name: "widget-" + layout + "-dark", state: "widget-" + layout, dark: true))
        }
        fixtures.append(CaptureFixture(name: "widget-everything-empty", state: "widget-everything-empty"))
        fixtures.append(CaptureFixture(name: "widget-details-large-text", state: "widget-details", largeText: true))
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
                if fixture.state.hasPrefix("widget-") {
                    let label = fixture.state.contains("empty") ? "Play KUSC" : "Pause KUSC"
                    XCTAssertTrue(app.buttons[label].isHittable, "Widget playback control must remain reachable")
                    XCTAssertFalse(app.buttons["Live"].exists)
                }
                if fixture.state == "sleep" {
                    XCTAssertTrue(app.buttons["timer-primary-action"].isHittable,
                                  "Sleep timer action must stay visible without scrolling.")
                } else if ["schedule", "schedule-output", "schedule-power"].contains(fixture.state) {
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
    func testPersistentSchedulePowerControlsKeepSafeguardAndExposeDeletionRule() {
        let app = launchFixture("schedule-power")
        defer { app.terminate() }
        let persistent = app.switches["scheduled-battery-only"]
        XCTAssertEqual(persistent.value as? String, "1")
        XCTAssertEqual(app.switches["scheduled-allow-battery"].value as? String, "1")
        XCTAssertFalse(app.switches["scheduled-allow-battery"].isEnabled)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "delete this scheduled start")).firstMatch.exists)
        let threshold = app.descendants(matching: .any).matching(identifier: "scheduled-battery-threshold").firstMatch
        for _ in 0..<3 {
            if threshold.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(threshold.isHittable)
        XCTAssertEqual(threshold.value as? String, "25 percent")
        let duration = app.descendants(matching: .any).matching(identifier: "scheduled-battery-duration").firstMatch
        for _ in 0..<3 {
            if duration.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(duration.isHittable)
        XCTAssertEqual(duration.value as? String, "20 minutes")
        let right = duration.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
        right.withOffset(CGVector(dx: -22, dy: 0)).tap()
        XCTAssertEqual(duration.value as? String, "20 minutes", "The cutoff delay cannot exceed 20 minutes")
        right.withOffset(CGVector(dx: -66, dy: 0)).tap()
        XCTAssertEqual(duration.value as? String, "19 minutes", "Shorter delays must be selectable")
        right.withOffset(CGVector(dx: -22, dy: 0)).tap()
        XCTAssertEqual(duration.value as? String, "20 minutes")
        XCTAssertTrue(app.buttons["schedule-primary-action"].isHittable)
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
    func testReminderOpensAtDeleteWithoutCancellingTheSchedule() {
        let app = launchFixture("schedule-reminder")
        defer { app.terminate() }
        let delete = app.buttons["delete-scheduled-start"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        XCTAssertTrue(delete.isHittable, "The reminder must scroll directly to the delete button")
        XCTAssertTrue(app.staticTexts["Current schedule"].exists)
        attach(app, named: "capture-schedule-reminder-delete")
    }

    @MainActor
    func testDarkMenuBrightnessStaysStableDuringPlaybackUpdates() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["KUSC_UI_STATE"] = "live"
        app.launchEnvironment["KUSC_UI_DARK"] = "1"
        app.launchEnvironment["KUSC_UI_REPEAT_MODEL_UPDATES"] = "1"
        app.launch()
        defer { app.terminate() }
        let more = app.buttons["More controls"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.tap()
        let item = app.buttons["Sleep Timer"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        // Let the menu's opening animation settle before comparing brightness.
        Thread.sleep(forTimeInterval: 1)
        let baseline = try meanBrightness(of: item.frame, app: app)
        for index in 1...3 {
            Thread.sleep(forTimeInterval: 1)
            XCTAssertTrue(item.isHittable)
            XCTAssertEqual(try meanBrightness(of: item.frame, app: app), baseline, accuracy: 0.012,
                           "Open menu text must not pulse when playback publishes state")
            attach(app, named: "capture-more-dark-stable-\(index)")
        }
        item.tap()
        XCTAssertTrue(app.staticTexts["Sleep Timer"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func meanBrightness(of frame: CGRect, app: XCUIApplication) throws -> Double {
        let screen = try XCTUnwrap(XCUIScreen.main.screenshot().image.cgImage)
        let scaleX = CGFloat(screen.width) / app.frame.width
        let scaleY = CGFloat(screen.height) / app.frame.height
        let crop = CGRect(x: frame.minX * scaleX, y: frame.minY * scaleY,
                          width: frame.width * scaleX, height: frame.height * scaleY)
        let image = try XCTUnwrap(screen.cropping(to: crop))
        var pixels = [UInt8](repeating: 0, count: 64 * 16 * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 64, height: 16,
                bitsPerComponent: 8, bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 16))
        }
        var total = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            total += Int(pixels[offset])
            total += Int(pixels[offset + 1])
            total += Int(pixels[offset + 2])
        }
        return Double(total) / Double(64 * 16 * 3 * 255)
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
        let adjustedValue = (slider.value as? String) ?? ""
        attach(app, named: "growing-buffer-after-normalized-adjustment")
        XCTAssertFalse(adjustedValue.contains("Preview"),
                       "A completed normalized adjustment must release its preview; got \(adjustedValue)")
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
        case "schedule-power": marker = app.switches["scheduled-battery-only"]
        case "schedule-reminder": marker = app.buttons["delete-scheduled-start"]
        case "output", "unavailable-output": marker = app.staticTexts["Audio Output"]
        case "paused": marker = app.buttons["Keep counting"]
        case "programme": marker = app.staticTexts["Programme layout fixture"]
        case "unavailable-programme": marker = app.staticTexts["Previous pieces are unavailable."]
        case "minimal": marker = app.buttons["Pause"]
        case "no-artwork": marker = app.buttons["Play"]
        case let state where state.hasPrefix("widget-"): marker = app.staticTexts["Widget layout fixture"]
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
