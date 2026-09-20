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

    var isPlaying: Bool { wantsPlayback && state.active }
    var sleepActive: Bool { sleepDeadline != nil || pausedSleepRemaining != nil || sleepDecision != nil }
    var statusText: String {
        switch state {
        case .idle: return "Ready to play"
        case .connecting: return "Connecting…"
        case .playingLive: return "Live"
        case .playingDelayed: return "\(Int(max(0, (bufferWindow?.live ?? Date()).timeIntervalSince(heardAt)))) seconds behind live"
        case .pausedLive, .pausedDelayed: return "Paused"
        case .reconnecting(let since): return "Reconnecting… \(min(60, Int(Date().timeIntervalSince(since)))) / 60 s"
        case .fadingOut: return "Sleep timer · fading out"
        case .scheduledStandby: return "Scheduled start · standby"
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
    private var scheduledAt: Date?
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
        if let date = UserDefaults.standard.object(forKey: "scheduledAt") as? Date, date > Date() {
            scheduledAt = date
        } else { UserDefaults.standard.removeObject(forKey: "scheduledAt") }
        ensureTicker()
    }

    func launch() {
        guard !launched else { return }
        launched = true
        fetchMetadata()
        if settings.autoplay { play() }
        evaluateSchedule()
    }

    func updateSettings() {
        settings.retentionMinutes = min(15, max(0, settings.retentionMinutes))
        settings.save()
        if settings.retentionMinutes != appliedSettings.retentionMinutes {
            engine.setRetention(minutes: settings.retentionMinutes)
            if settings.retentionMinutes == 0 { bufferWindow = nil; pausedAt = nil }
        }
        appliedSettings = settings
    }

    func play() {
        ensureTicker()
        if let remaining = pausedSleepRemaining {
            sleepDeadline = Date().addingTimeInterval(remaining); pausedSleepRemaining = nil
        }
        wantsPlayback = true
        standby.stop()
        engine.volume = 1
        do { try activateSession() } catch { notice = error.localizedDescription; wantsPlayback = false; return }
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
        if reconnectStarted != nil || state == .connecting {
            engine.stop(); hasStartedEngine = false; bufferWindow = nil
        }
        wantsPlayback = false
        pausedAt = heardAt
        connectionTask?.cancel(); connectionTask = nil
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
            sleepDeadline = nil; sleepDecision = nil; sleepRetryStarted = nil; engine.volume = 1
        case .cancelTimer: cancelSleep()
        }
    }

    func goLive() {
        if !hasStartedEngine { play(); return }
        if !wantsPlayback { play() }
        engine.goLive(); pausedAt = nil
        invalidateSleepEndpoint()
    }

    func seek(to date: Date) {
        guard let window = bufferWindow, window.contains(date) else { return }
        engine.seek(to: date); heardAt = window.clamped(date)
        if !wantsPlayback { pausedAt = heardAt }
        resolveMetadata(); invalidateSleepEndpoint()
    }

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
        sleepDescription = nil; engine.volume = 1
        if state == .fadingOut { state = wantsPlayback ? .playingLive : .pausedLive }
    }

    func scheduleStart(at date: Date) async throws {
        guard StandbyPolicy.isValidSchedule(date, now: Date()) else { throw ScheduleError.outsideWindow }
        try await NotificationCoordinator.shared.schedule(at: date)
        ensureTicker()
        scheduledAt = date; notificationOnly = false; unpluggedAt = nil
        UserDefaults.standard.set(date, forKey: "scheduledAt")
        evaluateSchedule()
    }
    func cancelSchedule() {
        scheduledAt = nil; unpluggedAt = nil; notificationOnly = false
        scheduleDescription = nil; standby.stop()
        UserDefaults.standard.removeObject(forKey: "scheduledAt")
        NotificationCoordinator.shared.cancelPending()
        if state == .scheduledStandby { state = .idle }
    }
    func startFromNotification() {
        let alreadyPlaying = isPlaying
        cancelSchedule()
        if !alreadyPlaying { play(); engine.goLive() }
    }
    func onForeground() {
        tick(); if hasStartedEngine || currentItem == nil { fetchMetadata() }
    }

    private func startConnection() {
        connectionTask?.cancel()
        if reconnectStarted == nil { state = .connecting }
        hasStartedEngine = true
        connectionTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            do {
                try await engine.start(url: StationConfiguration.audioURL, retentionMinutes: settings.retentionMinutes)
                guard !Task.isCancelled else { return }
                if wantsPlayback { engine.play() } else { engine.pause() }
            } catch {
                if !Task.isCancelled { connectionFailed(error) }
            }
        }
    }

    private func connectionFailed(_ error: Error) {
        guard wantsPlayback else {
            hasStartedEngine = false; engine.stop(); bufferWindow = nil; return
        }
        let now = Date()
        if reconnectStarted == nil { reconnectStarted = now }
        state = .reconnecting(since: reconnectStarted!)
        nextRetry = now.addingTimeInterval(3)
        // No separate Retry control; tick returns to the ordinary idle state after 60 seconds.
    }

    private func receive(_ snapshot: EngineSnapshot) {
        heardAt = snapshot.heardAt; bufferWindow = snapshot.window
        if snapshot.isPlaying {
            if reconnectStarted != nil { invalidateSleepEndpoint() }
            reconnectStarted = nil
            if sleepDecision != nil, case .fade = sleepDecision! { state = .fadingOut }
            else if wantsPlayback { state = snapshot.isAtLiveEdge ? .playingLive : .playingDelayed }
        }
        resolveMetadata()
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
            if ReconnectPolicy(startedAt: started).decision(at: now) == .stop { stopEverything(reason: .idle) }
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
            if now >= start { state = .fadingOut; engine.volume = Float(SleepPolicy.gain(at: now, fadeStart: start, fadeEnd: end)) }
            if now >= end { finishSleep() }
        case .retry:
            sleepDescription = "Sleep timer · checking transition"
        }
    }
    private func invalidateSleepEndpoint() {
        if sleepDeadline.map({ $0 <= Date() }) == true { sleepDecision = nil; sleepRetryStarted = nil; engine.volume = 1 }
    }
    private func finishSleep() {
        cancelSleep(); stopEverything(reason: .stoppedBySleepTimer)
    }
    private func stopEverything(reason: PlaybackState) {
        wantsPlayback = false; hasStartedEngine = false; pausedAt = nil; reconnectStarted = nil
        connectionTask?.cancel(); connectionTask = nil
        metadataTask?.cancel(); metadataTask = nil
        artworkTask?.cancel(); artworkTask = nil
        engine.stop(); bufferWindow = nil; state = reason
        refreshSystemSurfaces()
        if scheduledAt == nil { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    private func evaluateSchedule() {
        guard let date = scheduledAt else { return }
        let now = Date()
        // Validate the power/grace boundary before executing a due start, even if the
        // timer tick coincides exactly with the 10-minute or 30-percent boundary.
        let device = UIDevice.current
        let plugged = device.batteryState == .charging || device.batteryState == .full
        if standby.running {
            if case .notificationOnly = StandbyPolicy.update(now: now, isPluggedIn: plugged,
                batteryLevel: Double(device.batteryLevel), unpluggedAt: unpluggedAt, wasStandingBy: true) {
                standby.stop(); notificationOnly = true
                if state == .scheduledStandby { state = .idle }
            }
        }
        if now >= date {
            let automatic = standby.running
            let alreadyPlaying = isPlaying
            scheduledAt = nil; scheduleDescription = nil; standby.stop()
            UserDefaults.standard.removeObject(forKey: "scheduledAt")
            if !StandbyPolicy.shouldStartScheduled(alreadyPlaying: alreadyPlaying) {
                NotificationCoordinator.shared.cancelPending(); return
            }
            if automatic && !interruptionActive {
                play(); engine.goLive()
            }
            // Retain delivered/pending fallback notification for notification-only or failed standby.
            return
        }
        if isPlaying { standby.stop(); scheduleDescription = "Scheduled · \(date.formatted(date: .omitted, time: .shortened))"; return }
        if interruptionActive { standby.stop(); return }
        if !notificationOnly {
            let decision = StandbyPolicy.update(now: now, isPluggedIn: plugged,
                batteryLevel: Double(device.batteryLevel), unpluggedAt: unpluggedAt, wasStandingBy: standby.running)
            switch decision {
            case .standby(let unplugged):
                unpluggedAt = unplugged
                do { try activateSession(); try standby.start(); state = .scheduledStandby }
                catch { notificationOnly = true; standby.stop(); notice = "Automatic standby unavailable; scheduled notification remains active." }
            case .notificationOnly:
                standby.stop(); notificationOnly = true
                if state == .scheduledStandby { state = .idle }
            }
        }
        scheduleDescription = "\(date.formatted(date: .omitted, time: .shortened)) · \(standby.running ? "automatic standby" : "tap notification to play")"
    }

    private func fetchMetadata() {
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
        currentItem = context.current
        let programme = metadata.programme(at: heardAt)
        programmeName = programme?.name ?? currentItem?.programme
        hostName = programme?.host ?? currentItem?.host
        previousItems = context.previous; upcomingItems = context.upcoming
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
        nowPlaying.update(item: currentItem, artwork: artwork, playing: isPlaying)
        #if MODERN
        liveActivity.update(item: currentItem, artwork: artwork, playing: isPlaying, visible: hasStartedEngine)
        #endif
        NotificationCenter.default.post(name: .kuscPlaybackChanged, object: self)
    }

    private func activateSession() throws {
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
        try audio.setActive(true)
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
                    self.interruptionActive = true; self.engine.pause(); self.standby.stop()
                } else {
                    self.interruptionActive = false
                    if self.wasPlayingBeforeInterruption && self.wantsPlayback && AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                        try? self.activateSession(); self.engine.play(); self.invalidateSleepEndpoint()
                    } else if self.wasPlayingBeforeInterruption {
                        self.pauseRemote()
                    }
                    self.wasPlayingBeforeInterruption = false
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] n in
            let reason = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
            Task { @MainActor in
                guard let self, reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue,
                      self.wantsPlayback, !self.interruptionActive else { return }
                try? self.activateSession(); self.engine.play()
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in guard let self, self.wantsPlayback else { return }; try? self.activateSession(); self.startConnection() }
        })
    }
    enum ScheduleError: LocalizedError {
        case outsideWindow
        var errorDescription: String? { "Choose a future time within the next 24 hours." }
    }
}
extension Notification.Name { static let kuscPlaybackChanged = Notification.Name("KUSCPlaybackChanged") }
