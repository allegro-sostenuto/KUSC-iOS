#if canImport(UIKit) && !canImport(PhilharmonicCore)
import XCTest
@testable import Philharmonic_SE

final class LiveOnlySettingsTests: XCTestCase {
    func testQualityDefaultsToStandardAndPersistsWithoutLosingLegacySettings() throws {
        let suite = "quality-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var original = AppSettings()
        original.autoplay = false; original.appearance = "dark"; original.lastSleepMinutes = 90
        original.scheduledStartDefaults = .init(allowOnBattery: true)
        original.save(to: defaults)
        var loaded = AppSettings.load(from: defaults)
        XCTAssertEqual(loaded.audioQuality, .standard)
        XCTAssertEqual(loaded, original)
        loaded.audioQuality = .high
        loaded.save(to: defaults)
        XCTAssertEqual(AppSettings.load(from: defaults), loaded)
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(loaded)) as? [String: Any])
        fields["audioQualityPreference"] = "future-quality"
        defaults.set(try JSONSerialization.data(withJSONObject: fields), forKey: "settings.v1")
        let future = AppSettings.load(from: defaults)
        XCTAssertEqual(future.audioQuality, .standard)
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
