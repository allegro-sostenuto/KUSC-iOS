import Foundation
import XCTest
#if canImport(PhilharmonicCore)
@testable import PhilharmonicCore
#else
@testable import Philharmonic_SE
#endif

final class BroadcastMetadataTests: XCTestCase {
    func testP2FeedHasExplicitUTCWorkBoundsAndNoInventedArtwork() throws {
        let items = try BroadcastMetadataParser.srP2(fixture("sr-p2-now", extension: "json"))
        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items.allSatisfy { $0.end != nil && $0.timingReliable && $0.artworkURL == nil })
        XCTAssertTrue(items.allSatisfy { !$0.work.isEmpty && !$0.composer.isEmpty })
        XCTAssertEqual(BroadcastMetadataParser.srDate("/Date(1793618054000)/"), Date(timeIntervalSince1970: 1793618054))
        XCTAssertNil(BroadcastMetadataParser.srDate("missing"))
    }

    func testP2RejectsAnotherChannelAndMissingTimestamps() throws {
        let data = Data(#"{"playlist":{"channel":{"id":163},"song":{"title":"Other channel","starttimeutc":"/Date(1000)/"}}}"#.utf8)
        XCTAssertTrue(try BroadcastMetadataParser.srP2(data).isEmpty)
        let missing = Data(#"{"playlist":{"channel":{"id":2562},"song":{"title":"Untimed work"}}}"#.utf8)
        XCTAssertTrue(try BroadcastMetadataParser.srP2(missing).isEmpty)
    }

    func testHRTFiltersStationIDsButTheyStillClosePreviousWork() throws {
        let items = try BroadcastMetadataParser.hrt(fixture("hr-klasik-now", extension: "xml"))
        XCTAssertFalse(items.isEmpty)
        XCTAssertTrue(items.allSatisfy { $0.work.uppercased() != "HRVATSKI RADIO" && $0.performers.uppercased() != "HR KLASIK" })
        XCTAssertTrue(items.allSatisfy { !$0.timingReliable && $0.artworkURL == nil })
        XCTAssertEqual(items.last?.composer, "PETAR ILJIČ ČAJKOVSKI")
        XCTAssertNil(items.last?.end, "No broadcast end is fabricated for the last item")
        let earlier = try XCTUnwrap(items.first(where: { $0.start.timeIntervalSince1970 == 1793617292.265 }))
        XCTAssertEqual(try XCTUnwrap(earlier.end).timeIntervalSince1970, 1793617630.087, accuracy: 0.001)
    }

    func testMalformedFeedsFailWithoutProducingPlaceholderMusic() {
        XCTAssertThrowsError(try BroadcastMetadataParser.hrt(Data("<broken".utf8)))
        XCTAssertThrowsError(try BroadcastMetadataParser.srP2(Data("{}".utf8)))
    }

    func testScheduledStationMigratesAndSurvivesRoundTrip() throws {
        let request = ScheduledStartRequest(date: Date(timeIntervalSince1970: 1234), stationID: "hr-klasik")
        let data = try JSONEncoder().encode(request)
        XCTAssertEqual(try JSONDecoder().decode(ScheduledStartRequest.self, from: data).stationID, "hr-klasik")
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "stationID")
        XCTAssertEqual(try JSONDecoder().decode(ScheduledStartRequest.self,
            from: JSONSerialization.data(withJSONObject: legacy)).stationID, "kusc")
        legacy["stationID"] = "retired-station"
        XCTAssertEqual(try JSONDecoder().decode(ScheduledStartRequest.self,
            from: JSONSerialization.data(withJSONObject: legacy)).stationID, "kusc")
    }

    private func fixture(_ name: String, extension suffix: String) throws -> Data {
        #if SWIFT_PACKAGE
        let url = Bundle.module.url(forResource: name, withExtension: suffix, subdirectory: "Fixtures")
        #else
        let url = Bundle(for: Self.self).url(forResource: name, withExtension: suffix)
        #endif
        return try Data(contentsOf: XCTUnwrap(url))
    }
}
