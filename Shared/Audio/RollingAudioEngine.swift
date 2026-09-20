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

    var volume: Float {
        get { outputVolume }
        set {
            outputVolume = min(1, max(0, newValue))
            player?.volume = outputVolume
        }
    }

    private var player: AVPlayer?
    private var sourceURL: URL?
    private var retentionMinutes = 0
    private var segments: [AudioSegment] = []
    private var retention = RetentionResult(retained: [], expired: [], window: nil)
    private var queued: [ObjectIdentifier: AudioSegment] = [:]
    private var observations: [NSKeyValueObservation] = []
    private var timeObserver: Any?
    private var itemObservation: NSKeyValueObservation?
    private var lastCurrentItem: AVPlayerItem?
    private var failedToEndObserver: NSObjectProtocol?
    private var endObserver: NSObjectProtocol?
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
    private var lastEndedPosition: Date?
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
    /// Native XCTest fixture: exercise pending-seek ownership without fetching
    /// the station or requiring an AAC decoder to finish an asynchronous seek.
    func configureBufferedTransportForTesting(segments fixtures: [AudioSegment], pausedAt date: Date?,
                                              initialJoinPending: Bool = false) {
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
        install(AVQueuePlayer())
        publish()
    }
    func acceptBufferedSegmentForTesting(_ segment: AudioSegment) { accept(segment) }
    #endif

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
            let queue = AVQueuePlayer()
            queue.actionAtItemEnd = .advance
            queue.automaticallyWaitsToMinimizeStalling = false
            install(queue)
            ingestTask = Task { [weak self] in
                do {
                    try await HLSIngestor().run(url: url, directory: directory, status: { [weak self] status in
                        guard let self, self.generation == activeGeneration else { return }
                        self.advertisedEdge = status.advertisedEdge
                        self.targetDuration = status.targetDuration
                        self.recordDiagnostic("manifest seq=\(status.mediaSequence) A=\(status.advertisedEdge?.timeIntervalSince1970 ?? 0) downloadedSeq=\(status.downloadedSequence ?? -1) encodedDelta=\(status.encodedDurationDelta ?? 0)")
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
                    self.reportFailure(error)
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
        guard let player, !failed else { return }
        if !hasStartedPlayback { connectionBegan = Date() }
        shouldPlay = true
        if retentionMinutes == 0, directNeedsLiveReload, let url = sourceURL {
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
            if let cursor, let target = BufferRetention.seekTarget(cursor, result: retention) {
                if pausedAt != nil || cursor < (retention.window?.oldest ?? cursor) || player.currentItem == nil {
                    reposition(to: target)
                }
            }
        }
        pausedAt = nil
        if !isSeeking { player.play() }
        publish()
    }

    func pause() {
        pausedAt = heardDate()
        shouldPlay = false
        invalidatePendingSeek()
        if retentionMinutes == 0 { directNeedsLiveReload = true }
        player?.pause()
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
        guard let player else { return }
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
        } else if let url = sourceURL {
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
        let requiresRestart = ((player is AVQueuePlayer) != (next > 0)) || switchTask != nil
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
                    self.reportFailure(error)
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
                    self.pruneQueueMappings()
                    self.fillQueue()
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
                    self.reportFailure(error ?? AudioStreamError.disconnected)
                }
            }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
                let item = note.object as? AVPlayerItem
                Task { @MainActor in
                    guard let self, self.generation == activeGeneration else { return }
                    if let item, let segment = self.queued[ObjectIdentifier(item)], !self.isSeeking {
                        self.cursor.record(segment.end)
                        self.lastEndedPosition = segment.end
                        self.recordDiagnostic("item ended P=\(segment.end.timeIntervalSince1970)")
                    }
                    self.pruneQueueMappings()
                    self.fillQueue()
                    self.publish()
                }
            }
        observeCurrentItem()
    }

    private func observeCurrentItem() {
        itemObservation = nil
        if !isSeeking, retentionMinutes > 0, let previous = lastCurrentItem, previous !== player?.currentItem,
           let segment = queued[ObjectIdentifier(previous)] {
            // Our only non-seek queue transition is automatic advance-at-end.
            // Capture the consumed endpoint before mappings disappear; an end
            // notification can be delivered after the currentItem notification.
            lastEndedPosition = segment.end
            cursor.record(segment.end)
            recordDiagnostic("queue advanced P=\(segment.end.timeIntervalSince1970)")
        }
        lastCurrentItem = player?.currentItem
        guard let item = player?.currentItem else { return }
        let activeGeneration = generation
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, self.generation == activeGeneration, item === self.player?.currentItem else { return }
                if item.status == .failed {
                    self.reportFailure(item.error ?? AudioStreamError.disconnected)
                } else {
                    self.publish()
                }
            }
        }
    }

    private func accept(_ segment: AudioSegment) {
        segments.append(segment)
        lastAcquisitionUptime = ProcessInfo.processInfo.systemUptime
        applyRetention()
        if wantsInitialLivePosition {
            // Acquire both startup segments before starting once. Rebuilding an
            // already audible first item on the second arrival caused a skip.
            if segments.count >= 2, let live = safeLiveTarget() {
                wantsInitialLivePosition = false
                reposition(to: live)
            }
        } else if player?.currentItem == nil {
            // Resume exactly where the consumed queue ended, including a next
            // valid point after a real source gap; never replay the newest start.
            let requested = pausedAt ?? lastEndedPosition ?? cursor.position ?? segment.start
            if let target = BufferRetention.seekTarget(requested, result: retention), target < segment.end {
                reposition(to: target)
            }
        } else {
            fillQueue()
        }
        publish()
    }

    private func applyRetention() {
        guard let newest = segments.last else { return }
        let cursor = heardDate()
        retention = BufferRetention.trim(segments, live: newest.end, minutes: retentionMinutes)
        segments = retention.retained
        if shouldPlay, let cursor, let oldest = retention.window?.oldest, cursor < oldest {
            reposition(to: oldest)
        }
        for segment in retention.expired { try? FileManager.default.removeItem(at: segment.url) }
    }

    private func reposition(to requested: Date) {
        guard let queue = player as? AVQueuePlayer,
              let window = retention.window,
              let target = BufferRetention.seekTarget(requested, result: retention),
              let segment = segments.first(where: { target >= $0.start && target < $0.end }) else { return }
        let targetDate = min(target, segment.end.addingTimeInterval(-0.05))
        let offset = max(0, targetDate.timeIntervalSince(segment.start))
        let token = seekGeneration.begin()
        isSeeking = true
        seekTargetDate = window.clamped(targetDate)
        recordDiagnostic("seek requested=\(requested.timeIntervalSince1970) resolved=\(targetDate.timeIntervalSince1970) token=\(token)")
        queue.pause()
        queue.removeAllItems()
        queued.removeAll()
        let item = AVPlayerItem(url: segment.url)
        queued[ObjectIdentifier(item)] = segment
        queue.insert(item, after: nil)
        fillQueue()
        queue.seek(to: CMTime(seconds: offset, preferredTimescale: 44_100),
                   toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self, self.seekGeneration.accepts(token), self.player?.currentItem === item else { return }
                self.seekGeneration.invalidate()
                if finished {
                    let seconds = item.currentTime().seconds
                    if seconds.isFinite {
                        let confirmed = min(segment.end, segment.start.addingTimeInterval(max(0, seconds)))
                        self.cursor.record(confirmed, confirmingSeek: true)
                        self.lastEndedPosition = nil
                        if !self.shouldPlay { self.pausedAt = confirmed }
                        self.recordDiagnostic("seek confirmed P=\(confirmed.timeIntervalSince1970) token=\(token)")
                    }
                }
                self.isSeeking = false
                self.seekTargetDate = nil
                if finished, self.shouldPlay { self.player?.play() }
                self.publish()
            }
        }
        publish()
    }

    private func fillQueue() {
        guard let queue = player as? AVQueuePlayer, let tail = queue.items().last,
              let lastSegment = queued[ObjectIdentifier(tail)] else { return }
        var previous = tail
        let availableSlots = max(0, 4 - queue.items().count)
        for segment in segments.filter({ $0.start >= lastSegment.end.addingTimeInterval(-0.05) }).prefix(availableSlots) {
            // Never replay a segment already queued after a manifest refresh.
            guard !queued.values.contains(where: { $0.id == segment.id }) else { continue }
            let item = AVPlayerItem(url: segment.url)
            guard queue.canInsert(item, after: previous) else { break }
            queued[ObjectIdentifier(item)] = segment
            queue.insert(item, after: previous)
            previous = item
        }
        if shouldPlay, !isSeeking { queue.play() }
    }

    private func pruneQueueMappings() {
        guard let queue = player as? AVQueuePlayer else { return }
        let identifiers = Set(queue.items().map(ObjectIdentifier.init))
        queued = queued.filter { identifiers.contains($0.key) }
    }

    private func heardDate() -> Date? {
        guard let player else { return cursor.position }
        if isSeeking { return cursor.position }
        if !shouldPlay { return pausedAt ?? cursor.position }
        guard let item = player.currentItem, item.status == .readyToPlay else { return cursor.position }
        if retentionMinutes == 0 {
            cursor.record(item.currentDate())
            return cursor.position
        }
        guard let segment = queued[ObjectIdentifier(item)] else { return cursor.position }
        let seconds = item.currentTime().seconds
        guard seconds.isFinite else { return cursor.position }
        cursor.record(min(segment.end, segment.start.addingTimeInterval(max(0, seconds))))
        return cursor.position
    }

    private func invalidatePendingSeek() {
        seekGeneration.invalidate()
        player?.currentItem?.cancelPendingSeeks()
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

    private func publishClock() {
        let heard = heardDate()
        let live = safeLiveTarget()
        let advancing = shouldPlay && !isSeeking && player?.timeControlStatus == .playing && heard != nil
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
                                    isSeeking: isSeeking, pendingSeekAt: seekTargetDate,
                                    playableRanges: ranges))
    }

    private func tick() {
        // Retention is computed against the newest acquired station timestamp;
        // a stalled connection does not invent audio or extend the seek range.
        if player?.timeControlStatus == .playing { hasStartedPlayback = true }
        if shouldPlay, !hasStartedPlayback, Date().timeIntervalSince(connectionBegan) >= 45 {
            reportFailure(AudioStreamError.stalled)
        }
        if shouldPlay, hasStartedPlayback, !isSeeking, player?.timeControlStatus != .playing {
            if waitingSince == nil { waitingSince = Date() }
            if let waitingSince, Date().timeIntervalSince(waitingSince) >= 12 {
                reportFailure(AudioStreamError.stalled)
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
        if player?.timeControlStatus == .playing { hasStartedPlayback = true }
        publishClock()
        let sample = transportClock.sample
        let live = sample.window?.live ?? sample.heardAt ?? Date()
        let playing = shouldPlay && !isSeeking && player?.timeControlStatus == .playing
        let downloaded = segments.last?.end
        let lag = advertisedEdge.flatMap { advertised in downloaded.map { max(0, advertised.timeIntervalSince($0)) } }
        onUpdate?(EngineSnapshot(isPlaying: playing,
                                 heardAt: sample.heardAt ?? live, window: sample.window,
                                 isReady: player?.currentItem?.status == .readyToPlay,
                                 live: live, hasAudio: player?.currentItem != nil,
                                 isAtLiveEdge: sample.isAtLiveEdge,
                                 playbackRequested: shouldPlay, isWaiting: shouldPlay && !playing && !isSeeking,
                                 isSeeking: isSeeking, pendingSeekAt: seekTargetDate,
                                 hasConfirmedPosition: sample.heardAt != nil,
                                 downloadedEdge: downloaded, advertisedEdge: advertisedEdge,
                                 acquisitionLag: lag, acquisitionIsStale: acquisitionIsStale,
                                 sampledAt: sample.sampledAt))
        if sample.sampledAt - lastSlowPublishUptime >= 1 {
            lastSlowPublishUptime = sample.sampledAt
            let count = (player as? AVQueuePlayer)?.items().count ?? (player?.currentItem == nil ? 0 : 1)
            recordDiagnostic("sample A=\(advertisedEdge?.timeIntervalSince1970 ?? 0) D=\(downloaded?.timeIntervalSince1970 ?? 0) L=\(live.timeIntervalSince1970) O=\(sample.window?.oldest.timeIntervalSince1970 ?? 0) P=\(sample.heardAt?.timeIntervalSince1970 ?? 0) playing=\(playing) seek=\(isSeeking) stale=\(acquisitionIsStale) queue=\(count) gain=\(outputVolume)")
        }
    }

    private func recordDiagnostic(_ event: String) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-KUSCAudioDiagnostics") else { return }
        let line = "\(ProcessInfo.processInfo.systemUptime) session=\(generation) \(event)"
        diagnosticEvents.append(line)
        if diagnosticEvents.count > 256 { diagnosticEvents.removeFirst(diagnosticEvents.count - 256) }
        print("[KUSC audio] \(line)")
        #endif
    }

    private func reportFailure(_ error: Error) {
        guard !failed else { return }
        failed = true
        ingestTask?.cancel()
        ingestTask = nil
        invalidatePendingSeek()
        player?.pause()
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
        lastCurrentItem = nil
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let failedToEndObserver { NotificationCenter.default.removeObserver(failedToEndObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        failedToEndObserver = nil
        endObserver = nil
        player?.pause()
        if let queue = player as? AVQueuePlayer { queue.removeAllItems() }
        player?.replaceCurrentItem(with: nil)
        player = nil
        sourceURL = nil
        queued.removeAll()
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
        lastEndedPosition = nil
        directNeedsLiveReload = false
        waitingSince = nil
        failed = false
        if let runDirectory { try? FileManager.default.removeItem(at: runDirectory) }
        runDirectory = nil
        if shouldPublish { publish() }
    }
}
