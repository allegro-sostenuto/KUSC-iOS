#if canImport(UIKit) && !canImport(PhilharmonicCore) && DEBUG
import XCTest
import AVFoundation
@testable import Philharmonic_SE

@MainActor final class SpeakerVolumeSetupTests: XCTestCase {
    func testAlreadySpeakerNeverInterruptsSuspendsRestoresOrReleasesAudio() async {
        let audio = TestSpeakerVolumeSession(speaker: true)
        var suspended = 0, resumed = 0
        var saved: [Float] = []
        let setup = SpeakerVolumeSetup(audio: audio, timeout: 0, suspend: { suspended += 1 },
            resume: { _ in resumed += 1 }, save: { saved.append($0) }, log: { _, _ in })
        await setup.begin()
        XCTAssertEqual(setup.phase, .adjusting)
        audio.volume = 0.63
        await setup.finish(save: true)
        XCTAssertEqual(saved, [0.63])
        XCTAssertEqual(suspended, 0); XCTAssertEqual(resumed, 0)
        XCTAssertTrue(audio.operations.isEmpty)
        XCTAssertEqual(setup.phase, .finished)
    }

    func testOtherOutputInterruptsImmediatelyBeforeSpeakerThenRestoresAndNotifies() async {
        let audio = TestSpeakerVolumeSession()
        var events: [String] = []
        let setup = SpeakerVolumeSetup(audio: audio, timeout: 0,
            suspend: { events.append("suspend") }, resume: { events.append("resume=\($0)") },
            save: { _ in events.append("save") }, log: { _, _ in })
        await setup.begin()
        XCTAssertEqual(audio.operations, ["snapshot", "interrupt", "speaker"])
        XCTAssertTrue(setup.canSave)
        await setup.finish(save: true)
        XCTAssertEqual(audio.operations, ["snapshot", "interrupt", "speaker", "restore", "notify"])
        XCTAssertEqual(events, ["suspend", "save", "resume=true"])
        XCTAssertTrue(setup.previousOutputRestored)
    }

    func testDeniedInterruptionNeverSwitchesOrSavesAndStillRestoresPartialConfiguration() async {
        let audio = TestSpeakerVolumeSession(); audio.failInterruption = true
        var values: [Float] = []
        let setup = SpeakerVolumeSetup(audio: audio, timeout: 0, suspend: {}, resume: { _ in },
                                      save: { values.append($0) }, log: { _, _ in })
        await setup.begin()
        XCTAssertEqual(audio.operations, ["snapshot", "interrupt", "restore", "notify"])
        XCTAssertTrue(values.isEmpty)
        XCTAssertNotNil(setup.message)
        XCTAssertEqual(setup.phase, .finished)
    }

    func testUnconfirmedSpeakerTimesOutWithoutExposingVolumeControlOrSaving() async {
        let audio = TestSpeakerVolumeSession(); audio.confirmSpeaker = false
        var saves = 0
        let setup = SpeakerVolumeSetup(audio: audio, timeout: 0, suspend: {}, resume: { _ in },
                                      save: { _ in saves += 1 }, log: { _, _ in })
        await setup.begin()
        XCTAssertFalse(setup.canSave); XCTAssertEqual(saves, 0)
        XCTAssertEqual(setup.phase, .finished)
        XCTAssertEqual(audio.operations.last, "notify")
    }

    func testCancelRestoresRouteWithoutSaving() async {
        let audio = TestSpeakerVolumeSession()
        var saves = 0
        let setup = SpeakerVolumeSetup(audio: audio, timeout: 0, suspend: {}, resume: { _ in },
                                      save: { _ in saves += 1 }, log: { _, _ in })
        await setup.begin(); await setup.finish(save: false)
        XCTAssertEqual(saves, 0); XCTAssertTrue(setup.previousOutputRestored)
        XCTAssertEqual(audio.operations.last, "notify")
    }

