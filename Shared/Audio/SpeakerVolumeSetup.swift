import AVFoundation
import Combine
import UIKit

struct SpeakerVolumeSessionConfiguration {
    var category: AVAudioSession.Category
    var mode: AVAudioSession.Mode
    var policy: AVAudioSession.RouteSharingPolicy
    var options: AVAudioSession.CategoryOptions
}

#if DEBUG
/// Layout fixture only; never activates audio or writes the simulator's volume.
@MainActor final class SpeakerVolumePreviewSession: SpeakerVolumeSessionAccess {
    var route = ObservedAudioRoute(ports: [.init(uid: "speaker", type: "Speaker", name: "iPhone speaker")])
    var volume: Float { AVAudioSession.sharedInstance().outputVolume }
    var foreground = true
    func configuration() -> SpeakerVolumeSessionConfiguration {
        .init(category: .playback, mode: .default, policy: .default, options: [])
    }
    func interruptOtherAudio() throws {}
    func selectSpeaker() throws {}
    func restore(_ configuration: SpeakerVolumeSessionConfiguration) throws {}
    func releaseAndNotifyOthers() throws {}
    func observe(_ callback: @escaping (Bool) -> Void) {}
    func stopObserving() {}
}
#endif

@MainActor protocol SpeakerVolumeSessionAccess: AnyObject {
    var route: ObservedAudioRoute { get }
    var volume: Float { get }
    var foreground: Bool { get }
    func configuration() -> SpeakerVolumeSessionConfiguration
    func interruptOtherAudio() throws
    func selectSpeaker() throws
    func restore(_ configuration: SpeakerVolumeSessionConfiguration) throws
    func releaseAndNotifyOthers() throws
    func observe(_ callback: @escaping (Bool) -> Void)
    func stopObserving()
}

@MainActor final class SystemSpeakerVolumeSession: SpeakerVolumeSessionAccess {
    private let audio = AVAudioSession.sharedInstance()
    private var observation: NSKeyValueObservation?
    private var observers: [NSObjectProtocol] = []
    private var cleanupTask: UIBackgroundTaskIdentifier = .invalid
    private var observing = false
    var route: ObservedAudioRoute {
        .init(ports: audio.currentRoute.outputs.map { .init(uid: $0.uid, type: $0.portType.rawValue, name: $0.portName) })
    }
    var volume: Float { audio.outputVolume }
    var foreground: Bool { UIApplication.shared.applicationState == .active }
    func configuration() -> SpeakerVolumeSessionConfiguration {
        .init(category: audio.category, mode: audio.mode, policy: audio.routeSharingPolicy, options: audio.categoryOptions)
    }
    func interruptOtherAudio() throws {
        try audio.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
        try audio.setActive(true)
    }
    func selectSpeaker() throws {
        try audio.setCategory(.playAndRecord, mode: .default, policy: .default, options: [.defaultToSpeaker])
        try audio.setActive(true)
        try audio.overrideOutputAudioPort(.speaker)
    }
    func restore(_ configuration: SpeakerVolumeSessionConfiguration) throws {
        // Restore the category even if releasing the temporary override fails.
        var overrideError: Error?
        if audio.category == .playAndRecord {
            do { try audio.overrideOutputAudioPort(.none) } catch { overrideError = error }
        }
        try audio.setCategory(configuration.category, mode: configuration.mode,
                              policy: configuration.policy, options: configuration.options)
        if let overrideError { throw overrideError }
    }
    func releaseAndNotifyOthers() throws { try audio.setActive(false, options: .notifyOthersOnDeactivation) }
    func observe(_ callback: @escaping (Bool) -> Void) {
        stopObserving()
        observing = true
        observation = audio.observe(\.outputVolume, options: [.new]) { _, _ in
            Task { @MainActor in callback(false) }
        }
        let center = NotificationCenter.default
        for name in [AVAudioSession.routeChangeNotification, AVAudioSession.mediaServicesWereResetNotification,
                     UIApplication.didEnterBackgroundNotification, AVAudioSession.interruptionNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let interrupted = name == AVAudioSession.interruptionNotification
                    && (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
                let mustEnd = interrupted || name == UIApplication.didEnterBackgroundNotification
                    || name == AVAudioSession.mediaServicesWereResetNotification
                Task { @MainActor in
                    guard let self, self.observing else { return }
                    if name == UIApplication.didEnterBackgroundNotification, self.cleanupTask == .invalid {
                        self.cleanupTask = UIApplication.shared.beginBackgroundTask(withName: "Restore speaker volume setup")
                    }
                    callback(mustEnd)
                }
            })
        }
    }
    func stopObserving() {
        observing = false
        observation?.invalidate(); observation = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        if cleanupTask != .invalid {
            UIApplication.shared.endBackgroundTask(cleanupTask); cleanupTask = .invalid
        }
    }
}

/// Foreground transaction only. The already-speaker branch never acquires a
/// session or suspends playback. MPVolumeView owns all actual volume writes.
@MainActor final class SpeakerVolumeSetup: ObservableObject, Identifiable {
    enum Phase: Equatable { case idle, preparing, adjusting, restoring, restoreOutput, finished }
    let id = UUID()
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var volume: Float = 0
    @Published private(set) var currentRoute = ObservedAudioRoute(ports: [])
    @Published private(set) var previousRoute = ObservedAudioRoute(ports: [])
    @Published private(set) var message: String?
    @Published private(set) var saved = false
    private let audio: SpeakerVolumeSessionAccess
    private let suspend: () throws -> Void
    private let resume: (Bool) -> Void
    private let save: (Float) -> Void
    private let log: (String, [String: String]) -> Void
    private let timeout: TimeInterval
    private var configuration: SpeakerVolumeSessionConfiguration?
    private var suspended = false
    private var sessionTouched = false
    private var operation = UUID()
    private var cleaning = false
    private var permitResume = true
    private var routePickerAllowed = true

