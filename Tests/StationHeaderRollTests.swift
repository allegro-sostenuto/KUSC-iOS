import XCTest
#if canImport(PhilharmonicCore)
@testable import PhilharmonicCore
#else
@testable import Philharmonic_SE
#endif

final class StationHeaderRollTests: XCTestCase {
    func testNextMovesCurrentUpAndFollowingStationInFromBelow() throws {
        let frame = try XCTUnwrap(StationHeaderRoll.layout(position: 3.5, count: 17))
        XCTAssertEqual(frame.upperIndex, 3)
        XCTAssertEqual(frame.lowerIndex, 4)
        XCTAssertEqual(frame.upperOffset, -22, accuracy: 1e-9)
        XCTAssertEqual(frame.lowerOffset, 22, accuracy: 1e-9)
    }

    func testPreviousWrapsFromFirstToLastAndMovesCurrentDown() throws {
        let frame = try XCTUnwrap(StationHeaderRoll.layout(position: -0.5, count: 17))
        XCTAssertEqual(frame.upperIndex, 16)
        XCTAssertEqual(frame.lowerIndex, 0)
        XCTAssertEqual(frame.upperOffset, -22, accuracy: 1e-9)
        XCTAssertEqual(frame.lowerOffset, 22, accuracy: 1e-9)
        let end = try XCTUnwrap(StationHeaderRoll.layout(position: -1, count: 17))
        XCTAssertEqual(end.upperIndex, 16)
        XCTAssertEqual(end.upperOffset, 0)
    }

    func testRepeatedAndReversedTapsUseUnwrappedPositionsAndSavedCatalogueSize() throws {
        for count in [1, 3, 17] {
            for position in [-35, -17, -1, 0, 1, 16, 17, 18, 35] {
                let frame = try XCTUnwrap(StationHeaderRoll.layout(position: Double(position), count: count))
                XCTAssertEqual(frame.upperIndex, ((position % count) + count) % count)
                XCTAssertEqual(frame.upperOffset, 0)
                XCTAssertTrue((0..<count).contains(frame.lowerIndex))
            }
        }
    }

    func testExternalStationChangesChooseTheNearestUnwrappedTarget() {
        XCTAssertEqual(StationHeaderRoll.position(selecting: 0, from: 16, count: 17), 17)
        XCTAssertEqual(StationHeaderRoll.position(selecting: 16, from: 0, count: 17), -1)
        XCTAssertEqual(StationHeaderRoll.position(selecting: 0, from: -1, count: 17), 0)
        XCTAssertEqual(StationHeaderRoll.position(selecting: 5, from: 21, count: 17), 22)
        XCTAssertEqual(StationHeaderRoll.position(selecting: 4, from: 4, count: 17), 4)
        XCTAssertNil(StationHeaderRoll.position(selecting: 2, from: .nan, count: 17))
        XCTAssertNil(StationHeaderRoll.position(selecting: 2, from: 0, count: 0))
    }

    func testEveryIntermediateFrameJoinsWithoutGapsAndInvalidInputIsIgnored() throws {
        for step in -300...300 {
            let frame = try XCTUnwrap(StationHeaderRoll.layout(position: Double(step) / 100, count: 17))
            XCTAssertEqual(frame.lowerOffset - frame.upperOffset, 44, accuracy: 1e-9)
            XCTAssertTrue((-44...0).contains(frame.upperOffset))
            XCTAssertTrue((0...44).contains(frame.lowerOffset))
        }
        XCTAssertNil(StationHeaderRoll.layout(position: .nan, count: 17))
        XCTAssertNil(StationHeaderRoll.layout(position: .infinity, count: 17))
        XCTAssertNil(StationHeaderRoll.layout(position: 1, count: 0))
    }
}
