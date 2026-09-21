import Foundation
import SwiftUI
import AVFoundation
import UIKit

@MainActor final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var state: PlaybackState = .idle
    @Published var currentItem: ProgrammeItem?
    @Published var previousItems: [ProgrammeItem] = []
    @Published var upcomingItems: [ProgrammeItem] = []
    @Published var programmeName: String?
    @Published var hostName: String?
    @Published var artwork: UIImage?
    @Published var heardAt = Date()
    @Published var bufferWindow: BufferWindow?
    @Published var sleepDescription: String?
    @Published var scheduleDescription: String?
    @Published var notice: String?
    @Published var settings = AppSettings.load()
    @Published private(set) var schedulePhase: ScheduledStartPhase?
    @Published private(set) var currentOutputRoute = ObservedAudioRoute(ports: [])
    @Published private(set) var acquisitionIsStale = false
    @Published private(set) var bufferFailureMessage: String?
    var diagnostics: PlaybackDiagnostics { engine.diagnostics }

    // Transport exposes intent so Pause remains available while waiting or seeking.
    var isPlaying: Bool { wantsPlayback }
    var isAudible: Bool { audioIsAdvancing && wantsPlayback && !interruptionActive && engine.volume > 0 }
    var transportClock: PlaybackTransportClock { engine.transportClock }
    var currentOutputName: String { currentOutputRoute.ports.isEmpty ? "System output unavailable" : currentOutputRoute.name }
    var scheduledOutput: ScheduledOutputPreference { scheduleRequest?.output ?? .currentOutput }
    var sleepActive: Bool { sleepDeadline != nil || pausedSleepRemaining != nil || sleepDecision != nil }
    var statusText: String {
        switch state {
        case .idle: return "Ready to play"
        case .connecting: return "Connecting…"
        case .buffering: return acquisitionIsStale ? "Catching up to live…" : "Buffering…"
        case .seeking: return "Seeking…"
        case .interrupted: return "Audio interrupted"
        case .playingLive: return "Live"
        case .playingDelayed: return "\(Int(max(0, (bufferWindow?.live ?? Date()).timeIntervalSince(heardAt)))) seconds behind live"
        case .pausedLive, .pausedDelayed: return "Paused"
        case .reconnecting(let since): return "Reconnecting… \(min(60, Int(Date().timeIntervalSince(since)))) / 60 s"
        case .fadingOut: return "Sleep timer · fading out"
        case .scheduledStandby: return "Scheduled start · standby"
        case .scheduledSilent: return "Scheduled start · playing silently"
        case .scheduledFadeIn: return "Scheduled start · fading in"
        case .stoppedBySleepTimer: return "Stopped by sleep timer"
        }
    }

    private let engine = RollingAudioEngine()
    private let metadata = MetadataService()
    private var timeline = PlaybackTimeline()
    private let artworkCache = ArtworkCache()
    private var artworkTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var ticker: Timer?
    private var observers: [NSObjectProtocol] = []
    private var appliedSettings = AppSettings.load()
    private var wantsPlayback = false
    private var hasStartedEngine = false
    private var pausedAt: Date?
    private var wasPlayingBeforeInterruption = false
    private var interruptionActive = false
    private var reconnectStarted: Date?
    private var nextRetry = Date.distantPast
    private var lastMetadataFetch = Date.distantPast
    private var lastArtworkURL: URL?
    private var sleepDeadline: Date?
    private var pausedSleepRemaining: TimeInterval?
    private var sleepDecision: SleepDecision?
    private var sleepRetryStarted: Date?
    private var scheduleRequest: ScheduledStartRequest?
    private var scheduledAt: Date? { scheduleRequest?.date }
    private var scheduleGeneration = ScheduleGeneration()
    private var connectionGeneration = UUID()
    private var scheduleOwnsPlayback = false
    private var scheduleEnvelope: ScheduledGainEnvelope?
    private var scheduleGain: Float = 1
    private var sleepGain: Float = 1
    private var audioIsAdvancing = false
    private var scheduleUserInitiated = false
    private var gainTimer: Timer?
    private var scheduleBoundaryTimer: Timer?
    private var lastSurfacePlaying: Bool?
    #if DEBUG
    private var scheduleDiagnostics: [String] = []
    private var lastDiagnosticGain: Float = -1
    private var isUIFixture = ProcessInfo.processInfo.environment["KUSC_UI_STATE"] != nil
    private var boundaryGainTrace: [Float]?
    private var audioRecoveryTestConnections: Int?
    #endif
    private var unpluggedAt: Date?
    private var notificationOnly = false
    private var launched = false
    private let standby = SilentStandby()
    private lazy var nowPlaying = NowPlayingController(play: { [weak self] in self?.play() },
        pause: { [weak self] in self?.pauseRemote() },
        toggle: { [weak self] in guard let self else { return }; self.isPlaying ? self.pauseRemote() : self.play() })
    #if MODERN
    private let liveActivity = LiveActivityCoordinator()
    #endif

    private init() {
        NotificationCoordinator.shared.install()
        engine.onUpdate = { [weak self] snapshot in self?.receive(snapshot) }
        engine.onFailure = { [weak self] error in self?.connectionFailed(error) }
        installAudioObservers()
        UIDevice.current.isBatteryMonitoringEnabled = true
        if let data = UserDefaults.standard.data(forKey: "scheduledStart.v2"),
           let request = try? JSONDecoder().decode(ScheduledStartRequest.self, from: data) {
            scheduleRequest = request
            // A terminated process cannot claim it delivered an expired start.
            notificationOnly = request.date <= Date() || UserDefaults.standard.bool(forKey: "scheduledNotificationOnly.v2")
        } else if let date = UserDefaults.standard.object(forKey: "scheduledAt") as? Date, date > Date() {
            let migrated = ScheduledStartRequest(date: date)
            scheduleRequest = migrated
            persistSchedule()
            NotificationCoordinator.shared.cancel(requestID: migrated.id)
            NotificationCoordinator.shared.replaceFallback(migrated, body: "Tap to start KUSC live.")
        }
        UserDefaults.standard.removeObject(forKey: "scheduledAt")
        refreshCurrentOutput()
        armScheduleBoundary()
        ensureTicker()
    }

    func launch() {
        #if DEBUG
        guard !isUIFixture else { return }
        #endif
        guard !launched else { return }
        launched = true
        fetchMetadata()
        // Restore explicit scheduled intent before launch auto-play can defeat its
        // route policy or turn a fallback notification into a full-volume start.
        if settings.autoplay && scheduleRequest == nil { play() }
        evaluateSchedule()
    }

    func updateSettings() {
        settings.retentionMinutes = min(15, max(0, settings.retentionMinutes))
        settings.save()
        if settings.retentionMinutes != appliedSettings.retentionMinutes {
            bufferFailureMessage = nil
            diagnostics.record("settings retention=\(settings.retentionMinutes) resumeWherePaused=\(settings.resumeWherePaused)")
            engine.setRetention(minutes: settings.retentionMinutes)
            if settings.retentionMinutes == 0 { bufferWindow = nil; pausedAt = nil }
        }
        appliedSettings = settings
    }

    func startPlaybackDiagnostics() {
        let bundle = Bundle.main
        let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "unknown"
        let build = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "unknown"
        let routeTypes = AVAudioSession.sharedInstance().currentRoute.outputs.map { $0.portType.rawValue }.sorted().joined(separator: ",")
        diagnostics.start(context: "KUSC \(version) build \(build); \(UIDevice.current.model); iOS \(UIDevice.current.systemVersion); retention=\(settings.retentionMinutes); resumeWherePaused=\(settings.resumeWherePaused); playbackRequested=\(wantsPlayback); outputTypes=[\(routeTypes)]")
        engine.recordDiagnosticSnapshot()
    }

    func stopPlaybackDiagnostics() { diagnostics.stop() }

    func play() {
        #if DEBUG
        guard !isUIFixture || audioRecoveryTestConnections != nil else { return }
        #endif
        scheduleGeneration.invalidate()
        ensureTicker()
        if scheduleOwnsPlayback || notificationOnly { clearSchedule(stopOwnedPlayback: false) }
        guard !interruptionActive else { notice = "Playback will remain paused during the audio interruption."; return }
        if let remaining = pausedSleepRemaining {
            sleepDeadline = Date().addingTimeInterval(remaining); pausedSleepRemaining = nil
        }
        wantsPlayback = true
        standby.stop()
        scheduleGain = 1; applyGain()
        do { try activateSession() } catch { notice = error.localizedDescription; wantsPlayback = false; applyGain(); return }
        if hasStartedEngine, reconnectStarted == nil {
            if let pausedAt, settings.resumeWherePaused, let window = bufferWindow {
                engine.seek(to: ResumePolicy.target(mode: .wherePaused, pausedAt: pausedAt, window: window))
            } else if pausedAt != nil { engine.goLive() }
            self.pausedAt = nil
            engine.play()
            state = .connecting
        } else {
            reconnectStarted = nil
            startConnection()
        }
        fetchMetadata()
    }

    @discardableResult func pauseFromApp() -> Bool {
        pauseRemote()
        return sleepActive
    }

    func pauseRemote() {
        scheduleGeneration.invalidate()
        if scheduleOwnsPlayback { clearSchedule(stopOwnedPlayback: true) }
        if reconnectStarted != nil || state == .connecting {
            engine.stop(); hasStartedEngine = false; bufferWindow = nil
        }
        wantsPlayback = false
        audioIsAdvancing = false; applyGain()
        pausedAt = heardAt
        connectionTask?.cancel(); connectionTask = nil
        connectionGeneration = UUID()
        reconnectStarted = nil
        engine.pause()
        state = bufferWindow != nil && (bufferWindow!.live.timeIntervalSince(heardAt) > 12) ? .pausedDelayed : .pausedLive
        refreshSystemSurfaces()
    }

    func choosePausedTimer(_ choice: TimerPauseChoice) {
        switch choice {
        case .keepCounting: break
        case .pauseTimer:
            if let deadline = sleepDeadline { pausedSleepRemaining = max(0, deadline.timeIntervalSinceNow) }
            else if let decision = sleepDecision {
                switch decision {
                case .stopAt(let date): pausedSleepRemaining = max(0, date.timeIntervalSinceNow)
                case .fade(_, let end): pausedSleepRemaining = max(0, end.timeIntervalSinceNow)
                case .retry: pausedSleepRemaining = 0
                }
            }
            sleepDeadline = nil; sleepDecision = nil; sleepRetryStarted = nil; sleepGain = 1; applyGain()
        case .cancelTimer: cancelSleep()
        }
    }

    func goLive() {
        scheduleGeneration.invalidate()
        if scheduleOwnsPlayback { clearSchedule(stopOwnedPlayback: false); scheduleGain = 1; applyGain() }
        if !hasStartedEngine { play(); return }
        if !wantsPlayback { play() }
        engine.goLive(); pausedAt = nil
        invalidateSleepEndpoint()
    }

    func seek(to date: Date) {
        scheduleGeneration.invalidate()
        guard bufferWindow != nil else { return }
        if scheduleOwnsPlayback { clearSchedule(stopOwnedPlayback: false); scheduleGain = 1; applyGain() }
        // Engine resolves expiry/gaps and publishes only a confirmed media timestamp.
        engine.seek(to: date)
        invalidateSleepEndpoint()
    }

    func canSeek(to date: Date) -> Bool { engine.canSeek(to: date) }

    func startSleep(minutes: Int) {
        ensureTicker()
        let duration = min(720, max(0, minutes))
        settings.lastSleepMinutes = duration; settings.save()
        cancelSleep()
        if duration > 0 { sleepDeadline = Date().addingTimeInterval(TimeInterval(duration * 60)) }
        tick()
    }
    func cancelSleep() {
        sleepDeadline = nil; pausedSleepRemaining = nil; sleepDecision = nil; sleepRetryStarted = nil
        sleepDescription = nil; sleepGain = 1; applyGain()
        if state == .fadingOut { state = wantsPlayback ? .playingLive : .pausedLive }
    }

    func scheduleStart(at date: Date, output: ScheduledOutputPreference = .currentOutput) async throws {
        guard StandbyPolicy.isValidSchedule(date, now: Date()) else { throw ScheduleError.outsideWindow }
        clearSchedule(stopOwnedPlayback: true)
        let generation = scheduleGeneration.begin()
        let request = ScheduledStartRequest(date: date, output: output)
        try await NotificationCoordinator.shared.schedule(request)
        guard scheduleGeneration.accepts(generation) else {
            NotificationCoordinator.shared.cancel(requestID: request.id); return
        }
        ensureTicker()
        scheduleRequest = request; notificationOnly = false; unpluggedAt = nil
        persistSchedule(); armScheduleBoundary()
        evaluateSchedule()
    }
    func cancelSchedule() {
        clearSchedule(stopOwnedPlayback: true)
    }
    func startFromNotification(requestID: UUID? = nil) {
        guard let request = scheduleRequest, request.id == requestID else { return }
        if scheduleOwnsPlayback { return } // Duplicate delivery cannot restart an envelope.
        if wantsPlayback { clearSchedule(stopOwnedPlayback: false); return }
        guard !interruptionActive else { notice = "Wait for the audio interruption to end, then tap Play."; return }
        notificationOnly = false
        scheduleUserInitiated = true // A notification tap is explicit foreground playback intent.
        beginScheduledPlayback(request)
    }
    func onForeground() {
        #if DEBUG
        guard !isUIFixture else { return }
        #endif
        tick(); if hasStartedEngine || currentItem == nil { fetchMetadata() }
    }

    #if DEBUG
    /// Used only by deterministic screenshot launches; no session or player starts.
    func configureUIFixturePlayback(active: Bool) {
        isUIFixture = true
        ticker?.invalidate(); ticker = nil
        scheduleBoundaryTimer?.invalidate(); scheduleBoundaryTimer = nil
        wantsPlayback = active
        audioIsAdvancing = false
    }
    func configureUIFixtureOutputUnavailable() {
        currentOutputRoute = ObservedAudioRoute(ports: [])
    }

    /// Hosted XCTest exercises the real coordinator/engine gain boundary without
    /// starting an AVPlayer, changing the audio session, or contacting the station.
    func configureScheduledGainBoundaryTest(schedule: Float, sleep: Float) {
        precondition(isUIFixture, "Boundary tests require the isolated UI fixture launch environment")
        cancelSchedule(); cancelSleep()
        ticker?.invalidate(); ticker = nil
        gainTimer?.invalidate(); gainTimer = nil
        scheduleRequest = ScheduledStartRequest(date: Date().addingTimeInterval(60))
        scheduleOwnsPlayback = true
        scheduleEnvelope = nil
        wantsPlayback = true
        hasStartedEngine = false
        audioIsAdvancing = false
        scheduleGain = schedule
        sleepGain = sleep
        boundaryGainTrace = []
        applyGain()
    }

    var scheduledGainBoundaryState: (gain: Float, wantsPlayback: Bool, ownsPlayback: Bool, hasSchedule: Bool, trace: [Float]) {
        (engine.volume, wantsPlayback, scheduleOwnsPlayback, scheduleRequest != nil, boundaryGainTrace ?? [])
    }

    func runScheduledGainCallbackForTest() {
        precondition(isUIFixture)
        updateGains()
    }

    func configurePausedDiagnosticFailureForTesting() {
        precondition(isUIFixture)
        wantsPlayback = false
        state = .pausedLive
        settings.retentionMinutes = 5
        let anchor = Date(timeIntervalSince1970: 1_800_000_000)
        let segments: [AudioSegment] = (0..<2).map { (index: Int) -> AudioSegment in
            let url = URL(fileURLWithPath: "/diagnostic-fixture-\(index).aac")
            let start = anchor.addingTimeInterval(TimeInterval(index) * 10)
            let end = start.addingTimeInterval(10)
            return AudioSegment(url: url, start: start, end: end, byteCount: 100)
        }
        engine.configureBufferedTransportForTesting(segments: segments, pausedAt: anchor.addingTimeInterval(4))
        startPlaybackDiagnostics()
        engine.failForDiagnosticsTesting(AudioStreamError.unsupportedFormat("diagnostic fixture failure"))
    }

    /// Exercise coordinator recovery without contacting the station or activating
    /// the system audio session. The real engine is still invalidated on reset.
    func configureAudioRecoveryForTesting(playing: Bool, interrupted: Bool = false,
                                          scheduled: Bool = false) {
        precondition(isUIFixture)
        cancelSchedule(); cancelSleep()
        stopEverything(reason: .idle)
        ticker?.invalidate(); ticker = nil
        gainTimer?.invalidate(); gainTimer = nil
        audioRecoveryTestConnections = 0
        wantsPlayback = playing
        hasStartedEngine = true
        interruptionActive = interrupted
        wasPlayingBeforeInterruption = interrupted && playing
        let anchor = Date(timeIntervalSince1970: 1_800_000_000)
        heardAt = anchor
        pausedAt = playing ? nil : anchor
        bufferWindow = BufferWindow(oldest: anchor.addingTimeInterval(-60), live: anchor.addingTimeInterval(20))
        transportClock.configureUIFixture(.init(heardAt: anchor, window: bufferWindow))
        state = interrupted ? .interrupted : (playing ? .playingDelayed : .pausedDelayed)
        if scheduled {
            scheduleRequest = ScheduledStartRequest(date: Date().addingTimeInterval(60))
            scheduleOwnsPlayback = playing
            scheduleGain = playing ? 0.4 : 1
        }
        boundaryGainTrace = []
        applyGain()
    }

    var audioRecoveryStateForTesting: (started: Bool, connections: Int, engineGeneration: UUID,
                                       connectionGeneration: UUID, pausedAt: Date?, interrupted: Bool) {
        (hasStartedEngine, audioRecoveryTestConnections ?? 0, engine.transportSessionForTesting,
         connectionGeneration, pausedAt, interruptionActive)
    }

    func resetMediaServicesForTesting() { handleMediaServicesReset() }
    func endAudioInterruptionForTesting(shouldResume: Bool) { endInterruption(shouldResume: shouldResume) }

    func finishAudioRecoveryForTesting() {
        interruptionActive = false
        wasPlayingBeforeInterruption = false
        cancelSchedule(); cancelSleep()
        stopEverything(reason: .idle)
        ticker?.invalidate(); ticker = nil
        audioRecoveryTestConnections = nil
        boundaryGainTrace = nil
    }
    #endif

    private func startConnection() {
        bufferFailureMessage = nil
        connectionTask?.cancel()
        let generation = UUID(); connectionGeneration = generation
        if scheduleOwnsPlayback { scheduleEnvelope = nil; scheduleGain = 0; applyGain() }
        if reconnectStarted == nil { state = .connecting }
        hasStartedEngine = true
        #if DEBUG
        if let connections = audioRecoveryTestConnections {
            audioRecoveryTestConnections = connections + 1
            return
        }
        #endif
        connectionTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            do {
                try await engine.start(url: StationConfiguration.audioURL, retentionMinutes: settings.retentionMinutes)
                guard !Task.isCancelled, connectionGeneration == generation else { return }
                applyGain()
                if wantsPlayback && !interruptionActive { engine.play() } else { engine.pause() }
            } catch {
                if !Task.isCancelled, connectionGeneration == generation { connectionFailed(error) }
            }
        }
    }

    private func connectionFailed(_ error: Error) {
        // Engine failures normally freeze the report before this callback clears
        // their state. Startup failures can arrive directly from startConnection.
        diagnostics.captureFailure(error, origin: "model.connectionFailed")
        if settings.retentionMinutes > 0 {
            bufferFailureMessage = wantsPlayback
                ? "Audio collection stopped. Reconnecting…"
                : "Rewind stopped after an audio error. Tap Play to reconnect."
        }
        guard wantsPlayback else {
            hasStartedEngine = false; engine.stop(); bufferWindow = nil; return
        }
        audioIsAdvancing = false
        if scheduleOwnsPlayback { scheduleEnvelope = nil; scheduleGain = 0; applyGain() }
        let now = Date()
        if reconnectStarted == nil { reconnectStarted = now }
        state = .reconnecting(since: reconnectStarted!)
        nextRetry = now.addingTimeInterval(3)
        // No separate Retry control; tick returns to the ordinary idle state after 60 seconds.
    }

    private func receive(_ snapshot: EngineSnapshot) {
        if snapshot.hasConfirmedPosition {
            heardAt = snapshot.heardAt
            if !wantsPlayback { pausedAt = snapshot.heardAt }
        }
        if bufferWindow != snapshot.window { bufferWindow = snapshot.window }
        if acquisitionIsStale != snapshot.acquisitionIsStale { acquisitionIsStale = snapshot.acquisitionIsStale }
        if snapshot.isPlaying { bufferFailureMessage = nil }
        audioIsAdvancing = snapshot.isPlaying && !snapshot.isWaiting && !snapshot.isSeeking
        if scheduleOwnsPlayback {
            if audioIsAdvancing && snapshot.isReady && !interruptionActive {
                if scheduleEnvelope == nil, let request = scheduleRequest {
                    if !snapshot.hasConfirmedPosition { recordScheduleDiagnostic("audio ready; station timestamp unavailable") }
                    scheduleEnvelope = ScheduledGainEnvelope(target: request.date, readyAt: Date(), uptime: ProcessInfo.processInfo.systemUptime)
                    startGainDriver()
                }
                updateGains()
            } else {
                scheduleEnvelope = nil; scheduleGain = 0; applyGain()
            }
        }
        if interruptionActive && wantsPlayback {
            state = .interrupted
        } else if snapshot.isPlaying {
            if reconnectStarted != nil { invalidateSleepEndpoint() }
            reconnectStarted = nil
            if wantsPlayback && !scheduleOwnsPlayback {
                if snapshot.isSeeking { state = .seeking }
                else if snapshot.isWaiting || snapshot.acquisitionIsStale { state = .buffering }
                else if sleepGain < 1 { state = .fadingOut }
                else { state = snapshot.isAtLiveEdge ? .playingLive : .playingDelayed }
            }
        } else if wantsPlayback && reconnectStarted == nil && !scheduleOwnsPlayback {
            state = snapshot.isSeeking ? .seeking : (snapshot.isReady ? .buffering : .connecting)
        }
        if snapshot.hasConfirmedPosition { resolveMetadata() }
        else { refreshSystemSurfaces() }
    }

    private func ensureTicker() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        ticker?.tolerance = 0.2
    }

    private func tick() {
        let now = Date()
        if let started = reconnectStarted {
            objectWillChange.send()
            if ReconnectPolicy(startedAt: started).decision(at: now) == .stop {
                if scheduleOwnsPlayback { scheduleFallback("The station could not connect. Tap to try KUSC again.") }
                else { stopEverything(reason: .idle) }
            }
            else if now >= nextRetry {
                nextRetry = .distantFuture
                startConnection()
            }
        }
        if hasStartedEngine, now.timeIntervalSince(lastMetadataFetch) >= (sleepRetryStarted == nil ? 30 : 5) { fetchMetadata() }
        evaluateSleep(now: now)
        evaluateSchedule()
        if !hasStartedEngine && !sleepActive && scheduledAt == nil && reconnectStarted == nil {
            ticker?.invalidate(); ticker = nil
        }
    }

    private func evaluateSleep(now: Date) {
        if let remaining = pausedSleepRemaining {
            sleepDescription = "Sleep timer paused · \(Int(ceil(remaining / 60))) min"; return
        }
        guard let deadline = sleepDeadline else { return }
        if now < deadline {
            sleepDescription = "Sleep in \(Int(ceil(deadline.timeIntervalSince(now) / 60))) min"; return
        }
        if !wantsPlayback { finishSleep(); return }
        let needsDecision: Bool
        if case .retry? = sleepDecision { needsDecision = true } else { needsDecision = sleepDecision == nil }
        if needsDecision {
            if sleepRetryStarted == nil { sleepRetryStarted = now }
            sleepDecision = SleepPolicy.evaluate(now: now, heardAt: heardAt,
                movementEnd: currentItem?.end, movementEndReliable: currentItem?.timingReliable ?? false,
                nextStart: [upcomingItems.first?.start, metadata.nextProgrammeStart(after: heardAt)].compactMap { $0 }.min(), retryStartedAt: sleepRetryStarted)
        }
        guard let decision = sleepDecision else { return }
        switch decision {
        case .stopAt(let end):
            sleepDescription = "Sleep after current piece"
            if now >= end { finishSleep() }
        case .fade(let start, let end):
            sleepDescription = now < start ? "Sleep at next transition" : "Sleep timer · fading out"
            if now >= start { state = .fadingOut; startGainDriver(); updateGains() }
            if now >= end { finishSleep() }
        case .retry:
            sleepDescription = "Sleep timer · checking transition"
        }
    }
    private func invalidateSleepEndpoint() {
        if sleepDeadline.map({ $0 <= Date() }) == true { sleepDecision = nil; sleepRetryStarted = nil; sleepGain = 1; applyGain() }
    }
    private func finishSleep() {
        // Stop before resetting envelopes; cancellation must never expose one full-volume frame.
        if scheduleOwnsPlayback { clearSchedule(stopOwnedPlayback: true) }
        stopEverything(reason: .stoppedBySleepTimer); cancelSleep()
    }
    private func stopEverything(reason: PlaybackState) {
        wantsPlayback = false; hasStartedEngine = false; pausedAt = nil; reconnectStarted = nil
        audioIsAdvancing = false; applyGain(); connectionGeneration = UUID()
        connectionTask?.cancel(); connectionTask = nil
        metadataTask?.cancel(); metadataTask = nil
        artworkTask?.cancel(); artworkTask = nil
        engine.stop(); bufferWindow = nil; state = reason
        refreshSystemSurfaces()
        if scheduledAt == nil { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    private func evaluateSchedule() {
        #if DEBUG
        guard !isUIFixture else { return }
        #endif
        guard let request = scheduleRequest else { return }
        let now = Date()
        let dueForPreparation = ScheduledStartPolicy.shouldPrepare(target: request.date, now: now)
        if wantsPlayback && !scheduleOwnsPlayback {
            if dueForPreparation { clearSchedule(stopOwnedPlayback: false) }
            else {
                standby.stop(); setSchedulePhase(.waiting)
                scheduleDescription = "\(request.date.formatted(date: .omitted, time: .shortened)) · \(request.output.summary)"
            }
            return
        }
        if notificationOnly {
            setSchedulePhase(.notificationOnly)
            scheduleDescription = "\(request.date.formatted(date: .omitted, time: .shortened)) · tap notification to play · \(request.output.summary)"
            return
        }
        guard !interruptionActive else {
            scheduleFallback("An audio interruption prevented the scheduled start. Tap to start when it ends."); return
        }
        guard scheduleUserInitiated || schedulePowerPermits(now: now) else {
            scheduleFallback("Automatic start is unavailable on battery. Tap to start KUSC live."); return
        }
        if scheduleOwnsPlayback {
            guard validateScheduledRoute(request) else { return }
            updateGains(); return
        }
        if dueForPreparation {
            beginScheduledPlayback(request)
        } else if wantsPlayback {
            standby.stop()
            setSchedulePhase(.waiting)
        } else {
            do {
                try activateSession(); try standby.start()
                state = .scheduledStandby; setSchedulePhase(.standby)
            } catch { scheduleFallback("Automatic standby is unavailable. Tap to start KUSC live.") }
        }
        if scheduleRequest != nil, !notificationOnly {
            scheduleDescription = "\(request.date.formatted(date: .omitted, time: .shortened)) · \(request.output.summary)"
        }
    }

    private func schedulePowerPermits(now: Date) -> Bool {
        let device = UIDevice.current
        let plugged = device.batteryState == .charging || device.batteryState == .full
        switch StandbyPolicy.update(now: now, isPluggedIn: plugged, batteryLevel: Double(device.batteryLevel),
                                   unpluggedAt: unpluggedAt, wasStandingBy: standby.running || scheduleOwnsPlayback) {
        case .standby(let since): unpluggedAt = since; return true
        case .notificationOnly: return false
        }
    }

    private func beginScheduledPlayback(_ request: ScheduledStartRequest) {
        guard scheduleRequest?.id == request.id, !scheduleOwnsPlayback, !interruptionActive else { return }
        scheduleGain = 0
        // Gain reaches the player before session activation, reconnect, or play.
        applyGain()
        do { try activateSession() }
        catch { scheduleFallback("KUSC could not activate audio. Tap to try again."); return }
        guard validateScheduledRoute(request) else { return }
        scheduleOwnsPlayback = true; scheduleEnvelope = nil
        wantsPlayback = true; pausedAt = nil; reconnectStarted = nil
        connectionTask?.cancel(); engine.stop(); hasStartedEngine = false
        applyGain(); standby.stop()
        setSchedulePhase(.preparing)
        ensureTicker(); startGainDriver(); startConnection(); fetchMetadata()
    }

    private func validateScheduledRoute(_ request: ScheduledStartRequest) -> Bool {
        refreshCurrentOutput()
        guard request.output.permits(currentOutputRoute) else {
            scheduleGain = 0; applyGain()
            let name = request.output.route?.name ?? "Audio output"
            scheduleFallback("\(name) is unavailable or no longer selected. Choose an output, then tap Play.")
            return false
        }
        return true
    }

    func refreshCurrentOutput() {
        let route = ObservedAudioRoute(ports: AVAudioSession.sharedInstance().currentRoute.outputs.map {
            .init(uid: $0.uid, type: $0.portType.rawValue, name: $0.portName)
        })
        if currentOutputRoute != route { currentOutputRoute = route }
    }

    private func scheduleFallback(_ message: String) {
        guard let request = scheduleRequest else { return }
        recordScheduleDiagnostic("fallback \(message)")
        scheduleGain = 0; applyGain()
        let owned = scheduleOwnsPlayback
        scheduleOwnsPlayback = false; scheduleEnvelope = nil; scheduleUserInitiated = false
        notificationOnly = true; standby.stop(); setSchedulePhase(.notificationOnly)
        persistSchedule()
        if owned { stopEverything(reason: .idle) }
        else if state == .scheduledStandby { state = .idle }
        scheduleGain = 1; applyGain()
        notice = message
        scheduleDescription = "\(request.date.formatted(date: .omitted, time: .shortened)) · tap notification to play · \(request.output.summary)"
        NotificationCoordinator.shared.replaceFallback(request, body: message)
    }

    private func clearSchedule(stopOwnedPlayback: Bool) {
        if scheduleRequest != nil { recordScheduleDiagnostic("clear stopOwned=\(stopOwnedPlayback)") }
        scheduleGeneration.invalidate()
        let owned = scheduleOwnsPlayback
        if owned && stopOwnedPlayback {
            scheduleGain = 0; applyGain()
            stopEverything(reason: .idle)
        }
        if let request = scheduleRequest { NotificationCoordinator.shared.cancel(requestID: request.id) }
        scheduleRequest = nil; scheduleOwnsPlayback = false; scheduleEnvelope = nil
        scheduleUserInitiated = false; unpluggedAt = nil; notificationOnly = false
        scheduleDescription = nil; schedulePhase = nil; standby.stop()
        scheduleBoundaryTimer?.invalidate(); scheduleBoundaryTimer = nil
        persistSchedule()
        scheduleGain = 1; applyGain()
        if state == .scheduledStandby { state = .idle }
    }

    private func persistSchedule() {
        UserDefaults.standard.set(notificationOnly && scheduleRequest != nil, forKey: "scheduledNotificationOnly.v2")
        if let request = scheduleRequest, let data = try? JSONEncoder().encode(request) {
            UserDefaults.standard.set(data, forKey: "scheduledStart.v2")
        } else { UserDefaults.standard.removeObject(forKey: "scheduledStart.v2") }
    }

    private func armScheduleBoundary() {
        scheduleBoundaryTimer?.invalidate()
        guard let request = scheduleRequest else { return }
        let id = request.id
        let timer = Timer(fire: max(Date(), request.date.addingTimeInterval(-60)), interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.scheduleRequest?.id == id else { return }
                self.evaluateSchedule()
            }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        scheduleBoundaryTimer = timer
    }

    private func setSchedulePhase(_ phase: ScheduledStartPhase) {
        if schedulePhase != phase {
            schedulePhase = phase
            recordScheduleDiagnostic("phase=\(phase.rawValue)")
        }
    }

    private func startGainDriver() {
        guard gainTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateGains() }
        }
        timer.tolerance = 0.002
        RunLoop.main.add(timer, forMode: .common)
        gainTimer = timer
    }

    private func updateGains() {
        let now = Date()
        if scheduleOwnsPlayback, let request = scheduleRequest {
            guard !interruptionActive, scheduleUserInitiated || schedulePowerPermits(now: now) else {
                scheduleFallback("Automatic playback was interrupted. Tap to start KUSC live."); return
            }
            guard validateScheduledRoute(request) else { return }
            if let envelope = scheduleEnvelope, audioIsAdvancing {
                let uptime = ProcessInfo.processInfo.systemUptime
                scheduleGain = envelope.gain(at: uptime)
                setSchedulePhase(scheduleGain > 0 ? .fading : .silent)
                let newState: PlaybackState = scheduleGain > 0 ? .scheduledFadeIn : .scheduledSilent
                if state != newState { state = newState }
                if envelope.isComplete(at: uptime) {
                    clearSchedule(stopOwnedPlayback: false)
                    state = .playingLive
                }
            } else { scheduleGain = 0; setSchedulePhase(.preparing) }
        }
        var sleepFading = false
        if case .fade(let start, let end)? = sleepDecision, now >= start {
            sleepFading = true
            sleepGain = Float(SleepPolicy.gain(at: now, fadeStart: start, fadeEnd: end))
            if now >= end { finishSleep(); return }
        }
        applyGain()
        if !scheduleOwnsPlayback && !sleepFading { gainTimer?.invalidate(); gainTimer = nil }
    }

    private func applyGain() {
        engine.volume = ScheduledStartPolicy.composedGain(schedule: scheduleGain, sleep: sleepGain,
                                                        muted: !wantsPlayback || interruptionActive)
        #if DEBUG
        boundaryGainTrace?.append(engine.volume)
        if scheduleOwnsPlayback && abs(lastDiagnosticGain - engine.volume) >= 0.025 {
            lastDiagnosticGain = engine.volume
            recordScheduleDiagnostic("scheduleGain=\(scheduleGain) sleepGain=\(sleepGain) effective=\(engine.volume)")
        }
        #endif
        let playing = isAudible
        if lastSurfacePlaying != playing { lastSurfacePlaying = playing; refreshSystemSurfaces() }
    }

    private func recordScheduleDiagnostic(_ event: String) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-KUSCAudioDiagnostics") else { return }
        let entry = "schedule=\(scheduleRequest?.id.uuidString ?? "none") uptime=\(ProcessInfo.processInfo.systemUptime) wall=\(Date().timeIntervalSince1970) target=\(scheduledAt?.timeIntervalSince1970 ?? 0) route=\(currentOutputRoute.ports.map { $0.type + ":" + $0.uid }.joined(separator: ",")) \(event)"
        scheduleDiagnostics.append(entry)
        if scheduleDiagnostics.count > 512 { scheduleDiagnostics.removeFirst(scheduleDiagnostics.count - 512) }
        NSLog("KUSC schedule %@", entry)
        #endif
    }

    private func fetchMetadata() {
        #if DEBUG
        guard !isUIFixture else { return }
        #endif
        guard metadataTask == nil else { return }
        lastMetadataFetch = Date()
        metadataTask = Task { [weak self] in
            guard let self else { return }
            defer { metadataTask = nil }
            do {
                let items = try await metadata.fetch()
                guard !Task.isCancelled else { return }
                timeline.merge(items); resolveMetadata()
            } catch { /* Metadata failure never interrupts audio or clears the last known item. */ }
        }
    }
    private func resolveMetadata() {
        let context = timeline.context(at: heardAt)
        if currentItem != context.current { currentItem = context.current }
        let programme = metadata.programme(at: heardAt)
        let name = programme?.name ?? currentItem?.programme
        let host = programme?.host ?? currentItem?.host
        if programmeName != name { programmeName = name }
        if hostName != host { hostName = host }
        if previousItems != context.previous { previousItems = context.previous }
        if upcomingItems != context.upcoming { upcomingItems = context.upcoming }
        let url = currentItem?.artworkURL
        if url != lastArtworkURL {
            lastArtworkURL = url; artworkTask?.cancel(); artwork = nil
            if let url {
                artworkTask = Task { [weak self] in
                    guard let self else { return }
                    let image = await artworkCache.image(at: url)
                    guard !Task.isCancelled, lastArtworkURL == url else { return }
                    artwork = image; refreshSystemSurfaces()
                }
            }
        }
        refreshSystemSurfaces()
    }
    private func refreshSystemSurfaces() {
        nowPlaying.update(item: currentItem, artwork: artwork, playing: isAudible)
        #if MODERN
        let surfaceStatus: String?
        switch state {
        case .playingLive: surfaceStatus = nil
        case .playingDelayed: surfaceStatus = "Delayed playback"
        case .reconnecting: surfaceStatus = "Reconnecting…"
        default: surfaceStatus = statusText
        }
        liveActivity.update(item: currentItem, artwork: artwork, playing: isAudible,
                            requested: isPlaying, status: surfaceStatus, visible: hasStartedEngine)
        #endif
        NotificationCenter.default.post(name: .kuscPlaybackChanged, object: self)
    }

    private func activateSession() throws {
        #if DEBUG
        if audioRecoveryTestConnections != nil { return }
        #endif
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
        try audio.setActive(true)
    }

    private func handleMediaServicesReset() {
        // A reset invalidates the media objects even while paused. Do not leave
        // an obsolete renderer available for the next Play or interruption end.
        connectionGeneration = UUID()
        connectionTask?.cancel(); connectionTask = nil
        hasStartedEngine = false
        reconnectStarted = nil
        audioIsAdvancing = false
        if scheduleOwnsPlayback { scheduleGain = 0; scheduleEnvelope = nil }
        applyGain()
        engine.stop(); standby.stop()
        pausedAt = nil
        bufferWindow = nil
        acquisitionIsStale = false
        if wantsPlayback && !interruptionActive {
            do { try activateSession(); startConnection() }
            catch { connectionFailed(error) }
        } else if interruptionActive && wantsPlayback {
            state = .interrupted
        } else if state == .pausedDelayed {
            state = .pausedLive
        }
        refreshSystemSurfaces()
    }

    private func endInterruption(shouldResume: Bool) {
        interruptionActive = false
        if wasPlayingBeforeInterruption && wantsPlayback && shouldResume {
            do {
                try activateSession(); applyGain()
                if hasStartedEngine, reconnectStarted == nil { engine.play() }
                else { reconnectStarted = nil; startConnection() }
                invalidateSleepEndpoint()
            } catch { connectionFailed(error) }
        } else if wasPlayingBeforeInterruption {
            pauseRemote()
        }
        wasPlayingBeforeInterruption = false
    }

    private func installAudioObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let kind = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            let options = (n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            Task { @MainActor in
                guard let self else { return }
                if kind == .began {
                    self.wasPlayingBeforeInterruption = self.wantsPlayback
                    self.interruptionActive = true; self.applyGain(); self.engine.pause(); self.standby.stop()
                    if self.wantsPlayback { self.state = .interrupted }
                    if self.scheduleRequest != nil && (self.scheduleOwnsPlayback || !self.wasPlayingBeforeInterruption) {
                        self.scheduleFallback("An audio interruption prevented the scheduled start. Tap to try again when it ends.")
                        self.wasPlayingBeforeInterruption = false
                    }
                } else {
                    self.endInterruption(shouldResume: AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume))
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] n in
            let reason = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
            Task { @MainActor in
                guard let self else { return }
                if self.scheduleOwnsPlayback, let request = self.scheduleRequest {
                    self.scheduleGain = 0; self.scheduleEnvelope = nil; self.applyGain()
                    guard self.validateScheduledRoute(request) else { return }
                }
                self.refreshCurrentOutput()
                guard reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue,
                      self.wantsPlayback, !self.interruptionActive else { return }
                do { try self.activateSession(); self.applyGain(); self.engine.play() }
                catch { self.connectionFailed(error) }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.handleMediaServicesReset()
            }
        })
        for name in [UIDevice.batteryStateDidChangeNotification, UIDevice.batteryLevelDidChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.evaluateSchedule() }
            })
        }
        observers.append(center.addObserver(forName: UIApplication.significantTimeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Active gain ramps keep their monotonic deadline through clock changes.
                self.armScheduleBoundary(); self.evaluateSchedule()
            }
        })
    }
    enum ScheduleError: LocalizedError {
        case outsideWindow
        var errorDescription: String? { "Choose a future time within the next 24 hours." }
    }
}
extension Notification.Name { static let kuscPlaybackChanged = Notification.Name("KUSCPlaybackChanged") }
