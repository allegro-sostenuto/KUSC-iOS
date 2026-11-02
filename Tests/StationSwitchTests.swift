#if canImport(UIKit) && !canImport(PhilharmonicCore) && DEBUG
import XCTest
import UIKit
@testable import Philharmonic_SE

/// Hosted coordinator boundaries. The fixture intercepts session activation and
/// connection starts; these tests never contact a station or emit audio.
final class StationSwitchTests: XCTestCase {
    @MainActor func testRapidPausedSelectionClearsOldMetadataAndArtworkWithoutStartingAudio() {
        let (model, restore) = fixture(playing: false)
        defer { restore() }
        model.selectStation("kusc")
        model.currentItem = .init(id: "old-station", start: Date(), work: "Old work", composer: "Old composer")
        model.previousItems = [model.currentItem!]
        model.upcomingItems = [model.currentItem!]
        model.programmeName = "Old programme"; model.hostName = "Old host"
        model.artwork = UIImage(systemName: "music.note")

        for id in ["radio-swiss-classic", "sr-p2", "wdr3"] {
            model.selectStation(id)
            XCTAssertEqual(model.selectedStation.id, id)
            XCTAssertFalse(model.isPlaying)
            XCTAssertFalse(model.isAudible)
            XCTAssertNil(model.currentItem)
            XCTAssertNil(model.artwork)
            XCTAssertNil(model.programmeName)
            XCTAssertNil(model.hostName)
            XCTAssertTrue(model.previousItems.isEmpty)
            XCTAssertTrue(model.upcomingItems.isEmpty)
        }
        XCTAssertEqual(model.audioRecoveryStateForTesting.connections, 0)
    }

    @MainActor func testPlayingSwitchPreservesIntentAndPauseWinsOverFurtherSelections() {
        let (model, restore) = fixture(playing: false)
        defer { restore() }
        model.selectStation("kusc")
        model.configureAudioRecoveryForTesting(playing: true)
        model.selectStation("radio-swiss-classic")
        model.selectStation("sr-p2")
        XCTAssertTrue(model.isPlaying)
        XCTAssertEqual(model.audioRecoveryStateForTesting.connections, 2)
        let activeSession = model.audioRecoveryStateForTesting.engineGeneration
        model.selectStation("sr-p2")
        XCTAssertEqual(model.audioRecoveryStateForTesting.connections, 2, "Selecting the active station is idempotent")
        XCTAssertEqual(model.audioRecoveryStateForTesting.engineGeneration, activeSession)

        model.pauseRemote()
        model.selectStation("wdr3")
        model.endAudioInterruptionForTesting(shouldResume: true)
        XCTAssertFalse(model.isPlaying)
        XCTAssertFalse(model.isAudible)
        XCTAssertEqual(model.audioRecoveryStateForTesting.connections, 2)
    }

    @MainActor func testReorderingChangesNavigationOrderWithoutReconnectingCurrentAudio() {
        let (model, restore) = fixture(playing: true)
        defer { restore() }
        let stationID = model.selectedStation.id
        let session = model.audioRecoveryStateForTesting.engineGeneration
        let connections = model.audioRecoveryStateForTesting.connections
        model.moveStation("wdr3", before: "kusc")
        model.moveStation("sr-p2", by: 1)
        model.setStationDisplayMode(.list)
        XCTAssertEqual(model.selectedStation.id, stationID)
        XCTAssertEqual(model.audioRecoveryStateForTesting.engineGeneration, session)
        XCTAssertEqual(model.audioRecoveryStateForTesting.connections, connections)
        XCTAssertTrue(model.isPlaying)
        let expected = model.stationPreferences.adjacent(to: stationID, offset: 1)
        model.nextStation()
        XCTAssertEqual(model.selectedStation.id, expected)
        model.previousStation()
        XCTAssertEqual(model.selectedStation.id, stationID)
    }

