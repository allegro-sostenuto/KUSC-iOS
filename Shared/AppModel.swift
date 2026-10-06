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
    @Published private(set) var scheduleManagementRequest: UUID?
    @Published private(set) var currentOutputRoute = ObservedAudioRoute(ports: [])
    @Published private(set) var acquisitionIsStale = false
    @Published private(set) var bufferFailureMessage: String?
    var diagnostics: PlaybackDiagnostics { engine.diagnostics }

    // Transport exposes intent so Pause remains available while waiting or seeking.
    var isPlaying: Bool { wantsPlayback }
    var isAudible: Bool { audioIsAdvancing && wantsPlayback && !interruptionActive && engine.volume > 0 }
    var transportClock: PlaybackTransportClock { engine.transportClock }
    var currentOutputName: String { currentOutputRoute.ports.isEmpty ? "System output unavailable" : currentOutputRoute.name }
    var scheduledOutput: ScheduledOutputPreference { scheduleRequest?.output ?? settings.scheduledOutputDefault ?? .speaker }
    var scheduledOptions: ScheduledStartOptions { scheduleRequest?.options ?? settings.scheduledStartDefaults ?? .init() }
    private var protectedSchedule: Bool { pendingProtectedSchedule || scheduleRequest?.requiresDeletionToCancel == true }
    private var scheduledSpeakerRequired: Bool {
        scheduleRequest != nil && (scheduleRequest?.output.mode == .speaker || scheduleUsingSpeakerFallback)
    }
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
    private var interruptionRetryStarted: TimeInterval?
    private var interruptionRetryAt: TimeInterval = 0
    private var explicitPlayPending = false
    private var manualPlaybackOverridesSchedule = false
    private var manualPlaybackPrecedesStart = false
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
    private var scheduleUsingSpeakerFallback = false
    private var scheduleReachedFullGain = false
    // A future start releases a manual pause at its deadline. Once that time
    // has passed, only Play releases the pause (represented by distantFuture).
    private var schedulePausedUntil: Date?
    private var scheduleRetryUptime: TimeInterval = 0
    private var scheduledBattery = ScheduledBatteryGuard()
    private var speakerSessionActive = false
    private var sessionMixesWithOthers = false
    private var scheduledHasAudioFocus = false
    private var pendingProtectedSchedule = false
    private var gainTimer: Timer?
    private var scheduleBoundaryTimer: Timer?
    private var lastSurfacePlaying: Bool?
    #if DEBUG
    private var scheduleDiagnostics: [String] = []
    private var lastDiagnosticGain: Float = -1
    private var isUIFixture = ProcessInfo.processInfo.environment["KUSC_UI_STATE"] != nil
    private var boundaryGainTrace: [Float]?
    private var audioRecoveryTestConnections: Int?
    struct ScheduleTestEnvironment {
        var now: Date
        var uptime: TimeInterval
        var plugged: Bool
        var level: Double
        var route: ObservedAudioRoute
        var activationFails = false
        var otherAudioPlaying = false
    }
    private var scheduleTestEnvironment: ScheduleTestEnvironment?
    private var scheduleTestStandby = false
    private var sessionActivationAttempts: [(speaker: Bool, mixing: Bool)] = []
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
        restoreScheduledRequest()
        if scheduleRequest == nil, let date = UserDefaults.standard.object(forKey: "scheduledAt") as? Date, date > Date() {
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
        ensureTicker()
        // Play is fresh user intent, independent of automatic route/power policy
        // and of a possibly stale interruption notification. Ask iOS now.
        manualPlaybackOverridesSchedule = scheduleRequest != nil
        manualPlaybackPrecedesStart = scheduleRequest.map { scheduleNow < $0.date } ?? false
        scheduleOwnsPlayback = false; scheduleEnvelope = nil; scheduledHasAudioFocus = false
        schedulePausedUntil = nil; persistSchedule()
        if let remaining = pausedSleepRemaining {
            sleepDeadline = Date().addingTimeInterval(remaining); pausedSleepRemaining = nil
        }
        wantsPlayback = true
        stopStandby()
        scheduleGain = 1; notice = nil
        explicitPlayPending = true; interruptionActive = true
        interruptionRetryStarted = scheduleUptime; interruptionRetryAt = scheduleUptime
        applyGain()
        retryInterruptedPlayback(immediately: true)
    }

    private func resumeCurrentAudio() {
        if hasStartedEngine, reconnectStarted == nil {
            if let pausedAt, settings.resumeWherePaused, let window = bufferWindow {
                engine.seek(to: ResumePolicy.target(mode: .wherePaused, pausedAt: pausedAt, window: window))
            } else if pausedAt != nil { engine.goLive() }
            self.pausedAt = nil
            engine.play()
            state = .connecting
        } else {
            reconnectStarted = nil
            startConnection(preserveScheduledGain: true)
        }
        fetchMetadata()
    }

    private var otherAudioIsPlaying: Bool {
        #if DEBUG
        if let environment = scheduleTestEnvironment { return environment.otherAudioPlaying }
        if audioRecoveryTestConnections != nil { return false }
        #endif
        return AVAudioSession.sharedInstance().isOtherAudioPlaying
    }

    private func retryInterruptedPlayback(immediately: Bool = false) {
        guard interruptionActive, wantsPlayback, schedulePausedUntil == nil, !scheduleOwnsPlayback else { return }
        // Automatic recovery must not take audio back from an app the user chose.
        // Pressing Play explicitly requests focus even while another app plays.
        guard explicitPlayPending || !otherAudioIsPlaying else { return }
        let uptime = scheduleUptime
        guard immediately || uptime >= interruptionRetryAt else { return }
        if interruptionRetryStarted == nil { interruptionRetryStarted = uptime }
        let interval: TimeInterval = uptime - interruptionRetryStarted! < 60 ? 5 : 15
        interruptionRetryAt = uptime + interval
        do { try activateSession(forceSpeaker: false) }
        catch {
            state = .interrupted
            notice = "Waiting for iOS audio access. Play retries now; Pause cancels the retry."
            return
        }
        interruptionActive = false; wasPlayingBeforeInterruption = false
        explicitPlayPending = false; interruptionRetryStarted = nil
        notice = nil; stopStandby(); applyGain()
        resumeCurrentAudio()
    }

    @discardableResult func pauseFromApp() -> Bool {
        pauseRemote()
        return sleepActive
    }

    func pauseRemote() {
        explicitPlayPending = false; interruptionRetryStarted = nil
        manualPlaybackOverridesSchedule = false; manualPlaybackPrecedesStart = false
        if let request = scheduleRequest {
            schedulePausedUntil = scheduleNow < request.date ? request.date : .distantFuture
            scheduleEnvelope = nil
            persistSchedule()
        }
        if !sleepActive || protectedSchedule { gainTimer?.invalidate(); gainTimer = nil }
        wantsPlayback = false
        audioIsAdvancing = false; applyGain()
        if reconnectStarted != nil || state == .connecting {
            engine.stop(); hasStartedEngine = false; bufferWindow = nil
        }
        pausedAt = heardAt
        connectionTask?.cancel(); connectionTask = nil
        connectionGeneration = UUID()
        reconnectStarted = nil
        engine.pause()
        state = bufferWindow != nil && (bufferWindow!.live.timeIntervalSince(heardAt) > 12) ? .pausedDelayed : .pausedLive
        evaluateSchedule()
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
        if protectedSchedule { if scheduleOwnsPlayback { engine.goLive() }; return }
        scheduleGeneration.invalidate()
        if scheduleOwnsPlayback { clearSchedule(stopOwnedPlayback: false); scheduleGain = 1; applyGain() }
        if !hasStartedEngine { play(); return }
        if !wantsPlayback { play() }
        engine.goLive(); pausedAt = nil
        invalidateSleepEndpoint()
    }

    func seek(to date: Date) {
        if protectedSchedule { if scheduleOwnsPlayback { engine.seek(to: date) }; return }
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

    func scheduleStart(at date: Date, output: ScheduledOutputPreference = .speaker,
                       options: ScheduledStartOptions = .init()) async throws {
        guard StandbyPolicy.isValidSchedule(date, now: Date()) else { throw ScheduleError.outsideWindow }
        guard output.mode != .selected || output.route?.isIdentifiable == true else { throw ScheduleError.missingOutput }
        clearSchedule(stopOwnedPlayback: true)
        let generation = scheduleGeneration.begin()
        let request = ScheduledStartRequest(date: date, output: output, options: options)
        pendingProtectedSchedule = request.requiresDeletionToCancel
        do { try await NotificationCoordinator.shared.schedule(request) }
        catch {
            if !request.requiresDeletionToCancel {
                if scheduleGeneration.accepts(generation) { pendingProtectedSchedule = false }
                throw error
            }
            // Notification permission is not an extra stop condition for the
            // explicit battery-only policy. Audio still needs an executing app.
            if scheduleGeneration.accepts(generation) { notice = "Start armed. Enable notifications for a backup reminder." }
        }
        guard scheduleGeneration.accepts(generation) else {
            NotificationCoordinator.shared.cancel(requestID: request.id); return
        }
        ensureTicker()
        scheduleRequest = request; notificationOnly = false; unpluggedAt = nil
        pendingProtectedSchedule = false
        settings.scheduledStartDefaults = options; settings.scheduledOutputDefault = output; settings.save()
        persistSchedule(); armScheduleBoundary()
        evaluateSchedule()
    }
    func cancelSchedule() {
        clearSchedule(stopOwnedPlayback: true)
    }
    func openScheduleCancellation(requestID: UUID?) {
        guard let requestID, scheduleRequest?.id == requestID else { return }
        if scheduleDescription == nil, let request = scheduleRequest {
            scheduleDescription = "\(request.date.formatted(date: .omitted, time: .shortened)) · \(request.output.summary)"
        }
        scheduleManagementRequest = UUID()
    }
    func clearScheduleManagementRequest() { scheduleManagementRequest = nil }
    func startFromNotification(requestID: UUID? = nil) {
        guard let request = scheduleRequest, request.id == requestID else { return }
        if schedulePausedUntil != nil { play(); return }
        if scheduleOwnsPlayback { return } // Duplicate delivery cannot restart an envelope.
        if wantsPlayback && protectedSchedule { evaluateSchedule(); return }
        if wantsPlayback { clearSchedule(stopOwnedPlayback: false); return }
        guard !interruptionActive else { notice = "Wait for the audio interruption to end, then tap Play."; return }
        notificationOnly = false
        scheduleUserInitiated = true // A notification tap is explicit foreground playback intent.
        guard schedulePowerPermits(now: Date()) else { scheduleFallback("The scheduled start is stopped by its power settings."); return }
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
    func configureScheduleReminderFixture() {
        precondition(isUIFixture)
        let request = ScheduledStartRequest(date: Date().addingTimeInterval(300), output: .speaker,
                                            options: .init(batteryOnlyStop: true))
        scheduleRequest = request
        scheduleDescription = "Starts in 5 minutes · Always iPhone speaker"
        openScheduleCancellation(requestID: request.id)
    }

    /// Hosted XCTest exercises the real coordinator/engine gain boundary without
    /// starting an AVPlayer, changing the audio session, or contacting the station.
    func configureScheduledGainBoundaryTest(schedule: Float, sleep: Float) {
        precondition(isUIFixture, "Boundary tests require the isolated UI fixture launch environment")
        finishScheduleForTesting()
        ticker?.invalidate(); ticker = nil
        gainTimer?.invalidate(); gainTimer = nil
        scheduleTestEnvironment = .init(now: Date(), uptime: ProcessInfo.processInfo.systemUptime,
            plugged: true, level: 1, route: .init(ports: [.init(uid: "speaker", type: "Speaker", name: "iPhone")]))
        scheduleRequest = ScheduledStartRequest(date: scheduleNow.addingTimeInterval(60))
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

    func configureScheduleForTesting(output: ScheduledOutputPreference = .speaker,
                                     options: ScheduledStartOptions = .init(allowOnBattery: true),
                                     secondsUntilStart: TimeInterval = 120,
                                     environment: ScheduleTestEnvironment) {
        precondition(isUIFixture)
        finishAudioRecoveryForTesting()
        scheduleTestEnvironment = environment
        sessionActivationAttempts = []
        audioRecoveryTestConnections = 0
        scheduleRequest = .init(date: environment.now.addingTimeInterval(secondsUntilStart), output: output, options: options)
        currentOutputRoute = environment.route
        notificationOnly = false
        evaluateSchedule()
    }
    func advanceScheduleForTesting(seconds: TimeInterval = 0, plugged: Bool? = nil, level: Double? = nil,
                                   route: ObservedAudioRoute? = nil, activationFails: Bool? = nil,
                                   otherAudioPlaying: Bool? = nil) {
        scheduleTestEnvironment?.now.addTimeInterval(seconds)
        if let environment = scheduleTestEnvironment { scheduleTestEnvironment?.uptime = environment.uptime + seconds }
        if let plugged { scheduleTestEnvironment?.plugged = plugged }
        if let level { scheduleTestEnvironment?.level = level }
        if let activationFails { scheduleTestEnvironment?.activationFails = activationFails }
        if let otherAudioPlaying { scheduleTestEnvironment?.otherAudioPlaying = otherAudioPlaying }
        if let route {
            scheduleTestEnvironment?.route = route
            handleRouteChange(reason: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue)
        }
        retryInterruptedPlayback()
        evaluateSchedule()
    }
    func simulateScheduledReadinessForTesting() {
        audioIsAdvancing = true
        updateGains()
    }
    func interruptScheduledAudioForTesting() { beginInterruption() }
    func failScheduledConnectionForTesting() {
        connectionFailed(SilentStandby.StandbyError.failed)
        reconnectStarted = Date().addingTimeInterval(-61)
        tick()
    }
    func finishScheduleForTesting() {
        finishAudioRecoveryForTesting()
        scheduleTestEnvironment = nil
        scheduleTestStandby = false
    }
    func reloadScheduleForTesting() {
        precondition(scheduleTestEnvironment != nil)
        persistSchedule()
        stopEverything(reason: .idle); stopStandby()
        scheduleRequest = nil; scheduleOwnsPlayback = false; schedulePausedUntil = nil
        scheduleReachedFullGain = false; scheduleEnvelope = nil; scheduleGain = 1
        notificationOnly = false
        manualPlaybackOverridesSchedule = false; manualPlaybackPrecedesStart = false
        restoreScheduledRequest()
        evaluateSchedule()
    }
    var scheduleStateForTesting: (exists: Bool, owned: Bool, standby: Bool, notificationOnly: Bool,
                                   lowSince: TimeInterval?, fullGain: Bool, speakerSession: Bool) {
        (scheduleRequest != nil, scheduleOwnsPlayback, standbyIsRunning, notificationOnly,
         scheduledBattery.lowSince, scheduleReachedFullGain, speakerSessionActive)
    }
    var sessionStateForTesting: (mixing: Bool, attempts: Int, exclusiveAttempts: Int) {
        (sessionMixesWithOthers, sessionActivationAttempts.count, sessionActivationAttempts.filter { !$0.mixing }.count)
    }
    var scheduleIDForTesting: UUID? { scheduleRequest?.id }
    #endif

    private func startConnection(preserveScheduledGain: Bool = false) {
        bufferFailureMessage = nil
        connectionTask?.cancel()
        let generation = UUID(); connectionGeneration = generation
        if scheduleOwnsPlayback && !preserveScheduledGain { scheduleReachedFullGain = false; scheduleEnvelope = nil; scheduleGain = 0; applyGain() }
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
        if scheduleOwnsPlayback { scheduleReachedFullGain = false; scheduleEnvelope = nil; scheduleGain = 0; applyGain() }
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
        if scheduleOwnsPlayback && !scheduleReachedFullGain {
            if audioIsAdvancing && snapshot.isReady && !interruptionActive {
                if scheduleEnvelope == nil {
                    if !snapshot.hasConfirmedPosition { recordScheduleDiagnostic("audio ready; station timestamp unavailable") }
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
            if wantsPlayback && (!scheduleOwnsPlayback || scheduleReachedFullGain) {
                if snapshot.isSeeking { state = .seeking }
                else if snapshot.isWaiting || snapshot.acquisitionIsStale { state = .buffering }
                else if sleepGain < 1 { state = .fadingOut }
                else { state = snapshot.isAtLiveEdge ? .playingLive : .playingDelayed }
            }
        } else if wantsPlayback && reconnectStarted == nil && (!scheduleOwnsPlayback || scheduleReachedFullGain) {
            state = snapshot.isSeeking ? .seeking : (snapshot.isReady ? .buffering : .connecting)
        }
        if snapshot.hasConfirmedPosition { resolveMetadata() }
        else { refreshSystemSurfaces() }
    }

    private func ensureTicker() {
        if isScheduleTesting { return }
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        ticker?.tolerance = 0.2
    }

    private func tick() {
        let now = Date()
        retryInterruptedPlayback()
        if let started = reconnectStarted, !interruptionActive {
            objectWillChange.send()
            if ReconnectPolicy(startedAt: started).decision(at: now) == .stop {
                if protectedSchedule {
                    waitForScheduledAudio("Waiting for the station; this start remains armed.", retryAfter: 15)
                }
                else if scheduleOwnsPlayback { scheduleFallback("The station could not connect. Tap to try KUSC again.") }
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
        if protectedSchedule {
            if sleepActive { sleepDescription = "Sleep timer ignored while the persistent scheduled start is active" }
            sleepGain = 1
            return
        }
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
        guard !protectedSchedule else { return }
        // Stop before resetting envelopes; cancellation must never expose one full-volume frame.
        if scheduleOwnsPlayback && schedulePausedUntil == nil { clearSchedule(stopOwnedPlayback: true) }
        stopEverything(reason: .stoppedBySleepTimer); cancelSleep()
    }
    private func stopEverything(reason: PlaybackState) {
        explicitPlayPending = false; interruptionRetryStarted = nil
        wantsPlayback = false; hasStartedEngine = false; pausedAt = nil; reconnectStarted = nil
        audioIsAdvancing = false; applyGain(); connectionGeneration = UUID()
        connectionTask?.cancel(); connectionTask = nil
        metadataTask?.cancel(); metadataTask = nil
        artworkTask?.cancel(); artworkTask = nil
        engine.stop(); bufferWindow = nil; state = reason
        refreshSystemSurfaces()
        if scheduledAt == nil && !isScheduleTesting { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    private func evaluateSchedule() {
        #if DEBUG
        guard !isUIFixture || scheduleTestEnvironment != nil else { return }
        #endif
        guard let request = scheduleRequest else { return }
        let now = scheduleNow
        let dueForPreparation = ScheduledStartPolicy.shouldPrepare(target: request.date, now: now)
        if manualPlaybackOverridesSchedule {
            if manualPlaybackPrecedesStart && now >= request.date {
                manualPlaybackOverridesSchedule = false; manualPlaybackPrecedesStart = false
            } else {
                if (interruptionActive || !wantsPlayback) && now < request.date { maintainMixingStandby() }
                scheduleDescription = now < request.date
                    ? "\(request.date.formatted(date: .omitted, time: .shortened)) · \(request.output.summary)"
                    : "Saved start · manual playback"
                return
            }
        }
        if notificationOnly {
            setSchedulePhase(.notificationOnly)
            scheduleDescription = "\(request.date.formatted(date: .omitted, time: .shortened)) · tap notification to play · \(request.output.summary)"
            return
        }
        guard schedulePowerPermits(now: now) else {
            scheduleFallback("The scheduled start stopped because of its power settings. Tap to try again when power permits."); return
        }
        if let until = schedulePausedUntil {
            if now < until {
                setSchedulePhase(.paused)
                scheduleDescription = now < request.date
                    ? "Paused · start at \(request.date.formatted(date: .omitted, time: .shortened)) · \(request.output.summary)"
                    : "Paused · tap Play to resume · \(request.output.summary)"
                // Keep future intent alive without restarting the paused stream.
                if now < request.date, !standbyIsRunning {
                    maintainMixingStandby()
                } else if now >= request.date { stopStandby() }
                return
            }
            schedulePausedUntil = nil; scheduleOwnsPlayback = false
            persistSchedule()
        }
        if wantsPlayback && !scheduleOwnsPlayback {
            if dueForPreparation && request.output.mode == .currentOutput { clearSchedule(stopOwnedPlayback: false); return }
            if !dueForPreparation {
                if interruptionActive { maintainMixingStandby() } else { stopStandby() }
                setSchedulePhase(.waiting)
                scheduleDescription = "\(request.date.formatted(date: .omitted, time: .shortened)) · \(request.output.summary)"
                return
            }
        }
        if interruptionActive {
            guard request.output.mode != .currentOutput || request.survivesInterruption || scheduleUsingSpeakerFallback else {
                scheduleFallback("An audio interruption prevented the scheduled start. Tap to start when it ends."); return
            }
            // Some route/suspension interruptions have no matching .ended event.
            // A successful public session activation is the permission to resume;
            // calls that still own audio reject it, leaving the request armed.
            guard scheduleUptime >= scheduleRetryUptime else { return }
            scheduleRetryUptime = scheduleUptime + 5
            do { try activateSession(forceSpeaker: now >= request.date && scheduledSpeakerRequired,
                                     mixWithOthers: now < request.date) }
            catch { return }
            interruptionActive = false; wasPlayingBeforeInterruption = false
            scheduleRetryUptime = 0
            if scheduleOwnsPlayback {
                if hasStartedEngine { engine.play() } else { startConnection() }
            }
        }
        guard scheduleUptime >= scheduleRetryUptime else { return }
        if scheduleOwnsPlayback {
            guard validateScheduledRoute(request) else { return }
            updateGains(); return
        }
        if dueForPreparation {
            beginScheduledPlayback(request)
        } else if wantsPlayback {
            stopStandby()
            setSchedulePhase(.waiting)
        } else {
            do {
                if !standbyIsRunning {
                    // Pin speaker only when real scheduled audio starts. Setting
                    // up a future start must not reroute current system audio.
                    try activateSession(forceSpeaker: false, mixWithOthers: true); try startStandby()
                }
                state = .scheduledStandby; setSchedulePhase(.standby)
            } catch {
                if request.survivesInterruption { waitForScheduledAudio("Waiting for audio; scheduled start remains armed.") }
                else { scheduleFallback("Automatic standby is unavailable. Tap to start KUSC live.") }
            }
        }
        if scheduleRequest != nil, !notificationOnly {
            scheduleDescription = "\(request.date.formatted(date: .omitted, time: .shortened)) · \(request.output.summary)"
        }
    }

    private func schedulePowerPermits(now: Date) -> Bool {
        guard let request = scheduleRequest else { return true }
        let power = schedulePower
        if request.output.mode != .currentOutput {
            if scheduledBattery.shouldStop(uptime: scheduleUptime, plugged: power.plugged,
                                           level: power.level, options: request.options) { return false }
            return power.plugged || request.options.allowOnBattery
        }
        // Preserve the original behavior only for legacy current-output requests.
        if scheduleUserInitiated { return true }
        switch StandbyPolicy.update(now: now, isPluggedIn: power.plugged, batteryLevel: power.level,
                                   unpluggedAt: unpluggedAt, wasStandingBy: standbyIsRunning || scheduleOwnsPlayback) {
        case .standby(let since): unpluggedAt = since; return true
        case .notificationOnly: return false
        }
    }

    private var scheduleNow: Date {
        #if DEBUG
        if let environment = scheduleTestEnvironment { return environment.now }
        #endif
        return Date()
    }
    private var scheduleUptime: TimeInterval {
        #if DEBUG
        if let environment = scheduleTestEnvironment { return environment.uptime }
        #endif
        return ProcessInfo.processInfo.systemUptime
    }
    private var schedulePower: (plugged: Bool, level: Double) {
        #if DEBUG
        if let environment = scheduleTestEnvironment { return (environment.plugged, environment.level) }
        #endif
        let device = UIDevice.current
        return (device.batteryState == .charging || device.batteryState == .full, Double(device.batteryLevel))
    }
    private var isScheduleTesting: Bool {
        #if DEBUG
        return scheduleTestEnvironment != nil || audioRecoveryTestConnections != nil
        #else
        return false
        #endif
    }
    private var standbyIsRunning: Bool {
        #if DEBUG
        if scheduleTestEnvironment != nil { return scheduleTestStandby }
        #endif
        return standby.running
    }
    private func startStandby() throws {
        #if DEBUG
        if scheduleTestEnvironment != nil { scheduleTestStandby = true; return }
        #endif
        try standby.start()
    }
    private func stopStandby() {
        #if DEBUG
        scheduleTestStandby = false
        #endif
        standby.stop()
    }

    private func maintainMixingStandby() {
        guard !standbyIsRunning, scheduleUptime >= scheduleRetryUptime else { return }
        do {
            try activateSession(forceSpeaker: false, mixWithOthers: true)
            try startStandby()
        } catch { scheduleRetryUptime = scheduleUptime + 5 }
    }

    private func waitForScheduledAudio(_ message: String, retryAfter: TimeInterval = 5) {
        guard scheduleRequest != nil else { return }
        scheduleGain = 0; applyGain()
        if scheduleOwnsPlayback { stopEverything(reason: .idle) }
        scheduleOwnsPlayback = false; scheduleReachedFullGain = false; scheduleEnvelope = nil
        scheduledHasAudioFocus = false
        stopStandby()
        scheduleRetryUptime = scheduleUptime + retryAfter
        setSchedulePhase(.waiting); scheduleDescription = message
        recordScheduleDiagnostic(message)
        ensureTicker()
    }

    private func beginScheduledPlayback(_ request: ScheduledStartRequest) {
        guard scheduleRequest?.id == request.id, !scheduleOwnsPlayback, !interruptionActive else { return }
        scheduleOwnsPlayback = true
        scheduledHasAudioFocus = false
        scheduleGain = 0
        // Gain reaches the player before session activation, reconnect, or play.
        applyGain()
        let preparingSilently = scheduleNow < request.date && !scheduleUserInitiated
        do { try activateSession(forceSpeaker: !preparingSilently && scheduledSpeakerRequired,
                                 mixWithOthers: preparingSilently) }
        catch {
            if request.survivesInterruption { waitForScheduledAudio("Waiting for iPhone audio; scheduled start remains armed.") }
            else { scheduleFallback("KUSC could not activate audio. Tap to try again.") }
            return
        }
        guard validateScheduledRoute(request) else { return }
        scheduleOwnsPlayback = true; scheduleEnvelope = nil; scheduleReachedFullGain = false
        wantsPlayback = true; pausedAt = nil; reconnectStarted = nil
        connectionTask?.cancel(); engine.stop(); hasStartedEngine = false
        applyGain(); stopStandby()
        setSchedulePhase(.preparing)
        ensureTicker(); startGainDriver(); startConnection(); fetchMetadata()
    }

    private func validateScheduledRoute(_ request: ScheduledStartRequest) -> Bool {
        // Silent preloading must neither reroute accessories nor interrupt another app.
        if scheduleNow < request.date && !scheduleUserInitiated { return true }
        refreshCurrentOutput()
        if request.output.mode == .selected && request.output.fallback == .speaker,
           request.output.route?.matches(currentOutputRoute) != true {
            scheduleUsingSpeakerFallback = true
        }
        if !scheduledHasAudioFocus {
            // Preroll readiness belongs to the mixable session. Wait for a fresh
            // engine sample after takeover before starting the audible fade.
            if request.output.mode != .currentOutput { audioIsAdvancing = false }
            do { try activateSession(forceSpeaker: scheduledSpeakerRequired) }
            catch { waitForScheduledAudio("Waiting for audio; scheduled start remains armed."); return false }
            scheduledHasAudioFocus = true
            refreshCurrentOutput()
        }
        if scheduledSpeakerRequired {
            guard !currentOutputRoute.isBuiltInSpeaker else { return true }
            scheduleGain = 0; scheduleEnvelope = nil; scheduleReachedFullGain = false; applyGain()
            engine.pause()
            do { try activateSession(forceSpeaker: true) }
            catch { waitForScheduledAudio("Waiting for the iPhone speaker; scheduled start remains armed."); return false }
            refreshCurrentOutput()
            guard currentOutputRoute.isBuiltInSpeaker else {
                waitForScheduledAudio("Waiting for the iPhone speaker; scheduled start remains armed.")
                return false
            }
            if scheduleOwnsPlayback && wantsPlayback { engine.play() }
            return true
        }
        guard request.output.permits(currentOutputRoute) else {
            scheduleGain = 0; applyGain()
            let name = request.output.route?.name ?? "Audio output"
            scheduleFallback("\(name) is unavailable or no longer selected. Choose an output, then tap Play.")
            return false
        }
        return true
    }

    func refreshCurrentOutput() {
        #if DEBUG
        if let environment = scheduleTestEnvironment { currentOutputRoute = environment.route; return }
        #endif
        let route = ObservedAudioRoute(ports: AVAudioSession.sharedInstance().currentRoute.outputs.map {
            .init(uid: $0.uid, type: $0.portType.rawValue, name: $0.portName)
        })
        if currentOutputRoute != route { currentOutputRoute = route }
    }

    private func scheduleFallback(_ message: String) {
        guard let request = scheduleRequest else { return }
        recordScheduleDiagnostic("fallback \(message)")
        scheduleGain = 0; applyGain()
        let owned = scheduleOwnsPlayback || request.requiresDeletionToCancel
        scheduleOwnsPlayback = false; scheduleEnvelope = nil; scheduleUserInitiated = false
        notificationOnly = true; stopStandby(); setSchedulePhase(.notificationOnly)
        persistSchedule()
        if owned { stopEverything(reason: .idle) }
        else if state == .scheduledStandby { state = .idle }
        scheduleGain = 1; applyGain()
        releaseScheduledSessionIfIdle()
        notice = message
        scheduleDescription = "\(request.date.formatted(date: .omitted, time: .shortened)) · tap notification to play · \(request.output.summary)"
        if !isScheduleTesting { NotificationCoordinator.shared.replaceFallback(request, body: message) }
    }

    private func clearSchedule(stopOwnedPlayback: Bool) {
        if scheduleRequest != nil { recordScheduleDiagnostic("clear stopOwned=\(stopOwnedPlayback)") }
        scheduleGeneration.invalidate()
        pendingProtectedSchedule = false
        let owned = scheduleOwnsPlayback || (scheduleRequest?.requiresDeletionToCancel == true && wantsPlayback)
        if owned && stopOwnedPlayback {
            scheduleGain = 0; applyGain()
            stopEverything(reason: .idle)
        }
        if let request = scheduleRequest { NotificationCoordinator.shared.cancel(requestID: request.id) }
        scheduleRequest = nil; scheduleOwnsPlayback = false; scheduleEnvelope = nil
        scheduledBattery = ScheduledBatteryGuard(); scheduleUsingSpeakerFallback = false
        scheduleReachedFullGain = false; scheduleRetryUptime = 0; schedulePausedUntil = nil
        scheduledHasAudioFocus = false
        manualPlaybackOverridesSchedule = false; manualPlaybackPrecedesStart = false
        scheduleUserInitiated = false; unpluggedAt = nil; notificationOnly = false
        scheduleDescription = nil; schedulePhase = nil; stopStandby()
        scheduleManagementRequest = nil
        scheduleBoundaryTimer?.invalidate(); scheduleBoundaryTimer = nil
        persistSchedule()
        scheduleGain = 1; applyGain()
        if state == .scheduledStandby { state = .idle }
        if speakerSessionActive && wantsPlayback { try? activateSession(forceSpeaker: false) }
        releaseScheduledSessionIfIdle()
    }

    private func releaseScheduledSessionIfIdle() {
        guard !wantsPlayback else { return }
        if !isScheduleTesting {
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            if speakerSessionActive { try? session.setCategory(.playback, mode: .default, policy: .longFormAudio) }
        }
        speakerSessionActive = false
        sessionMixesWithOthers = false
    }

    private func persistSchedule() {
        UserDefaults.standard.set(notificationOnly && scheduleRequest != nil, forKey: "scheduledNotificationOnly.v2")
        UserDefaults.standard.set(scheduleRequest == nil ? nil : schedulePausedUntil, forKey: "scheduledPauseUntil.v2")
        if let request = scheduleRequest, let data = try? JSONEncoder().encode(request) {
            UserDefaults.standard.set(data, forKey: "scheduledStart.v2")
        } else { UserDefaults.standard.removeObject(forKey: "scheduledStart.v2") }
    }

    private func restoreScheduledRequest() {
        guard let data = UserDefaults.standard.data(forKey: "scheduledStart.v2"),
              let request = try? JSONDecoder().decode(ScheduledStartRequest.self, from: data) else { return }
        scheduleRequest = request
        schedulePausedUntil = UserDefaults.standard.object(forKey: "scheduledPauseUntil.v2") as? Date
        // A saved manual pause takes precedence over persistent auto-recovery.
        notificationOnly = (schedulePausedUntil == nil && !request.requiresDeletionToCancel && request.date <= scheduleNow)
            || UserDefaults.standard.bool(forKey: "scheduledNotificationOnly.v2")
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
        if isScheduleTesting { return }
        guard gainTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateGains() }
        }
        timer.tolerance = 0.002
        RunLoop.main.add(timer, forMode: .common)
        gainTimer = timer
    }

    private func updateGains() {
        let now = scheduleNow
        if scheduleOwnsPlayback, let request = scheduleRequest {
            guard schedulePowerPermits(now: now) else {
                scheduleFallback("The scheduled start stopped because of its power settings."); return
            }
            if schedulePausedUntil != nil { applyGain(); return }
            if interruptionActive { scheduleGain = 0; applyGain(); return }
            guard validateScheduledRoute(request) else { return }
            if !scheduleReachedFullGain, scheduleEnvelope == nil, audioIsAdvancing {
                if request.output.mode == .currentOutput || now >= request.date {
                    // New starts always get ten audible seconds. A delayed wake,
                    // route handoff or stream readiness must not consume the ramp.
                    let target = request.output.mode == .currentOutput ? request.date : now
                    scheduleEnvelope = ScheduledGainEnvelope(target: target, readyAt: now, uptime: scheduleUptime)
                    startGainDriver()
                }
            }
            if scheduleReachedFullGain { scheduleGain = 1 }
            else if let envelope = scheduleEnvelope, audioIsAdvancing {
                let uptime = scheduleUptime
                scheduleGain = envelope.gain(at: uptime)
                setSchedulePhase(scheduleGain > 0 ? .fading : .silent)
                let newState: PlaybackState = scheduleGain > 0 ? .scheduledFadeIn : .scheduledSilent
                if state != newState { state = newState }
                if envelope.isComplete(at: uptime) {
                    if request.output.mode == .currentOutput { clearSchedule(stopOwnedPlayback: false) }
                    else {
                        scheduleReachedFullGain = true; scheduleEnvelope = nil
                        setSchedulePhase(.playing)
                        scheduleDescription = "Playing · \(request.output.summary)"
                        NotificationCoordinator.shared.cancel(requestID: request.id)
                    }
                    state = .playingLive
                }
            } else {
                scheduleGain = 0
                setSchedulePhase(audioIsAdvancing ? .silent : .preparing)
                if audioIsAdvancing && state != .scheduledSilent { state = .scheduledSilent }
            }
        }
        var sleepFading = false
        if !protectedSchedule, case .fade(let start, let end)? = sleepDecision, now >= start {
            sleepFading = true
            sleepGain = Float(SleepPolicy.gain(at: now, fadeStart: start, fadeEnd: end))
            if now >= end { finishSleep(); return }
        }
        applyGain()
        if (!scheduleOwnsPlayback || scheduleReachedFullGain) && !sleepFading { gainTimer?.invalidate(); gainTimer = nil }
    }

    private func applyGain() {
        engine.volume = ScheduledStartPolicy.composedGain(schedule: scheduleGain, sleep: protectedSchedule ? 1 : sleepGain,
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

    private func activateSession(forceSpeaker: Bool? = nil, mixWithOthers: Bool? = nil) throws {
        let silentPreparation = scheduleOwnsPlayback && !scheduleUserInitiated && scheduledAt.map { scheduleNow < $0 } == true
        let mixing = mixWithOthers ?? silentPreparation
        let useSpeaker = forceSpeaker ?? (!silentPreparation && scheduleOwnsPlayback && scheduledSpeakerRequired)
        #if DEBUG
        if let environment = scheduleTestEnvironment {
            sessionActivationAttempts.append((useSpeaker, mixing))
            if environment.activationFails { throw SilentStandby.StandbyError.failed }
            if useSpeaker {
                scheduleTestEnvironment?.route = .init(ports: [.init(uid: "speaker", type: "Speaker", name: "iPhone")])
            }
            speakerSessionActive = useSpeaker
            sessionMixesWithOthers = mixing
            refreshCurrentOutput()
            return
        }
        if audioRecoveryTestConnections != nil { return }
        #endif
        let audio = AVAudioSession.sharedInstance()
        if useSpeaker {
            // Public speaker override requires playAndRecord. No input tap,
            // recorder, or microphone data is used by KUSC.
            if audio.category != .playAndRecord {
                try audio.setCategory(.playAndRecord, mode: .default, policy: .default, options: [.defaultToSpeaker])
            }
            try audio.setActive(true)
            speakerSessionActive = true
            if !audio.currentRoute.outputs.allSatisfy({ $0.portType == .builtInSpeaker }) || audio.currentRoute.outputs.isEmpty {
                try audio.overrideOutputAudioPort(.speaker)
            }
        } else {
            let options: AVAudioSession.CategoryOptions = mixing ? [.mixWithOthers] : []
            if audio.category != .playback || audio.categoryOptions != options || speakerSessionActive {
                try audio.setCategory(.playback, mode: .default,
                                      policy: mixing ? .default : .longFormAudio, options: options)
            }
            speakerSessionActive = false
            try audio.setActive(true)
        }
        sessionMixesWithOthers = mixing
    }

    private func handleMediaServicesReset() {
        // A reset invalidates the media objects even while paused. Do not leave
        // an obsolete renderer available for the next Play or interruption end.
        connectionGeneration = UUID()
        connectionTask?.cancel(); connectionTask = nil
        hasStartedEngine = false
        reconnectStarted = nil
        audioIsAdvancing = false
        scheduledHasAudioFocus = false
        if scheduleOwnsPlayback { scheduleGain = 0; scheduleEnvelope = nil; scheduleReachedFullGain = false }
        applyGain()
        engine.stop(); stopStandby()
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
        if explicitPlayPending {
            retryInterruptedPlayback(immediately: true)
            return
        }
        interruptionActive = false
        if schedulePausedUntil != nil {
            wasPlayingBeforeInterruption = false
            evaluateSchedule(); return
        }
        if let request = scheduleRequest, !notificationOnly,
           request.survivesInterruption || scheduleUsingSpeakerFallback {
            let resumeOrdinaryAudio = wasPlayingBeforeInterruption && wantsPlayback && !scheduleOwnsPlayback
                && (manualPlaybackOverridesSchedule || scheduleNow < request.date)
            wasPlayingBeforeInterruption = false; scheduleRetryUptime = 0
            if scheduleOwnsPlayback {
                guard schedulePowerPermits(now: scheduleNow) else {
                    scheduleFallback("The scheduled start stopped because of its power settings."); return
                }
                do {
                    try activateSession(forceSpeaker: scheduleNow >= request.date && scheduledSpeakerRequired,
                                        mixWithOthers: scheduleNow < request.date)
                    guard validateScheduledRoute(request) else { return }
                    applyGain()
                    if hasStartedEngine, reconnectStarted == nil { engine.play() }
                    else { reconnectStarted = nil; startConnection() }
                } catch { waitForScheduledAudio("Waiting for audio; scheduled start remains armed.") }
            } else {
                if resumeOrdinaryAudio {
                    if shouldResume {
                        interruptionActive = true
                        retryInterruptedPlayback(immediately: true)
                    } else { wantsPlayback = false; applyGain() }
                }
                evaluateSchedule()
            }
            return
        }
        if wasPlayingBeforeInterruption && wantsPlayback && shouldResume {
            interruptionActive = true
            retryInterruptedPlayback(immediately: true)
            invalidateSleepEndpoint()
        } else if wasPlayingBeforeInterruption {
            pauseRemote()
        }
        wasPlayingBeforeInterruption = false
    }

    private func beginInterruption() {
        wasPlayingBeforeInterruption = wantsPlayback
        interruptionActive = true
        explicitPlayPending = false; scheduledHasAudioFocus = false
        interruptionRetryStarted = scheduleUptime; interruptionRetryAt = scheduleUptime + 5
        if scheduleOwnsPlayback { scheduleGain = 0; scheduleEnvelope = nil; scheduleReachedFullGain = false }
        applyGain(); engine.pause(); stopStandby()
        audioIsAdvancing = false
        if wantsPlayback { state = .interrupted }
        if schedulePausedUntil != nil { return }
        if let request = scheduleRequest, (scheduleOwnsPlayback || !wasPlayingBeforeInterruption) {
            if request.survivesInterruption || scheduleUsingSpeakerFallback
                || (request.output.mode != .currentOutput && scheduleNow < request.date) {
                scheduleDescription = "Waiting for audio · \(request.output.summary)"
                setSchedulePhase(.waiting); scheduleRetryUptime = scheduleUptime + 5
            } else {
                scheduleFallback("An audio interruption prevented the scheduled start. Tap to try again when it ends.")
                wasPlayingBeforeInterruption = false
            }
        }
    }

    private func handleRouteChange(reason: UInt) {
        let previous = currentOutputRoute
        refreshCurrentOutput()
        if schedulePausedUntil != nil { return }
        if interruptionActive {
            if !previous.matches(currentOutputRoute) { retryInterruptedPlayback(immediately: true) }
            return
        }
        if scheduleOwnsPlayback, let request = scheduleRequest, !interruptionActive {
            // Category/override notifications with the same output must not restart
            // the fade or produce volume dips. Mute before fixing a changed route.
            if !previous.matches(currentOutputRoute) {
                scheduledHasAudioFocus = false
                scheduleGain = 0; scheduleEnvelope = nil; scheduleReachedFullGain = false; applyGain()
            }
            guard validateScheduledRoute(request) else { return }
        }
        guard reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue,
              wantsPlayback, !interruptionActive else { return }
        do { try activateSession(); applyGain(); engine.play() }
        catch {
            if scheduleOwnsPlayback && scheduledSpeakerRequired { waitForScheduledAudio("Waiting for the iPhone speaker.") }
            else { connectionFailed(error) }
        }
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
                    self.beginInterruption()
                } else {
                    self.endInterruption(shouldResume: AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume))
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] n in
            let reason = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
            Task { @MainActor in
                guard let self else { return }
                self.handleRouteChange(reason: reason)
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
        case outsideWindow, missingOutput
        var errorDescription: String? {
            switch self {
            case .outsideWindow: return "Choose a future time within the next 24 hours."
            case .missingOutput: return "Select and confirm an audio output before scheduling."
            }
        }
    }
}
extension Notification.Name { static let kuscPlaybackChanged = Notification.Name("KUSCPlaybackChanged") }
