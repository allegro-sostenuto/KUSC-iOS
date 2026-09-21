import AVFoundation
import Foundation
import Combine

/// Only the progress control observes these lightweight media-clock samples.
/// Metadata, artwork and system surfaces continue to receive the slower snapshot.
@MainActor final class PlaybackTransportClock: ObservableObject {
    @Published private(set) var sample = Sample()

    struct Sample {
        var heardAt: Date?
        var window: BufferWindow?
        var sampledAt: TimeInterval = 0
        var isAdvancing = false
        var isAtLiveEdge = false
        var isSeeking = false
        var pendingSeekAt: Date?
        var playableRanges: [ClosedRange<Date>] = []
        /// A UI may interpolate only this much beyond a verified media sample.
        var maximumExtrapolation: TimeInterval = 0.3
    }

    fileprivate func update(_ next: Sample) { sample = next }
    #if DEBUG
    func configureUIFixture(_ next: Sample) { sample = next }
    #endif
}

struct EngineSnapshot {
    let isPlaying: Bool
    let heardAt: Date
    let window: BufferWindow?
    let isReady: Bool
    let live: Date
    let hasAudio: Bool
    /// Uses the safe continuous live target and acquisition freshness, never the
    /// raw final milliseconds of the newest downloaded HLS segment.
    let isAtLiveEdge: Bool
    let playbackRequested: Bool
    let isWaiting: Bool
    let isSeeking: Bool
    let pendingSeekAt: Date?
    let hasConfirmedPosition: Bool
    let downloadedEdge: Date?
    let advertisedEdge: Date?
    let acquisitionLag: TimeInterval?
    let acquisitionIsStale: Bool
    let sampledAt: TimeInterval
}

/// Session ownership, interruption policy and retry deadlines belong to the
/// playback coordinator. This class owns exactly one audio player and one audio
/// acquisition path. A new generation invalidates every callback from its predecessor.
@MainActor
final class RollingAudioEngine {
    var onUpdate: ((EngineSnapshot) -> Void)?
    var onFailure: ((Error) -> Void)?
    let transportClock = PlaybackTransportClock()
    let diagnostics = PlaybackDiagnostics()

    var volume: Float {
        get { outputVolume }
        set {
            outputVolume = min(1, max(0, newValue))
            player?.volume = outputVolume
            bufferedPlayer?.volume = outputVolume
        }
    }

    private var player: AVPlayer?
    private var bufferedPlayer: BufferedAudioRenderer?
    private var sourceURL: URL?
    private var retentionMinutes = 0
    private var segments: [AudioSegment] = []
    private var retention = RetentionResult(retained: [], expired: [], window: nil)
    private var observations: [NSKeyValueObservation] = []
    private var timeObserver: Any?
    private var itemObservation: NSKeyValueObservation?
    private var failedToEndObserver: NSObjectProtocol?
    private var ingestTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var switchTask: Task<Void, Never>?
    private var switchRequest = UUID()
    private var generation = UUID()
    private var seekGeneration = PlaybackSeekGeneration()
    private var shouldPlay = false
    private var outputVolume: Float = 1
    private var pausedAt: Date?
    private var waitingSince: Date?
    private var connectionBegan = Date()
    private var hasStartedPlayback = false
    private var isSeeking = false
    private var seekTargetDate: Date?
    private var cursor = ConfirmedPlaybackCursor()
    private var liveClock = LivePlaybackClock()
    private var advertisedEdge: Date?
    private var lastAcquisitionUptime: TimeInterval?
    private var targetDuration: TimeInterval = 10
    private var lastSlowPublishUptime: TimeInterval = 0
    #if DEBUG
    private(set) var diagnosticEvents: [String] = []
    #endif
    private var directNeedsLiveReload = false
    private var failed = false
    private var wantsInitialLivePosition = true
    private var runDirectory: URL?