    @MainActor func testStaleStationWidgetAndActivityCommandsCannotStartAnotherStation() {
        let (model, restore) = fixture(playing: false)
        defer { restore() }
        model.selectStation("radio-swiss-classic")
        model.handleStationPlaybackIntent(playing: true, stationID: "kusc")
        model.handleStationPlaybackIntent(playing: nil, stationID: "kusc")
        model.handleStationLiveIntent(stationID: "kusc")
        XCTAssertEqual(model.selectedStation.id, "radio-swiss-classic")
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(model.audioRecoveryStateForTesting.connections, 0)
        model.handleStationPlaybackIntent(playing: true, stationID: "radio-swiss-classic")
        XCTAssertTrue(model.isPlaying)
        model.handleStationPlaybackIntent(playing: false, stationID: "radio-swiss-classic")
        XCTAssertFalse(model.isPlaying)
    }

    @MainActor func testSavedStartUsesCapturedStationAfterBrowsingBeforeAndDuringPreparation() {
        let (model, restore) = fixture(playing: false)
        defer { restore() }
        model.selectStation("radio-swiss-classic")
        model.configureScheduleForTesting(secondsUntilStart: 120, environment: .init(
            now: Date(), uptime: 1000, plugged: true, level: 1,
            route: .init(ports: [.init(uid: "speaker", type: "Speaker", name: "iPhone")])))
        XCTAssertEqual(model.scheduledStation.id, "radio-swiss-classic")
        model.selectStation("sr-p2")
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(model.scheduledStation.id, "radio-swiss-classic")
        model.advanceScheduleForTesting(seconds: 60)
        XCTAssertEqual(model.selectedStation.id, "radio-swiss-classic")
        XCTAssertTrue(model.isPlaying)
        model.selectStation("wdr3")
        model.advanceScheduleForTesting(seconds: 60)
        XCTAssertEqual(model.selectedStation.id, "radio-swiss-classic", "Browsing during silent preparation cannot retarget the saved start")
        model.simulateScheduledReadinessForTesting()
        model.runScheduledGainCallbackForTest()
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
        model.advanceScheduleForTesting(seconds: 30)
        model.runScheduledGainCallbackForTest()
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0.5, accuracy: 0.001)
    }

    @MainActor func testCanceledManualRefreshCannotPublishOldProgrammeAfterStationSwitch() async throws {
        let (model, restore) = fixture(playing: false)
        defer { restore() }
        model.selectStation("kusc")
        let refresh = Task { await model.refreshMetadata() }
        try await Task.sleep(nanoseconds: 50_000_000)
        model.selectStation("sr-p2")
        await refresh.value
        XCTAssertEqual(model.selectedStation.id, "sr-p2")
        XCTAssertNil(model.currentItem)
        XCTAssertNil(model.programmeName)
        XCTAssertFalse(model.isPlaying)
    }

    @MainActor private func fixture(playing: Bool) -> (AppModel, @MainActor () -> Void) {
        let model = AppModel.shared
        let preferences = model.stationPreferences
        let saved = UserDefaults.standard.data(forKey: StationPreferences.storageKey)
        let item = model.currentItem, previous = model.previousItems, upcoming = model.upcomingItems
        let programme = model.programmeName, host = model.hostName, artwork = model.artwork
        model.configureAudioRecoveryForTesting(playing: playing)
        return (model, {
            model.finishScheduleForTesting()
            model.selectStation(preferences.selectedID)
            for id in preferences.orderedIDs.reversed() {
                if let first = model.orderedStations.first { model.moveStation(id, before: first.id) }
            }
            model.setStationDisplayMode(preferences.displayMode)
            if let saved { UserDefaults.standard.set(saved, forKey: StationPreferences.storageKey) }
            else { UserDefaults.standard.removeObject(forKey: StationPreferences.storageKey) }
            model.currentItem = item; model.previousItems = previous; model.upcomingItems = upcoming
            model.programmeName = programme; model.hostName = host; model.artwork = artwork
        })
    }
}
#endif
