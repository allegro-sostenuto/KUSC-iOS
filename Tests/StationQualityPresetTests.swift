import XCTest
#if canImport(PhilharmonicCore)
@testable import PhilharmonicCore
#else
@testable import Philharmonic_SE
#endif

final class StationQualityPresetTests: XCTestCase {
    func testExtremesUseActualAvailableBitratesForEveryStation() {
        for station in StationCatalog.stations {
            XCTAssertEqual(StationQualityPreset.lowest.source(for: station).bitrateKbps,
                           station.audioSources.map(\.bitrateKbps).min())
            XCTAssertEqual(StationQualityPreset.highest.source(for: station).bitrateKbps,
                           station.audioSources.map(\.bitrateKbps).max())
            for preset in StationQualityPreset.allCases {
                XCTAssertTrue(station.audioSources.contains(preset.source(for: station)))
            }
        }
    }

    func testBalancedUsesKUSCTargetAndAvailabilityBreaksEqualDistanceTies() throws {
        XCTAssertEqual(StationCatalog.defaultStation.defaultAudioSource.bitrateKbps, 96)
        for (id, expected) in [("radio-swiss-classic", 96), ("sr-p2", 128), ("yle-klassinen", 64),
                               ("orpheus-camerata", 64), ("wdr3", 96), ("wfmt", 128)] {
            let station = try XCTUnwrap(StationCatalog.station(id: id))
            XCTAssertEqual(StationQualityPreset.balanced.source(for: station).bitrateKbps, expected, id)
        }
    }

    func testEqualBitratesPreferTheExistingDefaultFormatAndSingleSourcesStayUnchanged() throws {
        let wfmt = try XCTUnwrap(StationCatalog.station(id: "wfmt"))
        for preset in StationQualityPreset.allCases {
            XCTAssertEqual(preset.source(for: wfmt).format, .aac)
            for station in StationCatalog.stations where station.audioSources.count == 1 {
                XCTAssertEqual(preset.source(for: station), station.defaultAudioSource)
            }
        }
    }
}
