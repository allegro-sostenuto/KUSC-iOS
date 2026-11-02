import Foundation
import XCTest
#if canImport(PhilharmonicCore)
@testable import PhilharmonicCore
#else
@testable import Philharmonic_SE
#endif

final class StationCatalogTests: XCTestCase {
    func testApprovedCatalogueMatchesPortableParityFixture() throws {
        #if SWIFT_PACKAGE
        let url = try XCTUnwrap(Bundle.module.url(forResource: "station-catalog", withExtension: "json", subdirectory: "Fixtures"))
        #else
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "station-catalog", withExtension: "json"))
        #endif
        let stations = try JSONDecoder().decode([RadioStation].self, from: Data(contentsOf: url))
        XCTAssertEqual(stations, StationCatalog.stations)
        XCTAssertEqual(stations.count, 11)
        XCTAssertEqual(Set(stations.map(\.id)).count, 11)
        XCTAssertTrue(stations.allSatisfy { $0.audioURL.scheme == "https" && $0.websiteURL.scheme == "https" })
        XCTAssertTrue(stations.allSatisfy { TimeZone(identifier: $0.timeZoneIdentifier) != nil })
        XCTAssertEqual(stations.filter { $0.id.hasPrefix("orpheus-") }.count, 3)
        XCTAssertEqual(stations.filter { $0.id.hasPrefix("france-musique-") }.count, 2)
        XCTAssertEqual(StationCatalog.defaultStation.id, "kusc")
    }

    func testUpgradeDefaultsToKUSCWithoutChangingExistingPreferences() throws {
        let suite = "station-upgrade-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data([1, 2, 3]), forKey: "settings.v1")
        defaults.set("existing-request", forKey: "schedule.v1")
        let preferences = StationPreferences.load(defaults: defaults)
        XCTAssertEqual(preferences.selectedID, "kusc")
        XCTAssertEqual(preferences.orderedIDs, StationCatalog.stations.map(\.id))
        XCTAssertEqual(defaults.data(forKey: "settings.v1"), Data([1, 2, 3]))
        XCTAssertEqual(defaults.string(forKey: "schedule.v1"), "existing-request")
    }

    func testOrderMigrationDeduplicatesDropsUnknownAndAppendsNewChannels() {
        let preferences = StationPreferences(selectedID: "retired-channel", orderedIDs: ["wdr3", "wdr3", "retired-channel", "kusc"])
        XCTAssertEqual(preferences.selectedID, "kusc")
        XCTAssertEqual(Array(preferences.orderedIDs.prefix(2)), ["wdr3", "kusc"])
        XCTAssertEqual(preferences.orderedIDs.count, 11)
        XCTAssertEqual(Set(preferences.orderedIDs), Set(StationCatalog.stations.map(\.id)))
    }

    func testReorderingAndModePersistWithoutChangingSelectedStation() throws {
        let suite = "station-order-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var preferences = StationPreferences(selectedID: "wdr3")
        preferences.move(id: "wdr3", by: -5)
        XCTAssertEqual(preferences.orderedIDs.first, "wdr3")
        preferences.move(id: "hr-klasik", before: "kusc")
        preferences.displayMode = .list
        preferences.save(defaults: defaults)
        XCTAssertEqual(StationPreferences.load(defaults: defaults), preferences)
        XCTAssertEqual(preferences.selectedID, "wdr3")
    }

    func testMalformedModeDoesNotDiscardValidSelectionOrOrder() throws {
        let data = Data(#"{"selectedID":"wdr3","orderedIDs":["wdr3","kusc"],"displayMode":"future-mode"}"#.utf8)
        let preferences = try JSONDecoder().decode(StationPreferences.self, from: data)
        XCTAssertEqual(preferences.selectedID, "wdr3")
        XCTAssertEqual(Array(preferences.orderedIDs.prefix(2)), ["wdr3", "kusc"])
        XCTAssertEqual(preferences.displayMode, .grid)
    }

    func testStationTransportWrapsInSavedOrderAndMoveActionsStopAtEnds() {
        var preferences = StationPreferences()
        preferences.move(id: "hr-klasik", by: -100)
        XCTAssertEqual(preferences.orderedIDs.first, "hr-klasik")
        let last = preferences.orderedIDs.last!
        XCTAssertEqual(preferences.adjacent(to: "hr-klasik", offset: -1), last)
        XCTAssertEqual(preferences.adjacent(to: last, offset: 1), "hr-klasik")
        XCTAssertEqual(preferences.adjacent(to: last, offset: 12), "hr-klasik")
        preferences.move(id: "hr-klasik", by: -1)
        XCTAssertEqual(preferences.orderedIDs.first, "hr-klasik")
        preferences.move(id: "hr-klasik", by: Int.max)
        XCTAssertEqual(preferences.orderedIDs.last, "hr-klasik")
    }

    func testStationBroadcastDayUsesStationTimeZoneAcrossShanghaiAndDSTBoundaries() throws {
        let losAngeles = try XCTUnwrap(StationCatalog.station(id: "kusc"))
        let zurich = try XCTUnwrap(StationCatalog.station(id: "radio-swiss-classic"))
        let formatter = ISO8601DateFormatter()
        let shanghaiMidnight = try XCTUnwrap(formatter.date(from: "2026-11-01T16:10:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = losAngeles.timeZone
        XCTAssertEqual(calendar.component(.day, from: shanghaiMidnight), 1)
        XCTAssertEqual(calendar.component(.hour, from: shanghaiMidnight), 8)
        calendar.timeZone = zurich.timeZone
        XCTAssertEqual(calendar.component(.hour, from: shanghaiMidnight), 17)
        let summer = try XCTUnwrap(formatter.date(from: "2026-07-01T00:00:00Z"))
        XCTAssertEqual(losAngeles.timeZone.secondsFromGMT(for: summer), -7 * 3600)
        XCTAssertEqual(zurich.timeZone.secondsFromGMT(for: summer), 2 * 3600)
        XCTAssertEqual(losAngeles.timeZone.secondsFromGMT(for: shanghaiMidnight), -8 * 3600)
        XCTAssertEqual(zurich.timeZone.secondsFromGMT(for: shanghaiMidnight), 3600)
    }
}
