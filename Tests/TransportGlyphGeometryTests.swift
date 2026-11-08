import XCTest
#if canImport(PhilharmonicCore)
@testable import PhilharmonicCore
#else
@testable import Philharmonic_SE
#endif

final class TransportGlyphGeometryTests: XCTestCase {
    func testEveryMorphFrameRetainsTwoFiniteConvexSolidOutlines() {
        for step in 0...200 {
            let geometry = TransportGlyphGeometry(progress: Double(step) / 200)
            XCTAssertEqual(geometry.outlines.count, 2)
            for outline in geometry.outlines {
                XCTAssertEqual(outline.count, 4)
                var area = 0.0
                for index in outline.indices {
                    let point = outline[index], next = outline[(index + 1) % 4]
                    let after = outline[(index + 2) % 4]
                    XCTAssertTrue(point.x.isFinite && point.y.isFinite)
                    XCTAssertTrue((0...1).contains(point.x) && (0...1).contains(point.y))
                    area += point.x * next.y - point.y * next.x
                    let cross = (next.x - point.x) * (after.y - next.y) - (next.y - point.y) * (after.x - next.x)
                    XCTAssertGreaterThanOrEqual(cross, -1e-12, "Morph must not fold an outline inside out")
                }
                XCTAssertGreaterThan(area, 0)
            }
        }
    }

    func testPlayJoinsAtTheSeamAndPauseSeparatesBarsWithoutChangingTopologyMidway() {
        let play = TransportGlyphGeometry(progress: 0)
        XCTAssertEqual(play.outlines[0][1], play.outlines[1][0])
        XCTAssertEqual(play.outlines[0][2], play.outlines[1][3])
        let pause = TransportGlyphGeometry(progress: 1)
        XCTAssertLessThan(pause.outlines[0][1].x, pause.outlines[1][0].x)
        XCTAssertEqual(pause.outlines[0][0].y, pause.outlines[1][0].y)
        let middle = TransportGlyphGeometry(progress: 0.5)
        XCTAssertNotEqual(middle.outlines, play.outlines)
        XCTAssertNotEqual(middle.outlines, pause.outlines)
        XCTAssertEqual(TransportGlyphGeometry(progress: .nan).outlines, play.outlines)
    }
}
