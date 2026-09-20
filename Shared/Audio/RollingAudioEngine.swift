import AVFoundation
import Foundation

struct EngineSnapshot {
    let isPlaying: Bool
    let heardAt: Date
    let window: BufferWindow?
    let isReady: Bool
    let live: Date
    let hasAudio: Bool
    /// HLS makes an entire segment available at once. The current last segment
    /// is its playable live edge, typically 4–10 seconds behind its end date.
    let isAtLiveEdge: Bool
}

/// Session ownership, interruption policy and retry deadlines belong to the
/// playback coordinator. This class owns exactly one audio player and one audio
/// acquisition path. A new generation invalidates every callback from its predecessor.
@MainActor
final class RollingAudioEngine {
    var onUpdate: ((EngineSnapshot) -> Void)?
    var onFailure: ((Error) -> Void)?

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
    private var itemObservation: NSKeyValueObservation?
    private var failedToEndObserver: NSObjectProtocol?
    private var endObserver: NSObjectProtocol?
    private var ingestTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var switchTask: Task<Void, Never>?
    private var switchRequest = UUID()
    private var generation = UUID()
    private var seekGeneration = UUID()
    private var shouldPlay = false
    private var outputVolume: Float = 1
    private var pausedAt: Date?
    private var waitingSince: Date?
    private var connectionBegan = Date()
    private var hasStartedPlayback = false
    private var isSeeking = false
    private var seekTargetDate: Date?
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

    func start(url: URL, retentionMinutes: Int) async throws {
        try Task.checkCancellation()
        stopInternal(publish: false)
        sourceURL = url
        self.retentionMinutes = min(15, max(0, retentionMinutes))
        shouldPlay = true
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
            direct.play()
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
                    try await HLSIngestor().run(url: url, directory: directory) { [weak self] segment in
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
        } else if retentionMinutes > 0 {
            let cursor = pausedAt ?? heardDate()
            if let cursor, let target = BufferRetention.seekTarget(cursor, result: retention) {
                if cursor < (retention.window?.oldest ?? cursor) || player.currentItem == nil {
                    reposition(to: target)
                }
            }
        }
        pausedAt = nil
        if !isSeeking { player.play() }
        publish()
    }

    func pause() {
        pausedAt = heardDate() ?? segments.last?.start ?? Date()
        shouldPlay = false
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
        guard retentionMinutes > 0, let target = BufferRetention.seekTarget(date, result: retention) else { return }
        wantsInitialLivePosition = false
        reposition(to: target)
    }

    func goLive() {
        guard let player else { return }
        wantsInitialLivePosition = false
        if retentionMinutes > 0, let newest = segments.last {
            reposition(to: max(retention.window?.oldest ?? newest.start, newest.start))
        } else if let url = sourceURL {
            let item = AVPlayerItem(url: url)
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
            player.replaceCurrentItem(with: item)
            observeCurrentItem()
            connectionBegan = Date()
            hasStartedPlayback = false
            directNeedsLiveReload = false
            pausedAt = shouldPlay ? nil : Date()
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
            let wasPlaying = shouldPlay
            switchTask?.cancel()
            let request = UUID()
            switchRequest = request
            switchTask = Task { [weak self] in
                guard let self, self.switchRequest == request, !Task.isCancelled else { return }
                do {
                    try await self.start(url: url, retentionMinutes: next)
                    if !wasPlaying { self.pause() }
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
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == activeGeneration else { return }
                    self.pruneQueueMappings()
                    self.fillQueue()
                }
            }
        observeCurrentItem()
    }

    private func observeCurrentItem() {
        itemObservation = nil
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
        applyRetention()
        if wantsInitialLivePosition {
            // The first two segments are startup prebuffer. A second downloaded
            // segment updates the live join point before normal playback settles.
            reposition(to: segment.start)
            if segments.count >= 2 { wantsInitialLivePosition = false }
        } else if player?.currentItem == nil {
            let target = pausedAt.flatMap { BufferRetention.seekTarget($0, result: retention) }
                ?? segment.start
            reposition(to: target)
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
              let segment = segments.first(where: { target >= $0.start && target < $0.end }) ?? segments.last else { return }
        let targetDate = min(target, segment.end.addingTimeInterval(-0.05))
        let offset = max(0, targetDate.timeIntervalSince(segment.start))
        let token = UUID()
        seekGeneration = token
        isSeeking = true
        seekTargetDate = window.clamped(targetDate)
        queue.pause()
        queue.removeAllItems()
        queued.removeAll()
        let item = AVPlayerItem(url: segment.url)
        queued[ObjectIdentifier(item)] = segment
        queue.insert(item, after: nil)
        fillQueue()
        pausedAt = shouldPlay ? nil : window.clamped(targetDate)
        queue.seek(to: CMTime(seconds: offset, preferredTimescale: 44_100),
                   toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self, self.seekGeneration == token else { return }
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
        guard let player else { return nil }
        if isSeeking, let seekTargetDate { return seekTargetDate }
        if !shouldPlay, let pausedAt { return pausedAt }
        guard let item = player.currentItem else { return nil }
        if retentionMinutes == 0 { return item.currentDate() ?? Date() }
        guard let segment = queued[ObjectIdentifier(item)] else { return nil }
        let seconds = item.currentTime().seconds
        guard seconds.isFinite else { return segment.start }
        return min(segment.end, segment.start.addingTimeInterval(max(0, seconds)))
    }

    private func tick() {
        // Retention is computed against the newest acquired station timestamp;
        // a stalled connection does not invent audio or extend the seek range.
        if player?.timeControlStatus == .playing { hasStartedPlayback = true }
        if shouldPlay, !hasStartedPlayback, Date().timeIntervalSince(connectionBegan) >= 45 {
            reportFailure(AudioStreamError.stalled)
        }
        if shouldPlay, hasStartedPlayback, player?.timeControlStatus == .waitingToPlayAtSpecifiedRate {
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
        let live = retentionMinutes > 0 ? (segments.last?.end ?? Date()) : Date()
        let rawHeard = heardDate() ?? segments.last?.start ?? live
        let heard = retention.window?.clamped(rawHeard) ?? rawHeard
        let atLive = retentionMinutes == 0 || heard >= (segments.last?.start ?? live).addingTimeInterval(-1)
        onUpdate?(EngineSnapshot(isPlaying: shouldPlay && player?.timeControlStatus == .playing,
                                 heardAt: heard, window: retention.window,
                                 isReady: player?.currentItem?.status == .readyToPlay,
                                 live: live, hasAudio: player?.currentItem != nil,
                                 isAtLiveEdge: atLive))
    }

    private func reportFailure(_ error: Error) {
        guard !failed else { return }
        failed = true
        ingestTask?.cancel()
        ingestTask = nil
        player?.pause()
        onFailure?(error)
    }

    private func stopInternal(publish shouldPublish: Bool) {
        generation = UUID()
        seekGeneration = UUID()
        ingestTask?.cancel()
        ingestTask = nil
        monitorTask?.cancel()
        monitorTask = nil
        observations.removeAll()
        itemObservation = nil
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
        directNeedsLiveReload = false
        waitingSince = nil
        failed = false
        if let runDirectory { try? FileManager.default.removeItem(at: runDirectory) }
        runDirectory = nil
        if shouldPublish { publish() }
    }
}
