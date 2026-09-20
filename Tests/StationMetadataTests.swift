import Foundation
import XCTest
#if canImport(KUSCCore)
@testable import KUSCCore
#else
@testable import KUSC_SE
#endif

final class StationMetadataTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: StationMetadataTests.self)
        #endif
        let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? bundle.url(forResource: name, withExtension: "json")
        return try Data(contentsOf: XCTUnwrap(url, "Missing station fixture \(name).json"))
    }

    func testObservedCombinedResponsePreservesBroadcastFactsAndProgrammeContext() throws {
        let response = try StationMetadataParser.combined(fixture("official-combined-2026-09-19"))
        XCTAssertEqual(response.records.count, 6)
        XCTAssertEqual(response.programmes.count, 1)
        XCTAssertEqual(response.programmes[0].name, "Classical Music with Maggie Clennon Reberg")
        XCTAssertEqual(response.programmes[0].host, "Maggie Clennon Reberg")
        let piece = try XCTUnwrap(response.records.first { $0.item.composer == "Claude Debussy" })
        XCTAssertEqual(piece.item.work, "Prelude to the Afternoon of a Faun L.86")
        XCTAssertEqual(piece.item.performers, "Philharmonia Orchestra · Pablo Heras-Casado")
        XCTAssertEqual(piece.item.programme, response.programmes[0].name)
        XCTAssertEqual(piece.item.host, response.programmes[0].host)
        XCTAssertEqual(piece.item.start, StationMetadataParser.timestamp("2026-09-19T16:49:54Z"))
        XCTAssertEqual(piece.item.end, StationMetadataParser.timestamp("2026-09-19T16:59:32Z"))
        XCTAssertNil(piece.item.movement, "The station supplied no separate movement title.")
    }

    func testNowAndDayFormatsIdentifyTheSameAiringWithoutDuplicatingTimeline() throws {
        let day = try StationMetadataParser.combined(fixture("official-combined-2026-09-19"))
        let current = try XCTUnwrap(StationMetadataParser.now(fixture("official-now-2026-09-19"),
                                                             programmes: day.programmes))
        let history = try XCTUnwrap(day.records.first { $0.item.work == current.item.work })
        XCTAssertEqual(current.item.id, history.item.id)
        XCTAssertEqual(current.item.start, history.item.start)
        XCTAssertEqual(current.item.end, history.item.end)
        XCTAssertEqual(current.item.host, "Maggie Clennon Reberg")
        var timeline = PlaybackTimeline(items: day.records.map(\.item))
        timeline.merge([current.item])
        XCTAssertEqual(timeline.items.count, 6)
        XCTAssertEqual(timeline.item(at: current.item.start)?.id, current.item.id)
    }

    func testTimezoneAndFractionalTimestampFormatsReferToSameInstant() {
        let utc = StationMetadataParser.timestamp("2026-09-19T16:49:54Z")
        XCTAssertNotNil(utc)
        XCTAssertEqual(utc, StationMetadataParser.timestamp("2026-09-19T09:49:54-07:00"))
        XCTAssertEqual(utc, StationMetadataParser.timestamp(["dateTime": "2026-09-19T16:49:54.000Z"]))
        XCTAssertNil(StationMetadataParser.timestamp("not a timestamp"))
        XCTAssertNil(StationMetadataParser.timestamp(NSNull()))
    }

    func testMalformedRowDoesNotEraseUsableDayHistoryAndSpeechIsExcluded() throws {
        var blocks = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("official-combined-2026-09-19")) as? [[String: Any]])
        var songs = try XCTUnwrap(blocks[0]["songs"] as? [[String: Any]])
        songs.append(["name": "Bad row", "start": "yesterday"])
        songs.append(["name": "Station announcement", "start": "2026-09-19T17:00:00Z",
                      "extraInfo": ["media_type": "Announcement"]])
        blocks[0]["songs"] = songs
        let result = try StationMetadataParser.combined(JSONSerialization.data(withJSONObject: blocks))
        XCTAssertEqual(result.records.count, 6)
    }

    func testMissingOrReversedEndDoesNotSupplyReliableSleepTiming() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("official-now-2026-09-19")) as? [String: Any])
        var extra = try XCTUnwrap(object["extraInfo"] as? [String: Any])
        object.removeValue(forKey: "end")
        extra.removeValue(forKey: "AirStoptime")
        object["extraInfo"] = extra
        let missing = try XCTUnwrap(StationMetadataParser.now(JSONSerialization.data(withJSONObject: object), programmes: []))
        XCTAssertNil(missing.item.end)
        XCTAssertFalse(missing.item.timingReliable)
        extra["AirStoptime"] = "2026-09-19T16:40:00Z"
        object["extraInfo"] = extra
        let reversed = try XCTUnwrap(StationMetadataParser.now(JSONSerialization.data(withJSONObject: object), programmes: []))
        XCTAssertNil(reversed.item.end)
        XCTAssertFalse(reversed.item.timingReliable)
    }

    func testWrongTopLevelShapeFailsInsteadOfInventingMetadata() {
        XCTAssertThrowsError(try StationMetadataParser.combined(Data("{}".utf8)))
        XCTAssertThrowsError(try StationMetadataParser.now(Data("[]".utf8), programmes: []))
        XCTAssertThrowsError(try StationMetadataParser.combined(Data("{truncated".utf8)))
    }
}