    func testMissingPreviousRouteNeedsPickerAndNeverResumesOnSpeaker() async {
        let audio = TestSpeakerVolumeSession(); audio.restoreRoute = false
        var resumed: [Bool] = []
        let setup = SpeakerVolumeSetup(audio: audio, timeout: 0, suspend: {}, resume: { resumed.append($0) },
                                      save: { _ in }, log: { _, _ in })
        await setup.begin(); await setup.finish(save: true)
        XCTAssertEqual(setup.phase, .restoreOutput)
        XCTAssertTrue(resumed.isEmpty)
        XCTAssertFalse(audio.operations.contains("notify"))
        setup.closeWithoutResuming()
        XCTAssertEqual(resumed, [false]); XCTAssertEqual(audio.operations.last, "notify")
    }

    func testPickerRestorationReleasesExclusiveSessionBeforeResuming() async {
        let audio = TestSpeakerVolumeSession(); audio.restoreRoute = false
        var resumed: [Bool] = []
        let setup = SpeakerVolumeSetup(audio: audio, timeout: 0, suspend: {}, resume: {
            XCTAssertEqual(audio.operations.last, "notify"); resumed.append($0)
        }, save: { _ in }, log: { _, _ in })
        await setup.begin(); await setup.finish(save: true)
        audio.route = audio.original
        await setup.finish(save: false)
        XCTAssertEqual(resumed, [true]); XCTAssertEqual(setup.phase, .finished)
    }

    func testBackgroundCleanupSkipsPickerAndCannotResume() async {
        let audio = TestSpeakerVolumeSession(); audio.restoreRoute = false
        var resumed: [Bool] = []
        let setup = SpeakerVolumeSetup(audio: audio, timeout: 0, suspend: {}, resume: { resumed.append($0) },
                                      save: { _ in }, log: { _, _ in })
        await setup.begin(); audio.foreground = false
        await setup.finish(save: false, allowRoutePicker: false, permitResume: false)
        XCTAssertEqual(setup.phase, .finished); XCTAssertEqual(resumed, [false])
        XCTAssertEqual(audio.operations.last, "notify")
    }

    func testConcurrentCancellationCannotSwitchLateOrReleaseTwice() async {
        let audio = TestSpeakerVolumeSession(); audio.confirmSpeaker = false
        var resumes = 0
        let setup = SpeakerVolumeSetup(audio: audio, timeout: 1, suspend: {}, resume: { _ in resumes += 1 },
                                      save: { _ in XCTFail("Cancelled setup must not save") }, log: { _, _ in })
        let task = Task { await setup.begin() }
        while !audio.operations.contains("speaker") { await Task.yield() }
        await setup.finish(save: false)
        await task.value
        await setup.finish(save: false)
        XCTAssertEqual(audio.operations.filter { $0 == "notify" }.count, 1)
        XCTAssertEqual(resumes, 1); XCTAssertEqual(setup.phase, .finished)
    }

    func testDisappearingDuringCleanupCannotLeaveExclusiveSessionWaitingForInvisiblePicker() async {
        let audio = TestSpeakerVolumeSession(); audio.restoreRoute = false
        var resumed: [Bool] = []
        let setup = SpeakerVolumeSetup(audio: audio, timeout: 0.2, suspend: {}, resume: { resumed.append($0) },
                                      save: { _ in }, log: { _, _ in })
        await setup.begin()
        let cleanup = Task { await setup.finish(save: false) }
        while setup.phase != .restoring { await Task.yield() }
        await setup.finish(save: false, allowRoutePicker: false, permitResume: false)
        await cleanup.value
        XCTAssertEqual(setup.phase, .finished)
        XCTAssertEqual(audio.operations.filter { $0 == "notify" }.count, 1)
        XCTAssertEqual(resumed, [false])
    }