    init(audio: SpeakerVolumeSessionAccess? = nil, timeout: TimeInterval = 4,
         suspend: @escaping () throws -> Void, resume: @escaping (Bool) -> Void,
         save: @escaping (Float) -> Void, log: @escaping (String, [String: String]) -> Void) {
        self.audio = audio ?? SystemSpeakerVolumeSession(); self.timeout = timeout; self.suspend = suspend
        self.resume = resume; self.save = save; self.log = log
    }
    var canSave: Bool { phase == .adjusting && currentRoute.isBuiltInSpeaker && volume.isFinite }
    var previousOutputRestored: Bool { previousRoute.matches(currentRoute) }

    func begin() async {
        guard phase == .idle else { return }
        guard audio.foreground else { message = "Open Philharmonic to set speaker volume."; phase = .finished; return }
        refresh(); previousRoute = currentRoute
        audio.observe { [weak self] mustEnd in
            guard let self, self.phase != .finished else { return }
            self.refresh()
            if mustEnd {
                Task { @MainActor in await self.finish(save: false, allowRoutePicker: false, permitResume: false) }
            } else if self.phase == .adjusting && !self.currentRoute.isBuiltInSpeaker {
                self.message = "The speaker is no longer selected. Volume setup ended."
                Task { @MainActor in await self.finish(save: false) }
            }
        }
        log("volume_setup_started", ["already_speaker": String(currentRoute.isBuiltInSpeaker)])
        if currentRoute.isBuiltInSpeaker { phase = .adjusting; return }
        let token = operation
        phase = .preparing
        configuration = audio.configuration()
        do {
            try suspend(); suspended = true
            sessionTouched = true // Activation can partially change the category before failing.
            log("volume_setup_interruption_requested", [:])
            try audio.interruptOtherAudio()
            // No waiting clip or unrelated operation between interruption and routing.
            try audio.selectSpeaker()
            try await waitForRoute(token: token) { $0.isBuiltInSpeaker }
            guard operation == token, !cleaning else { return }
            refresh(); phase = .adjusting
            log("volume_setup_speaker_confirmed", [:])
        } catch {
            guard operation == token, !cleaning else { return }
            message = "Unable to prepare the speaker. " + error.localizedDescription
            log("volume_setup_failed", ["error": PlaybackDiagnosticLog.sanitizedError(error)])
            await finish(save: false)
        }
    }

    func refresh() {
        currentRoute = audio.route
        volume = audio.volume
    }

    func finish(save shouldSave: Bool, allowRoutePicker: Bool = true, permitResume: Bool = true) async {
        guard phase != .finished else { return }
        self.permitResume = self.permitResume && permitResume
        routePickerAllowed = routePickerAllowed && allowRoutePicker
        if phase == .restoreOutput {
            refresh()
            if !routePickerAllowed || previousOutputRestored { finalize() }
            return
        }
        guard !cleaning else { return }
        refresh()
        if shouldSave {
            guard canSave else { return }
            let confirmed = min(1, max(0, volume))
            save(confirmed); saved = true
            log("volume_setup_saved", ["speaker_volume": String(confirmed)])
        }
        cleaning = true; operation = UUID()
        phase = .restoring
        if sessionTouched, let configuration {
            do { try audio.restore(configuration) }
            catch {
                self.permitResume = false
                message = "The previous audio session could not be fully restored."
                log("volume_setup_restore_failed", ["error": PlaybackDiagnosticLog.sanitizedError(error)])
            }
            let token = operation
            try? await waitForRoute(token: token) { self.previousRoute.matches($0) }
            refresh()
            if !previousOutputRestored, routePickerAllowed, audio.foreground {
                phase = .restoreOutput; cleaning = false
                log("volume_setup_route_picker_needed", [:])
                return
            }
        }
        finalize()
    }

    func closeWithoutResuming() {
        guard phase == .restoreOutput else { return }
        permitResume = false; finalize()
    }

    private func finalize() {
        refresh()
        if sessionTouched {
            do { try audio.releaseAndNotifyOthers(); log("volume_setup_others_notified", [:]) }
            catch {
                permitResume = false
                message = "Audio access could not be released cleanly."
                log("volume_setup_release_failed", ["error": PlaybackDiagnosticLog.sanitizedError(error)])
            }
        }
        audio.stopObserving()
        if suspended { resume(permitResume && previousOutputRestored && audio.foreground) }
        log("volume_setup_finished", ["saved": String(saved), "previous_output_restored": String(previousOutputRestored)])
        phase = .finished; cleaning = false
    }

    private func waitForRoute(token: UUID, matching: (ObservedAudioRoute) -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while !matching(audio.route) {
            try Task.checkCancellation()
            guard token == operation else { throw CancellationError() }
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw SetupError.routeTimeout }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    enum SetupError: LocalizedError {
        case routeTimeout, busy
        var errorDescription: String? {
            switch self {
            case .routeTimeout: return "The requested audio output was not confirmed."
            case .busy: return "Another volume setup is already in progress."
            }
        }
    }
}