    private static var bufferDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("KUSC-RollingAudio", isDirectory: true)
    }

    init() {
        // A process never restores buffered playback after termination.
        try? FileManager.default.removeItem(at: Self.bufferDirectory)
    }

    #if DEBUG
    var transportSessionForTesting: UUID { generation }
    var bufferedTransportForTesting: BufferedAudioRenderer? { bufferedPlayer }
    /// Native XCTest fixture: exercise pending-seek ownership without fetching
    /// the station or requiring an AAC decoder to finish an asynchronous seek.
    func configureBufferedTransportForTesting(segments fixtures: [AudioSegment], pausedAt date: Date?,
                                              initialJoinPending: Bool = false,
                                              loadSamples: @escaping (URL) async throws -> BufferedAudioSamples = BufferedAudioSampleSource.load) {
        stopInternal(publish: false)
        retentionMinutes = 15
        segments = fixtures
        if let end = fixtures.last?.end {
            retention = BufferRetention.trim(fixtures, live: end, minutes: retentionMinutes)
        }
        cursor.record(date)
        pausedAt = date
        wantsInitialLivePosition = initialJoinPending
        hasStartedPlayback = !initialJoinPending
        installBufferedPlayer(loadSamples: loadSamples)
        bufferedPlayer?.updateSegments(segments)
        publish()
    }
    func acceptBufferedSegmentForTesting(_ segment: AudioSegment) { accept(segment) }
    func refillBufferedQueueForTesting() { fillBufferedAudio(); publish() }
    func failForDiagnosticsTesting(_ error: Error) { reportFailure(error, origin: "test.injected") }
    #endif

    func recordDiagnosticSnapshot() {
        guard diagnostics.isRecording else { return }
        recordDiagnostic(diagnosticSnapshot())
    }

    func start(url: URL, retentionMinutes: Int, playbackRequested: Bool = true) async throws {
        try Task.checkCancellation()
        stopInternal(publish: false)
        sourceURL = url
        self.retentionMinutes = min(15, max(0, retentionMinutes))
        shouldPlay = playbackRequested
        failed = false
        wantsInitialLivePosition = true
        connectionBegan = Date()
        hasStartedPlayback = false
        let activeGeneration = generation
        recordDiagnostic("start retention=\(self.retentionMinutes) requested=\(shouldPlay)")

        if self.retentionMinutes == 0 {
            let item = AVPlayerItem(url: url)
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
            let direct = AVPlayer(playerItem: item)
            direct.automaticallyWaitsToMinimizeStalling = true
            install(direct)
            if shouldPlay { direct.play() }
        } else {
            let directory = Self.bufferDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var excluded = URLResourceValues()
            excluded.isExcludedFromBackup = true
            var writableDirectory = directory
            try writableDirectory.setResourceValues(excluded)
            runDirectory = directory
            installBufferedPlayer()
            ingestTask = Task { [weak self] in
                do {
                    try await HLSIngestor().run(url: url, directory: directory, status: { [weak self] status in
                        guard let self, self.generation == activeGeneration else { return }
                        self.advertisedEdge = status.advertisedEdge
                        self.targetDuration = status.targetDuration
                        self.recordDiagnostic("manifest seq=\(status.mediaSequence) A=\(status.advertisedEdge?.timeIntervalSince1970 ?? 0) downloadedSeq=\(status.downloadedSequence ?? -1) encodedDelta=\(status.encodedDurationDelta ?? 0)")
                    }, diagnostic: { [weak self] event in
                        guard let self, self.generation == activeGeneration else { return }
                        self.recordDiagnostic(event)
                    }) { [weak self] segment in
                        guard let self, self.generation == activeGeneration else {
                            try? FileManager.default.removeItem(at: segment.url)
                            return
                        }
                        self.accept(segment)
                    }
                } catch is CancellationError {
                    // Explicit stop or a replacement stream owns cleanup.
                } catch {
                    guard let self, self.generation == activeGeneration, !Task.isCancelled else { return }
                    if let failure = error as? HLSAcquisitionFailure {
                        self.reportFailure(failure.underlying, origin: "hls.\(failure.stage) seq=\(failure.sequence.map(String.init) ?? "none")")
                    } else {
                        self.reportFailure(error, origin: "hls.acquisition")
                    }
                }
            }
        }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 1_000_000_000) }
                catch { return }
                guard let self, self.generation == activeGeneration else { return }
                self.tick()
            }
        }
        publish()
    }

    func play() {
        guard player != nil || bufferedPlayer != nil, !failed else { return }
        recordDiagnostic("engine.play")
        if !hasStartedPlayback { connectionBegan = Date() }
        shouldPlay = true
        if retentionMinutes == 0, directNeedsLiveReload, let url = sourceURL, let player {
            // At zero retention resume must not expose AVPlayer's old live buffer.
            let item = AVPlayerItem(url: url)
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
            player.replaceCurrentItem(with: item)
            observeCurrentItem()
            connectionBegan = Date()
            hasStartedPlayback = false
            directNeedsLiveReload = false
        } else if retentionMinutes > 0, !isSeeking {
            // A Live/seek action may already have installed its pending target
            // while paused. Resuming must not replace it with the old cursor.
            let cursor = pausedAt ?? heardDate()
            if wantsInitialLivePosition, let live = safeLiveTarget() {
                wantsInitialLivePosition = false
                reposition(to: live)
            } else if let cursor, let target = BufferRetention.seekTarget(cursor, result: retention) {
                if cursor < (retention.window?.oldest ?? cursor) || bufferedPlayer?.hasTimeline != true {
                    reposition(to: target)
                }
            }
        }
        pausedAt = nil
        if !isSeeking { player?.play() }
        // A pending paused seek still needs the latest intent; the renderer
        // defers its rate change until that seek has actually become ready.
        bufferedPlayer?.play()
        publish()
    }

    func pause() {
        recordDiagnostic("engine.pause")
        pausedAt = heardDate()
        shouldPlay = false
        if transportIsSeeking, cursor.position == nil { wantsInitialLivePosition = true }
        invalidatePendingSeek()
        if retentionMinutes == 0 { directNeedsLiveReload = true }
        player?.pause()
        bufferedPlayer?.pause()
        waitingSince = nil
        publish()
    }

    func stop() {
        switchTask?.cancel()
        switchTask = nil
        switchRequest = UUID()
        stopInternal(publish: true)
    }

    func seek(to date: Date) {
        guard retentionMinutes > 0, let live = safeLiveTarget(),
              let target = LivePlaybackClock.seekTarget(date, liveTarget: live, result: retention) else { return }
        wantsInitialLivePosition = false
        reposition(to: target)
    }

    func canSeek(to date: Date) -> Bool {
        guard retentionMinutes > 0, let live = safeLiveTarget(),
              let window = playableWindow(live: live), window.contains(date) else { return false }
        return segments.contains { date >= $0.start && date < $0.end }
    }

    func goLive() {
        guard player != nil || bufferedPlayer != nil else { return }
        if switchTask != nil {
            // The replacement already joins live. Until it runs, retentionMinutes
            // may describe the new mode while player still owns the old mode.
            // Never insert a direct HLS item into that outgoing buffered queue.
            wantsInitialLivePosition = true
            publish()
            return
        }
        if retentionMinutes > 0 {
            guard let live = safeLiveTarget() else {
                // Buffered startup has exactly one acquisition path. Keep its
                // initial join pending until retained media exists; inserting a
                // remote HLS item here would duplicate the stream and bypass the
                // segment-to-media-clock map used by the queue.
                wantsInitialLivePosition = true
                publish()
                return
            }
            wantsInitialLivePosition = false
            reposition(to: live)
        } else if let url = sourceURL, let player {
            wantsInitialLivePosition = false
            let item = AVPlayerItem(url: url)
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
            player.replaceCurrentItem(with: item)
            observeCurrentItem()
            connectionBegan = Date()
            hasStartedPlayback = false
            directNeedsLiveReload = false
            pausedAt = shouldPlay ? nil : cursor.position
            if shouldPlay { player.play() }
            publish()
        }
    }

    func setRetention(minutes: Int) {
        let next = min(15, max(0, minutes))
        guard next != retentionMinutes else { return }
        let requiresRestart = ((bufferedPlayer != nil) != (next > 0)) || switchTask != nil
        retentionMinutes = next
        guard let url = sourceURL else { return }
        if requiresRestart {
            switchTask?.cancel()
            let request = UUID()
            switchRequest = request
            switchTask = Task { [weak self] in
                guard let self, self.switchRequest == request, !Task.isCancelled else { return }
                // Read intent when the replacement actually starts. Pause/Play
                // may have changed it after this switch task was enqueued.
                let wasPlaying = self.shouldPlay
                do {
                    try await self.start(url: url, retentionMinutes: next, playbackRequested: wasPlaying)
                } catch {
                    self.reportFailure(error, origin: "retention replacement")
                }
                if self.switchRequest == request { self.switchTask = nil }
            }
        } else {
            applyRetention()
            publish()
        }
    }

    private func install(_ newPlayer: AVPlayer) {
        player = newPlayer
        newPlayer.volume = outputVolume
        let activeGeneration = generation
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                                                         queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == activeGeneration else { return }
                self.publishClock()
            }
        }
        observations = [
            newPlayer.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in
                    guard let self, self.generation == activeGeneration else { return }
                    self.observeCurrentItem()
                    self.publish()
                }
            },
            newPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in
                    guard let self, self.generation == activeGeneration else { return }
                    self.publish()
                }
            }
        ]
        failedToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] note in
                let item = note.object as? AVPlayerItem
                let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                Task { @MainActor in
                    guard let self, self.generation == activeGeneration,
                          item === self.player?.currentItem else { return }
                    self.reportFailure(error ?? AudioStreamError.disconnected, origin: "player.failedToEnd")
                }
            }
        observeCurrentItem()
    }

    private func installBufferedPlayer(loadSamples: @escaping (URL) async throws -> BufferedAudioSamples = BufferedAudioSampleSource.load) {
        let buffered = BufferedAudioRenderer(loadSamples: loadSamples)
        bufferedPlayer = buffered
        buffered.volume = outputVolume
        let activeGeneration = generation
        buffered.onClock = { [weak self] in
            guard let self, self.generation == activeGeneration else { return }
            self.publishClock()
        }
        buffered.onStateChange = { [weak self, weak buffered] in
            guard let self, self.generation == activeGeneration else { return }
            if self.isSeeking, buffered?.isSeeking == false {
                // Retention/output cancellation can revoke a read before the
                // renderer has a confirmed seek completion to deliver.
                self.seekGeneration.invalidate()
                self.isSeeking = false
                self.seekTargetDate = nil
                if self.cursor.position == nil { self.wantsInitialLivePosition = true }
            }
            self.publish()
        }
        buffered.onDiagnostic = { [weak self] event in
            guard let self, self.generation == activeGeneration else { return }
            self.recordDiagnostic(event)
        }
        buffered.onFailure = { [weak self] error in
            guard let self, self.generation == activeGeneration else { return }
            self.reportFailure(error, origin: "renderer.compressedAudio")
        }
    }

    private func observeCurrentItem() {
        itemObservation = nil
        guard let item = player?.currentItem else { return }
        let activeGeneration = generation
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, self.generation == activeGeneration, item === self.player?.currentItem else { return }
                if item.status == .failed {
                    self.reportFailure(item.error ?? AudioStreamError.disconnected, origin: "player.itemStatusFailed")
                } else {
                    self.publish()
                }
            }
        }
    }

    private func accept(_ segment: AudioSegment) {
        guard !failed else {
            try? FileManager.default.removeItem(at: segment.url)
            return
        }
        segments.append(segment)
        recordDiagnostic("accepted start=\(segment.start.timeIntervalSince1970) end=\(segment.end.timeIntervalSince1970) bytes=\(segment.byteCount) discontinuity=\(segment.discontinuity)")
        lastAcquisitionUptime = ProcessInfo.processInfo.systemUptime
        applyRetention()
        if wantsInitialLivePosition {
            // Acquire both startup segments before starting once. Rebuilding an
            // already audible first item on the second arrival caused a skip.
            if segments.count >= 2, let live = safeLiveTarget() {
                wantsInitialLivePosition = false
                reposition(to: live)
            }
        } else {
            fillBufferedAudio()
        }
        publish()
    }

    private func applyRetention() {
        guard let newest = segments.last else { return }
        let cursor = heardDate()
        retention = BufferRetention.trim(segments, live: newest.end, minutes: retentionMinutes)
        segments = retention.retained
        if let pending = seekTargetDate, let oldest = retention.window?.oldest, pending < oldest {
            invalidatePendingSeek()
        }
        bufferedPlayer?.updateSegments(segments)
        if shouldPlay, let cursor, let oldest = retention.window?.oldest, cursor < oldest {
            reposition(to: oldest)
        }
        for segment in retention.expired { try? FileManager.default.removeItem(at: segment.url) }
    }

    private func reposition(to requested: Date) {
        guard let buffered = bufferedPlayer,
              let window = retention.window,
              let target = BufferRetention.seekTarget(requested, result: retention),
              let segment = segments.first(where: { target >= $0.start && target < $0.end }) else { return }
        let targetDate = min(target, segment.end.addingTimeInterval(-0.05))
        let token = seekGeneration.begin()
        isSeeking = true
        seekTargetDate = window.clamped(targetDate)
        recordDiagnostic("seek requested=\(requested.timeIntervalSince1970) resolved=\(targetDate.timeIntervalSince1970) seekGeneration=\(token)")
        buffered.updateSegments(segments)
        buffered.seek(to: targetDate, playing: shouldPlay) { [weak self] confirmed in
            guard let self, self.seekGeneration.accepts(token), self.bufferedPlayer === buffered else { return }
            self.seekGeneration.invalidate()
            self.cursor.record(confirmed, confirmingSeek: true)
            if !self.shouldPlay { self.pausedAt = confirmed }
            self.recordDiagnostic("seek confirmed P=\(confirmed.timeIntervalSince1970) seekGeneration=\(token)")
            self.isSeeking = false
            self.seekTargetDate = nil
            self.publish()
        }
        publish()
    }

    private func fillBufferedAudio() {
        guard !failed, let buffered = bufferedPlayer else { return }
        buffered.updateSegments(segments)
        guard !buffered.hasTimeline, !isSeeking, !wantsInitialLivePosition,
              let requested = pausedAt ?? cursor.position,
              let target = BufferRetention.seekTarget(requested, result: retention),
              segments.contains(where: { target >= $0.start && target < $0.end }) else { return }
        reposition(to: target)
    }

    private func heardDate() -> Date? {
        if transportIsSeeking { return cursor.position }
        if !shouldPlay { return pausedAt ?? cursor.position }
        if let bufferedPlayer {
            cursor.record(bufferedPlayer.position)
        } else if let item = player?.currentItem, item.status == .readyToPlay {
            cursor.record(item.currentDate())
        }
        return cursor.position
    }

    private func invalidatePendingSeek() {
        seekGeneration.invalidate()
        player?.currentItem?.cancelPendingSeeks()
        bufferedPlayer?.cancelPendingSeek()
        isSeeking = false
        seekTargetDate = nil
    }

    private func safeLiveTarget() -> Date? {
        // Do not anchor to the first startup file: the initial join is selected
        // only after both files exist and the observed cadence can be covered.
        guard !wantsInitialLivePosition || segments.count >= 2 else { return nil }
        return liveClock.target(in: retention, uptime: ProcessInfo.processInfo.systemUptime)
    }

    private var acquisitionIsStale: Bool {
        guard retentionMinutes > 0 else { return false }
        let age = lastAcquisitionUptime.map { ProcessInfo.processInfo.systemUptime - $0 } ?? 0
        let backlog = advertisedEdge.flatMap { advertised in segments.last.map { advertised.timeIntervalSince($0.end) } } ?? 0
        return age > max(12, targetDuration * 1.5) || backlog > max(2, targetDuration)
    }

    private func playableWindow(live: Date?) -> BufferWindow? {
        guard let raw = retention.window, let live else { return nil }
        return BufferWindow(oldest: raw.oldest, live: max(raw.oldest, live))
    }

    private var transportIsPlaying: Bool {
        bufferedPlayer?.isPlaying ?? (player?.timeControlStatus == .playing)
    }
    private var transportIsSeeking: Bool { isSeeking || bufferedPlayer?.isSeeking == true }
    private var transportIsReady: Bool {
        bufferedPlayer?.isReady ?? (player?.currentItem?.status == .readyToPlay)
    }
    private var transportHasAudio: Bool {
        bufferedPlayer?.hasAudio ?? (player?.currentItem != nil)
    }

    private func publishClock() {
        let heard = heardDate()
        let live = safeLiveTarget()
        let advancing = shouldPlay && !transportIsSeeking && transportIsPlaying && heard != nil
        let atLive = !acquisitionIsStale && (retentionMinutes == 0 ||
            (heard.flatMap { position in live.map { LivePlaybackClock.isAtLive(heardAt: position, liveTarget: $0, acquisitionIsStale: false) } } ?? false))
        let window = playableWindow(live: live)
        let ranges: [ClosedRange<Date>] = segments.compactMap { segment in
            guard let window else { return nil }
            let lower = max(window.oldest, segment.start)
            let upper = min(window.live, segment.end)
            return lower <= upper ? lower...upper : nil
        }
        transportClock.update(.init(heardAt: heard, window: window,
                                    sampledAt: ProcessInfo.processInfo.systemUptime,
                                    isAdvancing: advancing, isAtLiveEdge: atLive,
                                    isSeeking: transportIsSeeking, pendingSeekAt: seekTargetDate ?? bufferedPlayer?.pendingSeekAt,
                                    playableRanges: ranges))
    }

    private func tick() {
        // Retention is computed against the newest acquired station timestamp;
        // a stalled connection does not invent audio or extend the seek range.
        if transportIsPlaying { hasStartedPlayback = true }
        if shouldPlay, !hasStartedPlayback, Date().timeIntervalSince(connectionBegan) >= 45 {
            reportFailure(AudioStreamError.stalled, origin: "monitor.startup45s")
        }
        if shouldPlay, hasStartedPlayback, !transportIsSeeking, !transportIsPlaying {
            if waitingSince == nil { waitingSince = Date() }
            if let waitingSince, Date().timeIntervalSince(waitingSince) >= 12 {
                reportFailure(AudioStreamError.stalled, origin: "monitor.playbackStall12s")
            }
        } else {
            waitingSince = nil
        }
        if shouldPlay, let cursor = heardDate(), let oldest = retention.window?.oldest, cursor < oldest {
            reposition(to: oldest)
        }
        publish()
    }

    private func publish() {
        if transportIsPlaying { hasStartedPlayback = true }
        publishClock()
        let sample = transportClock.sample
        let live = sample.window?.live ?? sample.heardAt ?? Date()
        let playing = shouldPlay && !transportIsSeeking && transportIsPlaying
        let downloaded = segments.last?.end
        let lag = advertisedEdge.flatMap { advertised in downloaded.map { max(0, advertised.timeIntervalSince($0)) } }
        onUpdate?(EngineSnapshot(isPlaying: playing,
                                 heardAt: sample.heardAt ?? live, window: sample.window,
                                 isReady: transportIsReady,
                                 live: live, hasAudio: transportHasAudio,
                                 isAtLiveEdge: sample.isAtLiveEdge,
                                 playbackRequested: shouldPlay, isWaiting: shouldPlay && !playing && !transportIsSeeking,
                                 isSeeking: transportIsSeeking, pendingSeekAt: sample.pendingSeekAt,
                                 hasConfirmedPosition: sample.heardAt != nil,
                                 downloadedEdge: downloaded, advertisedEdge: advertisedEdge,
                                 acquisitionLag: lag, acquisitionIsStale: acquisitionIsStale,
                                 sampledAt: sample.sampledAt))
        if sample.sampledAt - lastSlowPublishUptime >= 1 {
            lastSlowPublishUptime = sample.sampledAt
            recordDiagnosticSnapshot()
            let count = bufferedPlayer?.queueCount ?? (player?.currentItem == nil ? 0 : 1)
            recordDiagnostic("sample A=\(advertisedEdge?.timeIntervalSince1970 ?? 0) D=\(downloaded?.timeIntervalSince1970 ?? 0) L=\(live.timeIntervalSince1970) O=\(sample.window?.oldest.timeIntervalSince1970 ?? 0) P=\(sample.heardAt?.timeIntervalSince1970 ?? 0) playing=\(playing) seek=\(isSeeking) stale=\(acquisitionIsStale) queue=\(count) gain=\(outputVolume)")
        }
    }

    private func recordDiagnostic(_ event: String) {
        diagnostics.record("generation=\(generation.uuidString.prefix(8)) \(event)")
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-KUSCAudioDiagnostics") else { return }
        let line = "\(ProcessInfo.processInfo.systemUptime) session=\(generation) \(event)"
        diagnosticEvents.append(line)
        if diagnosticEvents.count > 256 { diagnosticEvents.removeFirst(diagnosticEvents.count - 256) }
        print("[KUSC audio] \(line)")
        #endif
    }

    private func diagnosticSnapshot() -> String {
        let now = ProcessInfo.processInfo.systemUptime
        let item = player?.currentItem
        let itemCount = bufferedPlayer?.queueCount ?? (item == nil ? 0 : 1)
        let last = segments.last?.end
        let live = transportClock.sample.window?.live
        let oldest = retention.window?.oldest
        let history = live.flatMap { target in oldest.map { target.timeIntervalSince($0) } }
        let queue = bufferedPlayer?.queueStarts.map { $0.timeIntervalSince1970.description }.joined(separator: ",") ?? "direct"
        return "snapshot requested=\(shouldPlay) retention=\(retentionMinutes) backend=\(bufferedPlayer == nil ? "direct" : "continuous") playing=\(transportIsPlaying) ready=\(transportIsReady) waiting=\(player?.reasonForWaitingToPlay?.rawValue ?? "none") seek=\(transportIsSeeking) retained=\(segments.count) queueCount=\(itemCount) queueFirst3=[\(queue)] A=\(advertisedEdge?.timeIntervalSince1970 ?? -1) D=\(last?.timeIntervalSince1970 ?? -1) L=\(live?.timeIntervalSince1970 ?? -1) O=\(oldest?.timeIntervalSince1970 ?? -1) P=\(transportClock.sample.heardAt?.timeIntervalSince1970 ?? -1) itemSeconds=\(bufferedPlayer?.currentSeconds ?? item?.currentTime().seconds ?? -1) history=\(history ?? -1) acquisitionAge=\(lastAcquisitionUptime.map { now - $0 } ?? -1) gain=\(outputVolume)"
    }

    private func reportFailure(_ error: Error, origin: String) {
        guard !failed else { return }
        recordDiagnosticSnapshot()
        if let entry = player?.currentItem?.errorLog()?.events.last {
            recordDiagnostic("player errorLog domain=\(entry.errorDomain) code=\(entry.errorStatusCode) comment=\(entry.errorComment ?? "none")")
        }
        diagnostics.captureFailure(error, origin: origin)
        failed = true
        ingestTask?.cancel()
        ingestTask = nil
        invalidatePendingSeek()
        player?.pause()
        bufferedPlayer?.pause()
        publish()
        onFailure?(error)
    }

    private func stopInternal(publish shouldPublish: Bool) {
        generation = UUID()
        seekGeneration.invalidate()
        ingestTask?.cancel()
        ingestTask = nil
        monitorTask?.cancel()
        monitorTask = nil
        observations.removeAll()
        itemObservation = nil
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let failedToEndObserver { NotificationCenter.default.removeObserver(failedToEndObserver) }
        failedToEndObserver = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        bufferedPlayer?.stop()
        bufferedPlayer = nil
        sourceURL = nil
        segments.removeAll()
        retention = RetentionResult(retained: [], expired: [], window: nil)
        pausedAt = nil
        shouldPlay = false
        isSeeking = false
        seekTargetDate = nil
        cursor = ConfirmedPlaybackCursor()
        liveClock = LivePlaybackClock()
        advertisedEdge = nil
        lastAcquisitionUptime = nil
        directNeedsLiveReload = false
        waitingSince = nil
        failed = false
        if let runDirectory { try? FileManager.default.removeItem(at: runDirectory) }
        runDirectory = nil
        if shouldPublish { publish() }
    }
}
