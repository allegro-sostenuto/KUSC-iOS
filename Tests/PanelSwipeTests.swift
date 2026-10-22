import XCTest
#if canImport(KUSCCore)
@testable import KUSCCore
#else
@testable import KUSC_SE
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
            XCTAssertNil(swipe.releaseDirection(x: 20 * sign, predictedX: 500 * sign, width: 390))
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
}
