import XCTest
#if canImport(PhilharmonicCore)
@testable import PhilharmonicCore
#else
@testable import Philharmonic_SE
#endif

final class PanelSwipeTests: XCTestCase {
    func testDragTracksBothDirectionsAndClampsAtViewport() {
        for sign in [-1.0, 1.0] {
            var swipe = PanelSwipeState()
            XCTAssertEqual(swipe.translation(x: 45 * sign, y: 2, width: 390), 45 * sign)
            XCTAssertEqual(swipe.translation(x: 900 * sign, y: 2, width: 390), 390 * sign)
            XCTAssertEqual(swipe.releaseDirection(x: 150 * sign, predictedX: 150 * sign, width: 390), Int(sign))
        }
    }

    func testVerticalRefreshOrScrollCannotTurnIntoPagingMidGesture() {
        var swipe = PanelSwipeState()
        XCTAssertNil(swipe.translation(x: 3, y: 25, width: 390))
        XCTAssertNil(swipe.translation(x: 200, y: 30, width: 390))
        XCTAssertNil(swipe.releaseDirection(x: 200, predictedX: 350, width: 390))
    }

    func testDiagonalMovementDoesNotPage() {
        var swipe = PanelSwipeState()
        XCTAssertNil(swipe.translation(x: 20, y: 20, width: 390))
        XCTAssertNil(swipe.releaseDirection(x: 200, predictedX: 300, width: 390))
    }

    func testShortReleaseCancelsButDeliberateFlickWorksBothWays() {
        for sign in [-1.0, 1.0] {
            var swipe = PanelSwipeState()
            _ = swipe.translation(x: 30 * sign, y: 0, width: 390)
            XCTAssertNil(swipe.releaseDirection(x: 30 * sign, predictedX: 40 * sign, width: 390))
            XCTAssertNil(swipe.releaseDirection(x: 12 * sign, predictedX: 500 * sign, width: 390))
            XCTAssertEqual(swipe.releaseDirection(x: 30 * sign, predictedX: 150 * sign, width: 390), Int(sign))
            XCTAssertNil(swipe.releaseDirection(x: 30 * sign, predictedX: -150 * sign, width: 390))
        }
    }

    func testReversingDirectionTracksFingerAndUsesReleaseDirection() {
        var swipe = PanelSwipeState()
        XCTAssertEqual(swipe.translation(x: 100, y: 0, width: 390), 100)
        XCTAssertEqual(swipe.translation(x: -110, y: 0, width: 390), -110)
        XCTAssertEqual(swipe.releaseDirection(x: -110, predictedX: -110, width: 390), -1)
    }

    func testLandscapeDoesNotRequireDraggingAcrossEntireScreen() {
        var swipe = PanelSwipeState()
        _ = swipe.translation(x: 121, y: 0, width: 844)
        XCTAssertEqual(swipe.releaseDirection(x: 121, predictedX: 121, width: 844), 1)
    }

    func testResetAllowsNewAxisAndRejectsInvalidGeometry() {
        var swipe = PanelSwipeState()
        XCTAssertNil(swipe.translation(x: 5, y: 5, width: 390))
        XCTAssertNil(swipe.translation(x: .nan, y: 0, width: 390))
        XCTAssertNil(swipe.translation(x: 50, y: 0, width: 0))
        XCTAssertNil(swipe.axis)
        _ = swipe.translation(x: 0, y: 20, width: 390)
        swipe = PanelSwipeState()
        XCTAssertEqual(swipe.translation(x: 30, y: 0, width: 390), 30)
    }

