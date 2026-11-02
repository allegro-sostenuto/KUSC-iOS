#if canImport(UIKit) && !canImport(PhilharmonicCore)
import XCTest
@testable import Philharmonic_SE

final class LiveOnlySettingsTests: XCTestCase {
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
