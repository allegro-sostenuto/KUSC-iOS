#if canImport(UIKit) && !canImport(PhilharmonicCore)
import XCTest
@testable import Philharmonic_SE

final class LiveOnlySettingsTests: XCTestCase {
    func testMapStyleAndExplicitPresetPersistWithoutChangingOlderPreferences() throws {
        let suite = "map-quality-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = AppSettings()
        settings.autoplay = false; settings.appearance = "dark"
        settings.scheduledStartDefaults = .init(allowOnBattery: true)
        settings.save(to: defaults)
        XCTAssertEqual(AppSettings.load(from: defaults).stationMapStyle, .satellite)
        XCTAssertNil(AppSettings.load(from: defaults).audioQualityPreset)
        settings.stationMapStyle = .political
        settings.audioQualityPreset = .highest
        settings.save(to: defaults)
        XCTAssertEqual(AppSettings.load(from: defaults), settings)
        settings.audioQualityPreset = nil
        settings.save(to: defaults)
        XCTAssertNil(AppSettings.load(from: defaults).audioQualityPreset)
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        fields["stationMapAppearance"] = "future-style"
        fields["appliedAudioQualityPreset"] = "future-preset"
        defaults.set(try JSONSerialization.data(withJSONObject: fields), forKey: "settings.v1")
        let restored = AppSettings.load(from: defaults)
        XCTAssertEqual(restored.stationMapStyle, .satellite)
        XCTAssertNil(restored.audioQualityPreset)
        XCTAssertFalse(restored.autoplay)
        XCTAssertEqual(restored.appearance, "dark")
        XCTAssertEqual(restored.scheduledStartDefaults, settings.scheduledStartDefaults)
    }

    func testPerStationQualityPersistsWithoutLosingLegacySettings() throws {
        let suite = "quality-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var original = AppSettings()
        original.autoplay = false; original.appearance = "dark"; original.lastSleepMinutes = 90
        original.scheduledStartDefaults = .init(allowOnBattery: true)
        original.save(to: defaults)
        var loaded = AppSettings.load(from: defaults)
        let swiss = try XCTUnwrap(StationCatalog.station(id: "radio-swiss-classic"))
        let p2 = try XCTUnwrap(StationCatalog.station(id: "sr-p2"))
        XCTAssertEqual(loaded.audioSource(for: swiss).bitrateKbps, 96)
        XCTAssertEqual(loaded, original)
        loaded.setAudioSource("aac-192", for: swiss)
        loaded.setAudioSource("aac-32", for: p2)
        loaded.save(to: defaults)
        XCTAssertEqual(AppSettings.load(from: defaults), loaded)
        XCTAssertEqual(AppSettings.load(from: defaults).audioSource(for: swiss).bitrateKbps, 192)
        XCTAssertEqual(AppSettings.load(from: defaults).audioSource(for: p2).bitrateKbps, 32)
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(loaded)) as? [String: Any])
        fields["stationAudioSources"] = [swiss.id: "retired-source", p2.id: "aac-32"]
        defaults.set(try JSONSerialization.data(withJSONObject: fields), forKey: "settings.v1")
        let future = AppSettings.load(from: defaults)
        XCTAssertEqual(future.audioSource(for: swiss).bitrateKbps, 96)
        XCTAssertEqual(future.audioSource(for: p2).bitrateKbps, 32)
        XCTAssertFalse(future.autoplay)
        XCTAssertEqual(future.appearance, "dark")
        XCTAssertEqual(future.lastSleepMinutes, 90)
        XCTAssertEqual(future.scheduledStartDefaults, original.scheduledStartDefaults)
    }

    func testOldHistoryAndResumePreferencesAreRemovedWithoutLosingOtherSettings() throws {
        let suite = "kusc-live-only-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var original = AppSettings()
        original.autoplay = false
        original.minimalist = true
        original.appearance = "dark"
        original.lastSleepMinutes = 90
        original.scheduledStartDefaults = .init(allowOnBattery: true)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        legacy["retentionMinutes"] = 15
        legacy["resumeWherePaused"] = true
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: "settings.v1")

        let migrated = AppSettings.load(from: defaults)
        XCTAssertEqual(migrated, original)
        XCTAssertEqual(migrated.retentionMinutes, 0)
        XCTAssertFalse(migrated.resumeWherePaused)
        let saved = try XCTUnwrap(defaults.data(forKey: "settings.v1"))
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertNil(fields["retentionMinutes"])
        XCTAssertNil(fields["resumeWherePaused"])
        XCTAssertEqual(AppSettings.load(from: defaults), migrated, "Migration must remain stable on another launch")
    }
}
#endif