    func testUnavailableProgrammeMovementStaysSmallEvenPastTheOpeningThreshold() {
        let threshold = PanelSwipeState.openingThreshold(width: 390)
        let initial = PanelSwipeState.unavailableProgrammeMotion(20)
        let crossing = PanelSwipeState.unavailableProgrammeMotion(threshold)
        let long = PanelSwipeState.unavailableProgrammeMotion(390)
        XCTAssertGreaterThan(initial.offset, 0)
        XCTAssertGreaterThan(crossing.offset, initial.offset)
        XCTAssertLessThanOrEqual(long.offset, 16)
        XCTAssertGreaterThan(long.offset, crossing.offset)
        XCTAssertLessThan(crossing.slope, initial.slope)
        XCTAssertEqual(PanelSwipeState.unavailableProgrammeMotion(-30).offset, 0)
    }
    func testLightResistanceRespondsImmediatelyAndLosesAtMostThreePoints() {
        for width in [320.0, 402, 844] {
            var previous = 0.0
            for distance in [1.0, 6, 12, 24, 80, width] {
                let position = PanelSwipeState.resistedTranslation(distance, width: width)
                XCTAssertGreaterThanOrEqual(position, distance * 0.8)
                XCTAssertLessThanOrEqual(position, distance + 0.001)
                XCTAssertLessThanOrEqual(distance - position, 3)
                XCTAssertGreaterThan(position, previous)
                XCTAssertEqual(PanelSwipeState.resistedTranslation(-distance, width: width), -position)
                previous = position
            }
            XCTAssertEqual(PanelSwipeState.resistedTranslation(width, width: width), width, accuracy: 0.001)
        }
    }

    func testResistanceVelocityMatchesInteriorDerivativeIncludingDirectionChanges() {
        let width = 402.0
        for x in [-300.0, -20, -0.001, 0, 0.001, 20, 300] {
            let epsilon = 0.0001
            let derivative = (PanelSwipeState.resistedTranslation(x + epsilon, width: width)
                              - PanelSwipeState.resistedTranslation(x - epsilon, width: width)) / (2 * epsilon)
            for velocity in [-800.0, 0, 800] {
                XCTAssertEqual(PanelSwipeState.resistedVelocity(velocity, at: x, width: width),
                               velocity * derivative, accuracy: 0.0001)
            }
        }
        let step = 0.01
        let leftCurvature = (PanelSwipeState.resistedTranslation(-2 * step, width: width)
                             - 2 * PanelSwipeState.resistedTranslation(-step, width: width)) / (step * step)
        let rightCurvature = (PanelSwipeState.resistedTranslation(2 * step, width: width)
                              - 2 * PanelSwipeState.resistedTranslation(step, width: width)) / (step * step)
        XCTAssertEqual(leftCurvature, rightCurvature, accuracy: 0.0001,
                       "Reversing through zero must not change curvature abruptly")
        XCTAssertEqual(PanelSwipeState.resistedVelocity(.nan, at: 20, width: width), 0)
    }

    func testHeaderRollHasFlatEndsAndSmoothMidpointSnap() {
        XCTAssertEqual(PanelSwipeState.headerProgress(0), 0)
        XCTAssertEqual(PanelSwipeState.headerProgress(1), 1)
        XCTAssertLessThan(PanelSwipeState.headerProgress(0.01), 1e-30)
        XCTAssertEqual(PanelSwipeState.headerProgress(0.5), 0.5, accuracy: 1e-12)
        XCTAssertLessThan(PanelSwipeState.headerProgress(0.25), 0.25)
        XCTAssertGreaterThan(PanelSwipeState.headerProgress(0.75), 0.75)
        let midpointSlope = (PanelSwipeState.headerProgress(0.501) - PanelSwipeState.headerProgress(0.499)) / 0.002
        XCTAssertGreaterThan(midpointSlope, 1.5)
        var previous = 0.0
        for index in 1...100 {
            let p = Double(index) / 100
            let roll = PanelSwipeState.headerProgress(p)
            XCTAssertTrue(roll.isFinite)
            XCTAssertGreaterThanOrEqual(roll, previous)
            XCTAssertEqual(roll + PanelSwipeState.headerProgress(1 - p), 1, accuracy: 1e-12)
            previous = roll
        }
    }

}
