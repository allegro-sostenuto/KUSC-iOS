import XCTest
#if canImport(PhilharmonicCore)
@testable import PhilharmonicCore
#else
@testable import Philharmonic_SE
#endif

final class StationGeographyTests: XCTestCase {
    func testEveryStationHasOneValidBaseCityInItsCountry() {
        let groups = StationGeography.groups(stations: StationCatalog.stations)
        XCTAssertEqual(groups.count, 14)
        XCTAssertEqual(groups.flatMap(\.stations).count, StationCatalog.stations.count)
        for station in StationCatalog.stations {
            let city = StationGeography.city(for: station)
            XCTAssertNotNil(city, station.id)
            XCTAssertEqual(city?.countryCode, station.countryCode)
            XCTAssertTrue((-90...90).contains(city?.latitude ?? 100))
            XCTAssertTrue((-180...180).contains(city?.longitude ?? 200))
        }
        XCTAssertEqual(groups.first { $0.id == "paris" }?.stations.count, 2)
        XCTAssertEqual(groups.first { $0.id == "moscow" }?.stations.count, 3)
        XCTAssertEqual(StationGeography.city(for: StationCatalog.station(id: "rete-toscana-classica")!)?.name, "Prato")
    }

    func testCityListsPreserveSavedStationOrder() {
        let stations = Array(StationCatalog.stations.reversed())
        let groups = StationGeography.groups(stations: stations)
        XCTAssertEqual(groups.first?.id, "utrecht")
        XCTAssertEqual(groups.first { $0.id == "moscow" }?.stations.map(\.id),
                       ["orpheus-camerata", "orpheus-russian-classical", "orpheus-large-scale"])
    }

    func testGestureZoomCrossesBothThresholdsWithoutBoundaryFlicker() {
        func follow(_ current: StationMapZoom, _ distance: Double) -> StationMapZoom {
            current.following(distance: distance, continentDistance: 16_000_000, countryDistance: 4_000_000)
        }
        XCTAssertEqual(follow(.globe, 45_000_000), .globe)
        XCTAssertEqual(follow(.globe, 20_000_000), .continent)
        XCTAssertEqual(follow(.continent, 4_000_000), .country)
        XCTAssertEqual(follow(.country, 16_000_000), .continent)
        XCTAssertEqual(follow(.continent, 45_000_000), .globe)
        XCTAssertEqual(follow(.globe, 4_000_000), .country, "A continuous fast pinch can cross both boundaries")
        XCTAssertEqual(follow(.country, 8_100_000), .country)
        XCTAssertEqual(follow(.continent, 7_900_000), .continent)
        XCTAssertEqual(follow(.continent, .nan), .continent)
        XCTAssertEqual(follow(.country, 0), .country)
    }

    func testCountryFramingContainsEveryStationCityIncludingBothUSCities() throws {
        for city in StationGeography.cities {
            let camera = StationMapZoom.country.camera(focusing: city)
            let span = try XCTUnwrap(StationMapZoom.country.span(focusing: city))
            for other in StationGeography.cities where other.countryCode == city.countryCode {
                XCTAssertLessThan(abs(other.latitude - camera.latitude), span.latitude / 2, other.name)
                XCTAssertLessThan(abs(other.longitude - camera.longitude), span.longitude / 2, other.name)
            }
        }
    }

    func testThreeProgressivelyCloserZoomsAndLongitudeWrap() throws {
        XCTAssertEqual(StationMapZoom.allCases, [.globe, .continent, .country])
        for city in StationGeography.cities {
            let globe = StationMapZoom.globe.camera(focusing: city)
            let continent = StationMapZoom.continent.camera(focusing: city)
            let country = StationMapZoom.country.camera(focusing: city)
            XCTAssertGreaterThan(globe.distance, continent.distance)
            XCTAssertGreaterThan(continent.distance, country.distance)
        }
        XCTAssertEqual(StationGeography.nearestCity(latitude: 34.0522, longitude: 241.7563).id, "los-angeles")
        var preferences = StationPreferences(displayMode: .map)
        preferences.move(id: "wfmt", by: -100)
        let restored = try JSONDecoder().decode(StationPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(restored, preferences)
        XCTAssertEqual(restored.displayMode, .map)
    }
}