    func testRouteChangeCannotSaveVolumeForTheWrongOutput() async {
        let audio = TestSpeakerVolumeSession(speaker: true)
        let setup = SpeakerVolumeSetup(audio: audio, timeout: 0, suspend: { XCTFail() }, resume: { _ in XCTFail() },
                                      save: { _ in XCTFail() }, log: { _, _ in })
        await setup.begin(); audio.route = .init(ports: [])
        await setup.finish(save: true)
        XCTAssertFalse(setup.canSave)
        await setup.finish(save: false)
        XCTAssertTrue(audio.operations.isEmpty)
    }

    func testModelPauseDuringSetupWinsOverCleanupResumption() async {
        let model = AppModel.shared
        model.configureAudioRecoveryForTesting(playing: true)
        defer { model.finishAudioRecoveryForTesting() }
        let setup = model.makeSpeakerVolumeSetup(audio: TestSpeakerVolumeSession(), timeout: 0)
        await setup.begin()
        XCTAssertEqual(model.scheduledGainBoundaryState.gain, 0)
        model.pauseRemote()
        let count = model.audioRecoveryStateForTesting.connections
        await setup.finish(save: false)
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(model.audioRecoveryStateForTesting.connections, count)
    }

    func testModelRestoresLivePlaybackWithoutChangingUnpausedIntent() async {
        let model = AppModel.shared
        model.configureAudioRecoveryForTesting(playing: true)
        defer { model.finishAudioRecoveryForTesting() }
        let setup = model.makeSpeakerVolumeSetup(audio: TestSpeakerVolumeSession(), timeout: 0)
        await setup.begin(); let count = model.audioRecoveryStateForTesting.connections
        await setup.finish(save: false)
        XCTAssertTrue(model.isPlaying)
        XCTAssertEqual(model.audioRecoveryStateForTesting.connections, count + 1)
    }

    func testAlreadySpeakerModelKeepsPlaybackConnectionAndSavesReferenceLevel() async {
        let model = AppModel.shared
        model.configureAudioRecoveryForTesting(playing: true)
        let old = model.settings
        defer { model.settings = old; model.settings.save(); model.finishAudioRecoveryForTesting() }
        let audio = TestSpeakerVolumeSession(speaker: true)
        let setup = model.makeSpeakerVolumeSetup(audio: audio, timeout: 0)
        let count = model.audioRecoveryStateForTesting.connections
        await setup.begin(); await setup.finish(save: true)
        XCTAssertEqual(model.settings.scheduledSpeakerVolume, audio.volume)
        XCTAssertTrue(model.isPlaying)
        XCTAssertEqual(model.audioRecoveryStateForTesting.connections, count)
        XCTAssertTrue(audio.operations.isEmpty)
    }
}

@MainActor private final class TestSpeakerVolumeSession: SpeakerVolumeSessionAccess {
    let original: ObservedAudioRoute
    var route: ObservedAudioRoute
    var volume: Float = 0.4
    var foreground = true
    var operations: [String] = []
    var failInterruption = false
    var confirmSpeaker = true
    var restoreRoute = true
    init(speaker: Bool = false) {
        original = .init(ports: [.init(uid: speaker ? "speaker" : "bt", type: speaker ? "Speaker" : "BluetoothA2DPOutput",
                                      name: speaker ? "iPhone" : "Headphones")])
        route = original
    }
    func configuration() -> SpeakerVolumeSessionConfiguration {
        operations.append("snapshot")
        return .init(category: .playback, mode: .default, policy: .default, options: [.mixWithOthers])
    }
    func interruptOtherAudio() throws {
        operations.append("interrupt")
        if failInterruption { throw NSError(domain: NSOSStatusErrorDomain, code: 560557684) }
    }
    func selectSpeaker() throws {
        operations.append("speaker")
        if confirmSpeaker { route = .init(ports: [.init(uid: "speaker", type: "Speaker", name: "iPhone")]) }
    }
    func restore(_ configuration: SpeakerVolumeSessionConfiguration) throws {
        operations.append("restore")
        if restoreRoute { route = original }
    }
    func releaseAndNotifyOthers() throws { operations.append("notify") }
    func observe(_ callback: @escaping (Bool) -> Void) {}
    func stopObserving() {}
}
#endif
