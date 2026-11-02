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
                      "no-artwork", "unavailable-programme", "paused-live",
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
            CaptureFixture(name: "schedule-power-dark", state: "schedule-power", dark: true),
            CaptureFixture(name: "reveal-left", state: "reveal-left"),
            CaptureFixture(name: "reveal-right-dark", state: "reveal-right", dark: true),
            CaptureFixture(name: "reveal-programme-right", state: "reveal-programme-right"),
            CaptureFixture(name: "programme-dark", state: "programme", dark: true)
        ]
        var regularSheetTitleHeights: [String: CGFloat] = [:]
        var restingFooterFrames: [Bool: [CGRect]] = [:]
        var restingPanelX: [Bool: CGFloat] = [:]
        for layout in ["playback", "artwork", "details", "everything", "artwork-only", "details-only"] {
            fixtures.append(CaptureFixture(name: "widget-" + layout, state: "widget-" + layout))
            fixtures.append(CaptureFixture(name: "widget-" + layout + "-dark", state: "widget-" + layout, dark: true))
        }
        fixtures.append(CaptureFixture(name: "widget-everything-empty", state: "widget-everything-empty"))
        fixtures.append(CaptureFixture(name: "widget-details-large-text", state: "widget-details", largeText: true))
        fixtures.append(CaptureFixture(name: "widget-artwork-only-empty", state: "widget-artwork-only-empty", dark: true))
        fixtures.append(CaptureFixture(name: "widget-details-only-large-text", state: "widget-details-only", largeText: true))
        for fixture in fixtures {
            XCTContext.runActivity(named: "Capture " + fixture.name) { _ in
                let app = startFixture(fixture)
                defer { app.terminate() }
                guard waitForFixture(fixture, in: app) else {
                    XCTFail("Native UI did not become ready: \(fixture.name)")
                    attach(app, named: "failed-readiness-" + fixture.name)
                    return
                }
                if fixture.name == "live" || fixture.name == "landscape" {
                    restingFooterFrames[fixture.landscape] = footerFrames(in: app)
                    restingPanelX[fixture.landscape] = app.scrollViews["now-playing-scroll"].frame.minX
                }
                if fixture.state.hasPrefix("reveal-") {
                    let identifier = fixture.state == "reveal-programme-right" ? "programme-scroll" : "now-playing-scroll"
                    let delta = app.scrollViews[identifier].frame.minX - (restingPanelX[fixture.landscape] ?? 0)
                    if fixture.state == "reveal-programme-right" {
                        XCTAssertEqual(delta, 0, accuracy: 1, "Program stays underneath during the return")
                    } else {
                        XCTAssertGreaterThan(delta, 50, "The capture must show the panel displaced from rest")
                    }
                }
                if fixture.state.hasPrefix("reveal-") || fixture.name == "programme" || fixture.name == "programme-dark" {
                    let actual = footerFrames(in: app)
                    if let expected = restingFooterFrames[fixture.landscape] {
                        for (frame, baseline) in zip(actual, expected) {
                            XCTAssertEqual(frame.minX, baseline.minX, accuracy: 1, "Footer must not move during panel reveal")
                            XCTAssertEqual(frame.minY, baseline.minY, accuracy: 1, "Footer must remain below both panels")
                        }
                    } else {
                        XCTFail("Missing resting footer comparison")
                    }
                    XCTAssertEqual(app.buttons.matching(identifier: "Pause").count, 1)
                    XCTAssertEqual(app.buttons.matching(identifier: "More controls").count, 1)
                }
                if fixture.largeText && fixture.state == "live" {
                    XCTAssertTrue(app.staticTexts["Native layout fixture"].isHittable,
                                  "The work title must remain visible below artwork at accessibility text sizes.")
                }
                if fixture.state.hasPrefix("widget-") {
                    if fixture.state.contains("-only") {
                        XCTAssertFalse(app.buttons["Play Philharmonic"].exists)
                        XCTAssertFalse(app.buttons["Pause Philharmonic"].exists)
                    } else {
                        let label = fixture.state.contains("empty") ? "Play Philharmonic" : "Pause Philharmonic"
                        XCTAssertTrue(app.buttons[label].isHittable, "Widget playback control must remain reachable")
                    }
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
    private func footerFrames(in app: XCUIApplication) -> [CGRect] {
        let elements = [app.buttons["Pause"], app.buttons["Jump to live"], app.buttons["More controls"],
                        app.staticTexts["Listening live"]]
        return elements.map {
            XCTAssertTrue($0.isHittable, "Fixed playback controls and status must stay visible")
            return $0.frame
        }
    }

    @MainActor
    func testSettingsOfferLivePlaybackWithoutDelayPreferences() {
        let app = launchFixture("settings")
        defer { app.terminate() }
        XCTAssertTrue(app.switches["Auto-play on launch"].exists)
        XCTAssertFalse(app.staticTexts["Rolling buffer"].exists)
        XCTAssertFalse(app.pickers["Rolling buffer duration"].exists)
        XCTAssertFalse(app.buttons["Resume after pause"].exists)
        XCTAssertTrue(app.staticTexts["Playback is live-only. Play returns to live after a pause."].exists)
    }

    @MainActor
    func testPersistentSchedulePowerControlsKeepSafeguardAndExposeExpiryRule() {
        let app = launchFixture("schedule-power")
        defer { app.terminate() }
        let persistent = app.switches["scheduled-battery-only"]
        XCTAssertEqual(persistent.value as? String, "1")
        XCTAssertEqual(app.switches["scheduled-allow-battery"].value as? String, "1")
        XCTAssertFalse(app.switches["scheduled-allow-battery"].isEnabled)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
            "10 minutes after the selected time", "Delete it here to cancel sooner")).firstMatch.exists)
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
        app.launchEnvironment["PHILHARMONIC_UI_STATE"] = "live"
        app.launchEnvironment["PHILHARMONIC_UI_DARK"] = "1"
        app.launchEnvironment["PHILHARMONIC_UI_REPEAT_MODEL_UPDATES"] = "1"
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
    func testFirstSwipeOpensProgramWithoutWarmup() {
        for (state, landscape) in [("live", false), ("dark", false)] {
            let app = launchFixture(state, landscape: landscape)
            let station = app.staticTexts["station-header"]
            XCTAssertTrue(station.waitForExistence(timeout: 5))
            XCTAssertTrue(station.label.contains("KUSC"))
            XCTAssertTrue(station.label.contains("91.5 FM"))
            let footer = footerFrames(in: app)
            let first = app.scrollViews["now-playing-scroll"]
            // This is the first gesture after a fresh launch: no rejected swipe,
            // short drag or page-button tap can prime the recognizers.
            let start = first.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.35))
            let end = first.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.42))
            start.press(forDuration: 0.05, thenDragTo: end)
            let program = app.staticTexts["programme-header"]
            let opened = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.buttons["programme-page"].isSelected &&
                    app.scrollViews["programme-scroll"].isHittable && !first.isHittable
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [opened], timeout: 5), .completed,
                           "The first right swipe must actually select and reveal Program")
            XCTAssertTrue(program.exists)
            XCTAssertEqual(program.label, "Program")
            for (actual, resting) in zip(footerFrames(in: app), footer) {
                XCTAssertEqual(actual.minX, resting.minX, accuracy: 1)
                XCTAssertEqual(actual.minY, resting.minY, accuracy: 1)
            }
            attach(app, named: "first-swipe-" + state + (landscape ? "-landscape" : ""))
            swipePanel(app.scrollViews["programme-scroll"], direction: -1)
            let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.buttons["now-playing-page"].isSelected && first.isHittable &&
                    !app.scrollViews["programme-scroll"].isHittable
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed,
                           "The first return swipe must actually restore the piece details")
            XCTAssertTrue(station.exists)
            XCTAssertTrue(app.buttons["Pause"].isHittable)
            app.terminate()
        }
    }

    @MainActor
    func testProgramStaysPortraitUntilReturningToPlayer() {
        let app = launchFixture("live")
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        swipePanel(app.scrollViews["now-playing-scroll"], direction: 1)
        let opened = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.buttons["programme-page"].isSelected && app.scrollViews["programme-scroll"].isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [opened], timeout: 5), .completed)
        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertLessThan(app.frame.width, app.frame.height, "Program must stay portrait when the phone turns")
        XCTAssertTrue(app.scrollViews["programme-scroll"].isHittable)
        attach(app, named: "program-portrait-lock")
        swipePanel(app.scrollViews["programme-scroll"], direction: -1)
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.scrollViews["now-playing-scroll"].isHittable &&
                !app.scrollViews["programme-scroll"].isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed)
        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.orientation = .landscapeRight
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 10), .completed,
                       "The artwork player must support landscape after leaving Program")
        XCTAssertFalse(app.buttons["programme-page"].exists)
        attach(app, named: "landscape-player-after-program")
    }

    @MainActor
    func testHeaderRollPartialRevealCapture() {
        let app = launchFixture("reveal-right")
        attach(app, named: "header-roll-partial-reveal")
        XCTAssertTrue(app.buttons["Pause"].isHittable)
        app.terminate()
    }

    @MainActor
    func testRightSwipeOpensProgramAndLeftSwipeReturns() {
        let app = launchFixture("live")
        defer { app.terminate() }
        let nowPlaying = app.scrollViews["now-playing-scroll"]
        let programme = app.staticTexts["Programme layout fixture"]
        swipePanel(nowPlaying, direction: -1)
        XCTAssertTrue(nowPlaying.isHittable, "A left swipe must not open Program")
        XCTAssertFalse(programme.exists)
        for direction in [1.0] {
            let scroll = app.scrollViews["now-playing-scroll"]
            let restingX = scroll.frame.minX
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: direction * 16, dy: 0)))
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                scroll.exists && abs(scroll.frame.minX - restingX) <= 1
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed,
                           "Cancellation must finish its settling animation")
            XCTAssertTrue(nowPlaying.isHittable, "A short drag must settle back to the current panel")
            XCTAssertEqual(scroll.frame.minX, restingX, accuracy: 1, "Cancellation must restore the resting position")
            XCTAssertFalse(programme.exists, "The underneath panel must be hidden from accessibility")

            swipePanel(scroll, direction: direction)
            XCTAssertTrue(programme.waitForExistence(timeout: 5))
            XCTAssertFalse(nowPlaying.exists)
            XCTAssertFalse(app.buttons["now-playing-header"].exists)
            XCTAssertEqual(app.staticTexts["programme-header"].label, "Program")
            XCTAssertFalse(app.buttons["Program"].exists, "Program is a heading, not a return button")
            app.staticTexts["programme-header"].tap()
            XCTAssertTrue(programme.exists, "Tapping the heading must not change panels")
            swipePanel(app.scrollViews["programme-scroll"], direction: direction)
            XCTAssertTrue(programme.exists, "A right swipe must not close Program")
            swipePanel(app.scrollViews["programme-scroll"], direction: -direction)
            XCTAssertTrue(nowPlaying.waitForExistence(timeout: 5), "The reverse direction must return to Now Playing")
            XCTAssertFalse(programme.exists)
            XCTAssertTrue(app.buttons["Pause"].isHittable)
        }
    }

    @MainActor
    func testHorizontalRevealLocksVerticalScrollAndReleaseRestoresIt() {
        let app = launchFixture("programme")
        defer { app.terminate() }
        let scroll = app.scrollViews["programme-scroll"]
        let title = app.staticTexts["Programme layout fixture"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let initialY = title.frame.minY
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.35))
        // A real short horizontal pan with vertical drift must lock scrolling.
        // Hold before release so it cancels rather than becoming a fast flick.
        start.press(forDuration: 0.05,
                    thenDragTo: start.withOffset(CGVector(dx: -40, dy: -12)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(app.staticTexts["programme-header"].exists)
        XCTAssertEqual(title.frame.minY, initialY, accuracy: 1,
                       "Vertical content must stay still during a horizontal pan")
        let normalStart = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.7))
        normalStart.press(forDuration: 0.1, thenDragTo: normalStart.withOffset(CGVector(dx: 0, dy: -100)))
        XCTAssertLessThan(title.frame.minY, initialY - 30, "Vertical scrolling must resume after settling")
        XCTAssertTrue(app.buttons["Pause"].isHittable)
    }

    @MainActor
    private func swipePanel(_ panel: XCUIElement, direction: Double) {
        let start = panel.coordinate(withNormalizedOffset: CGVector(dx: direction > 0 ? 0.2 : 0.8, dy: 0.25))
        let end = panel.coordinate(withNormalizedOffset: CGVector(dx: direction > 0 ? 0.8 : 0.2, dy: 0.25))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    @MainActor
    func testLandscapeLiveOnlyControlsAndPaging() {
        for state in ["live", "dark"] {
            let app = launchFixture(state, landscape: true)
            let orientation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.frame.width > app.frame.height
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [orientation], timeout: 10), .completed)
            let player = app.scrollViews["now-playing-scroll"]
            let artwork = app.descendants(matching: .any).matching(identifier: "player-artwork").firstMatch
            let play = app.buttons["Pause"]
            XCTAssertTrue(player.isHittable)
            XCTAssertGreaterThan(artwork.frame.width, app.frame.height * 0.55,
                                 "Landscape artwork must retain its historical large size")
            XCTAssertEqual(artwork.frame.width, artwork.frame.height, accuracy: 1)
            XCTAssertGreaterThan(player.frame.minX, artwork.frame.maxX)
            for button in [app.buttons["Jump to live"], play, app.buttons["More controls"]] {
                XCTAssertTrue(button.isHittable)
                XCTAssertGreaterThanOrEqual(button.frame.minX, player.frame.minX - 1,
                                            "Transport belongs in the right column, below the details")
                XCTAssertGreaterThanOrEqual(button.frame.minY, player.frame.maxY - 1)
            }
            XCTAssertEqual(play.frame.midX, player.frame.midX, accuracy: 1)
            swipePanel(player, direction: 1)
            XCTAssertTrue(player.isHittable)
            XCTAssertFalse(app.buttons["programme-page"].exists, "Program is unavailable in landscape")
            XCTAssertFalse(app.scrollViews["programme-scroll"].exists)
            XCTAssertTrue(app.staticTexts["station-header"].label.contains("KUSC"))
            attach(app, named: "restored-landscape-" + state)
            app.terminate()
        }
    }

    @MainActor
    func testLargeTextLiveOnlyControlsAndPaging() {
        let app = launchFixture("live", largeText: true)
        exerciseLiveControlsAndPaging(app, attachment: "large-text-live-and-programme")
    }

    @MainActor
    func testPullToRefreshBothPanelsPreservesPlaybackAndHorizontalPaging() {
        let app = launchFixture("dark")
        let scroll = app.scrollViews["now-playing-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        pull(scroll, distance: 25)
        XCTAssertTrue(app.staticTexts["Native layout fixture"].exists,
                      "A short pull must return without starting a refresh")
        pull(scroll, distance: 240)
        XCTAssertTrue(app.staticTexts["Refreshed layout fixture 1"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Pause"].exists, "Refresh must not pause audio")
        let artwork = app.descendants(matching: .any).matching(identifier: "player-artwork").firstMatch
        artwork.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo:
                artwork.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        let programme = app.scrollViews["programme-scroll"]
        XCTAssertTrue(programme.waitForExistence(timeout: 5), "Horizontal paging must still work")
        pull(programme, distance: 240)
        XCTAssertTrue(app.staticTexts["Refreshed programme fixture 2"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Pause"].exists)
        app.buttons["now-playing-page"].tap()
        XCTAssertTrue(app.staticTexts["Refreshed layout fixture 2"].waitForExistence(timeout: 5))
        attach(app, named: "pull-refresh-both-panels-dark")
    }

    @MainActor
    func testLandscapePullToRefreshKeepsPausedAudioPaused() {
        let app = launchFixture("paused-live", landscape: true)
        let scroll = app.scrollViews["now-playing-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        pull(scroll, distance: 240)
        XCTAssertTrue(app.staticTexts["Refreshed layout fixture 1"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Play"].exists, "Refresh must not resume paused audio")
        XCTAssertFalse(app.buttons["programme-page"].exists)
        XCTAssertFalse(app.scrollViews["programme-scroll"].exists)
        XCTAssertTrue(app.buttons["Play"].exists)

    }

    @MainActor
    private func pull(_ scroll: XCUIElement, distance: CGFloat) {
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 20))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)))
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
        app.launchEnvironment["PHILHARMONIC_UI_STATE"] = fixture.state
        app.launchEnvironment["PHILHARMONIC_UI_ROTATION_DRIVER"] = "xctest"
        app.launchEnvironment["PHILHARMONIC_UI_LANDSCAPE"] = fixture.landscape ? "1" : "0"
        app.launchEnvironment["PHILHARMONIC_UI_LARGE_TEXT"] = fixture.largeText ? "1" : "0"
        app.launchEnvironment["PHILHARMONIC_UI_DARK"] = fixture.dark ? "1" : "0"
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
        case "reveal-left", "reveal-right", "reveal-programme-right": marker = app.buttons["Settings"]
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
    private func exerciseLiveControlsAndPaging(_ app: XCUIApplication, attachment: String) {
        XCTAssertFalse(app.sliders["Listening position in retained audio"].exists)
        XCTAssertTrue(app.buttons["Pause"].isHittable)
        XCTAssertTrue(app.buttons["Jump to live"].isHittable)
        XCTAssertTrue(app.buttons["More controls"].isHittable)
        XCTAssertTrue(app.staticTexts["Listening live"].exists)

        let artwork = app.descendants(matching: .any).matching(identifier: "player-artwork").firstMatch
        XCTAssertTrue(artwork.waitForExistence(timeout: 5))
        XCTAssertTrue(artwork.isHittable)
        artwork.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo:
                artwork.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        XCTAssertTrue(app.staticTexts["Programme layout fixture"].waitForExistence(timeout: 5))
        attach(app, named: attachment + "-programme")
        let nowPlaying = app.buttons["now-playing-page"]
        XCTAssertTrue(nowPlaying.isHittable)
        nowPlaying.tap()
        XCTAssertTrue(app.scrollViews["now-playing-scroll"].waitForExistence(timeout: 5),
                      "Wait for the animated return to finish before checking which panel is visible")
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
