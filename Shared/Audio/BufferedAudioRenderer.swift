import AVFoundation
import Foundation

/// One compressed-audio decoder and one timeline for the entire buffered session.
/// Download boundaries append packets; only explicit seeks, real discontinuities,
/// or output-route flushes reset the decoder. All mutable state is serialized on main.
@MainActor final class BufferedAudioRenderer {
    // AAC needs decoder context around a seek, not every packet since the
    // previous storage boundary. A short packet-aligned preroll prevents old
    // audio filling the paused renderer before it reaches the requested time.
    private static let seekPrerollSeconds: TimeInterval = 1
    var onStateChange: (() -> Void)?
    var onClock: (() -> Void)?
    var onFailure: ((Error) -> Void)?
    var onDiagnostic: ((String) -> Void)?

    private let renderer = AVSampleBufferAudioRenderer()
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private let loadSamples: (URL) async throws -> BufferedAudioSamples
    private var periodicObserver: Any?
    private var endObserver: Any?
    private var notifications: [NSObjectProtocol] = []
    private var statusObservation: NSKeyValueObservation?
    private var readinessObservation: NSKeyValueObservation?
    private var loadTask: Task<Void, Never>?
    private var loadingSegmentID: UUID?
    private var generation = UUID()
    private var retained: [AudioSegment] = []
    private var entries: [Entry] = []
    private var pendingBuffers: [CMSampleBuffer] = []
    private var pendingIndex = 0
    private var requestingData = false
    private var scheduledEnd = CMTime.zero
    private var requestedStart = CMTime.zero
    private var firstEnqueuedTime: CMTime?
    private var seekCompletion: ((Date) -> Void)?
    private var lastConfirmedPosition: Date?
    private var nextSegment: AudioSegment?
    private var lastLoadedSegment: AudioSegment?
    private var waitingBoundary: AudioSegment?
    private var format: CMFormatDescription?
    private var stopped = false
    private var failed = false
    private var lastPublishedPlaying = false
    private var decoderResetCount = 0
    private var appendedSegmentCount = 0

    private struct Entry {
        let segment: AudioSegment
        let start: CMTime
        let end: CMTime
    }

    private(set) var playbackRequested = false
    private(set) var isSeeking = false
    private(set) var pendingSeekAt: Date?
    var volume: Float {
        get { renderer.volume }
        set { renderer.volume = min(1, max(0, newValue)) }
    }
    var hasTimeline: Bool { lastLoadedSegment != nil || nextSegment != nil || isSeeking }
    var hasAudio: Bool { !entries.isEmpty }
    var isReady: Bool { hasAudio && !failed && !isSeeking }
    var queueCount: Int { entries.count }
    var queueStarts: [Date] { entries.prefix(3).map { $0.segment.start } }
    var currentSeconds: TimeInterval { synchronizer.currentTime().seconds }
    var isPlaying: Bool {
        playbackRequested && !isSeeking && !failed && CMTimebaseGetEffectiveRate(synchronizer.timebase) > 0 &&
            CMTimeCompare(synchronizer.currentTime(), scheduledEnd) < 0
    }
    var position: Date? {
        guard !isSeeking, !entries.isEmpty else { return lastConfirmedPosition }
        let time = minTime(synchronizer.currentTime(), scheduledEnd)
        guard time.isNumeric else { return lastConfirmedPosition }
        if let entry = entries.last(where: { CMTimeCompare(time, $0.start) >= 0 }) {
            let seconds = max(0, CMTimeSubtract(minTime(time, entry.end), entry.start).seconds)
            let date = min(entry.segment.end, entry.segment.start.addingTimeInterval(seconds))
            lastConfirmedPosition = date
        }
        return lastConfirmedPosition
    }

    init(loadSamples: @escaping (URL) async throws -> BufferedAudioSamples = BufferedAudioSampleSource.load) {
        self.loadSamples = loadSamples
        renderer.volume = 0 // Owner installs the composed gain before requesting playback.
        synchronizer.addRenderer(renderer)
        synchronizer.delaysRateChangeUntilHasSufficientMediaData = true
        periodicObserver = synchronizer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 44_100), queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.clockAdvanced() }
            }
        statusObservation = renderer.observe(\.status, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                if self.renderer.status == .failed {
                    self.fail(self.renderer.error ?? AudioStreamError.disconnected)
                } else { self.finishSeekIfReady() }
            }
        }
        readinessObservation = renderer.observe(\.hasSufficientMediaDataForReliablePlaybackStart,
                                                  options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                self.finishSeekIfReady()
                self.resumeIfPossible()
            }
        }
        for name in [Notification.Name.AVSampleBufferAudioRendererWasFlushedAutomatically,
                     .AVSampleBufferAudioRendererOutputConfigurationDidChange] {
            notifications.append(NotificationCenter.default.addObserver(forName: name, object: renderer,
                                                                         queue: .main) { [weak self] note in
                Task { @MainActor in
                    guard let self, !self.stopped, !self.failed else { return }
                    self.recoverOutputFlush(reason: note.name.rawValue)
                }
            })
        }
    }

    func updateSegments(_ segments: [AudioSegment]) {
        retained = segments
        if let loadingSegmentID, !segments.contains(where: { $0.id == loadingSegmentID }) {
            // Retention may expire a paused seek's file while its reader is
            // opening it. That obsolete read is cancellation, not stream failure.
            if isSeeking { cancelPendingSeek() }
            else {
                generation = UUID()
                loadTask?.cancel()
                loadTask = nil
                self.loadingSegmentID = nil
                if hasAudio { installEndObserver() }
            }
        }
        prunePlayedEntries()
        loadNextIfNeeded()
    }

    func seek(to date: Date, playing: Bool, completion: @escaping (Date) -> Void) {
        guard let index = retained.firstIndex(where: { date >= $0.start && date < $0.end }) else { return }
        let target = retained[index]
        // Read the preceding storage file only when the bounded AAC preroll
        // actually reaches across its boundary. append() selects whole packets.
        var first = target
        if index > 0, !target.discontinuity,
           date.timeIntervalSince(target.start) < Self.seekPrerollSeconds {
            let previous = retained[index - 1]
            if abs(target.start.timeIntervalSince(previous.end)) <= 0.25 { first = previous }
        }
        resetDecoder()
        stopped = false
        failed = false
        playbackRequested = playing
        isSeeking = true
        pendingSeekAt = date
        seekCompletion = completion
        nextSegment = first
        requestedStart = CMTime(seconds: max(0, date.timeIntervalSince(first.start)), preferredTimescale: 44_100)
        synchronizer.setRate(0, time: requestedStart)
        onDiagnostic?("renderer seek target=\(date.timeIntervalSince1970) preroll=\(first.start.timeIntervalSince1970)")
        loadNextIfNeeded()
        publishState()
    }

    func play() {
        guard !failed, !stopped else { return }
        playbackRequested = true
        loadNextIfNeeded()
        resumeIfPossible()
    }

    func pause() {
        _ = position
        playbackRequested = false
        synchronizer.rate = 0
        publishState()
    }

    func cancelPendingSeek() {
        guard isSeeking else { return }
        let previous = lastConfirmedPosition
        resetDecoder()
        lastConfirmedPosition = previous
        isSeeking = false
        pendingSeekAt = nil
        seekCompletion = nil
        publishState()
    }

    func stop() {
        stopped = true
        playbackRequested = false
        resetDecoder()
        statusObservation = nil
        readinessObservation = nil
        if let periodicObserver { synchronizer.removeTimeObserver(periodicObserver) }
        periodicObserver = nil
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        notifications.removeAll()
        retained.removeAll()
        lastConfirmedPosition = nil
        isSeeking = false
        pendingSeekAt = nil
        seekCompletion = nil
    }

    private func resetDecoder() {
        generation = UUID()
        loadTask?.cancel()
        loadTask = nil
        loadingSegmentID = nil
        synchronizer.rate = 0
        renderer.stopRequestingMediaData()
        requestingData = false
        if let endObserver { synchronizer.removeTimeObserver(endObserver) }
        endObserver = nil
        renderer.flush()
        decoderResetCount += 1
        entries.removeAll()
        pendingBuffers.removeAll()
        pendingIndex = 0
        scheduledEnd = .zero
        firstEnqueuedTime = nil
        nextSegment = nil
        lastLoadedSegment = nil
        waitingBoundary = nil
        format = nil
    }

    private func loadNextIfNeeded() {
        guard !stopped, !failed, loadTask == nil, pendingIndex >= pendingBuffers.count,
              entries.count < 4, waitingBoundary == nil else { return }
        let segment: AudioSegment
        if let nextSegment { segment = nextSegment }
        else if let last = lastLoadedSegment,
                let next = BufferQueuePolicy.followers(after: last, retained: retained,
                                                       alreadyQueued: [], limit: 1).first {
            if next.discontinuity || abs(next.start.timeIntervalSince(last.end)) > 0.25 {
                waitingBoundary = next
                handleExhaustion()
                return
            }
            segment = next
        } else { return }
        nextSegment = nil
        let request = generation
        let source = loadSamples
        loadingSegmentID = segment.id
        loadTask = Task { [weak self] in
            do {
                let samples = try await source(segment.url)
                try Task.checkCancellation()
                guard let self, self.generation == request, !self.stopped else { return }
                self.loadTask = nil
                self.loadingSegmentID = nil
                try self.append(samples, segment: segment)
            } catch is CancellationError {
                // The replacing seek/session owns all later state.
            } catch {
                guard let self, self.generation == request, !self.stopped else { return }
                self.loadTask = nil
                self.loadingSegmentID = nil
                self.fail(error)
            }
        }
    }

    private func append(_ samples: BufferedAudioSamples, segment: AudioSegment) throws {
        guard !samples.buffers.isEmpty, samples.duration.isNumeric, samples.duration.seconds > 0,
              abs(samples.duration.seconds - segment.end.timeIntervalSince(segment.start)) <=
                max(0.2, segment.end.timeIntervalSince(segment.start) * 0.01) else {
            throw AudioStreamError.unsupportedFormat("compressed audio duration disagrees with retained segment")
        }
        guard let nextFormat = CMSampleBufferGetFormatDescription(samples.buffers[0]) else {
            throw AudioStreamError.invalidAAC
        }
        if let format, !CMFormatDescriptionEqual(format, otherFormatDescription: nextFormat) {
            throw AudioStreamError.unsupportedFormat("AAC format changed without a discontinuity")
        }
        format = nextFormat
        let start = entries.last?.end ?? .zero
        let end = CMTimeAdd(start, samples.duration)
        entries.append(Entry(segment: segment, start: start, end: end))
        let packets: [CMSampleBuffer]
        if isSeeking {
            let preroll = CMTime(seconds: Self.seekPrerollSeconds, preferredTimescale: 44_100)
            let cutoff = CMTimeSubtract(CMTimeSubtract(requestedStart, start), preroll)
            packets = try BufferedAudioSampleSource.packets(samples.buffers, endingAfter: cutoff)
        } else {
            packets = samples.buffers
        }
        pendingBuffers = try packets.map { try BufferedAudioSampleSource.retimed($0, by: start) }
        pendingIndex = 0
        lastLoadedSegment = segment
        appendedSegmentCount += 1
        onDiagnostic?("renderer appended start=\(segment.start.timeIntervalSince1970) timeline=\(start.seconds)...\(end.seconds) batches=\(packets.count)/\(samples.buffers.count) resets=\(decoderResetCount)")
        requestMoreData()
    }

    private func requestMoreData() {
        guard !requestingData, !failed, !stopped else { return }
        requestingData = true
        renderer.requestMediaDataWhenReady(on: .main) { [weak self] in
            MainActor.assumeIsolated { self?.provideMediaData() }
        }
    }

    private func provideMediaData() {
        guard !failed, !stopped else { return }
        while renderer.isReadyForMoreMediaData, pendingIndex < pendingBuffers.count {
            let sample = pendingBuffers[pendingIndex]
            if firstEnqueuedTime == nil { firstEnqueuedTime = CMSampleBufferGetPresentationTimeStamp(sample) }
            renderer.enqueue(sample)
            scheduledEnd = CMTimeAdd(CMSampleBufferGetPresentationTimeStamp(sample), CMSampleBufferGetDuration(sample))
            pendingIndex += 1
        }
        if pendingIndex == pendingBuffers.count {
            renderer.stopRequestingMediaData()
            requestingData = false
            pendingBuffers.removeAll()
            pendingIndex = 0
            installEndObserver()
            loadNextIfNeeded()
        }
        finishSeekIfReady()
        resumeIfPossible()
    }

    private func finishSeekIfReady() {
        guard isSeeking, CMTimeCompare(scheduledEnd, requestedStart) > 0,
              renderer.hasSufficientMediaDataForReliablePlaybackStart,
              let target = pendingSeekAt else { return }
        isSeeking = false
        pendingSeekAt = nil
        lastConfirmedPosition = target
        let completion = seekCompletion
        seekCompletion = nil
        completion?(target)
        resumeIfPossible()
        publishState()
    }

    private func resumeIfPossible() {
        guard playbackRequested, !isSeeking, !failed, !stopped,
              CMTimeCompare(synchronizer.currentTime(), scheduledEnd) < 0 else { return }
        if synchronizer.rate == 0 { synchronizer.rate = 1 }
        publishStateIfNeeded()
    }

    private func installEndObserver() {
        if let endObserver { synchronizer.removeTimeObserver(endObserver) }
        let request = generation
        endObserver = synchronizer.addBoundaryTimeObserver(forTimes: [NSValue(time: scheduledEnd)], queue: .main) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == request else { return }
                self.handleExhaustion()
            }
        }
    }

    private func handleExhaustion() {
        guard !isSeeking, CMTimeCompare(synchronizer.currentTime(), scheduledEnd) >= 0 else { return }
        _ = position
        synchronizer.setRate(0, time: scheduledEnd)
        if let boundary = waitingBoundary {
            onDiagnostic?("renderer source boundary start=\(boundary.start.timeIntervalSince1970)")
            seek(to: boundary.start, playing: playbackRequested) { [weak self] _ in self?.publishState() }
        } else {
            prunePlayedEntries()
            loadNextIfNeeded()
            publishStateIfNeeded()
        }
    }

    private func prunePlayedEntries() {
        guard !isSeeking else { return }
        let time = synchronizer.currentTime()
        // Keep the last entry to map a fully consumed timeline while starved.
        while entries.count > 1, CMTimeCompare(time, entries[0].end) >= 0 { entries.removeFirst() }
    }

    private func clockAdvanced() {
        guard !stopped, !failed else { return }
        handleExhaustion()
        prunePlayedEntries()
        loadNextIfNeeded()
        _ = position
        publishStateIfNeeded()
        onClock?()
    }

    private func recoverOutputFlush(reason: String) {
        guard let date = pendingSeekAt ?? position,
              let target = BufferRetention.seekTarget(date, result: BufferRetention.trim(
                retained, live: retained.last?.end ?? date, minutes: BufferRetention.maximumMinutes)),
              retained.contains(where: { target >= $0.start && target < $0.end }) else { return }
        onDiagnostic?("renderer output recovery reason=\(reason) P=\(target.timeIntervalSince1970)")
        let completion = seekCompletion
        seek(to: target, playing: playbackRequested) { [weak self] date in
            completion?(date)
            self?.publishState()
        }
    }

    private func fail(_ error: Error) {
        guard !failed, !stopped else { return }
        failed = true
        synchronizer.rate = 0
        renderer.stopRequestingMediaData()
        requestingData = false
        loadTask?.cancel()
        loadTask = nil
        onFailure?(error)
    }

    private func publishStateIfNeeded() {
        let playing = isPlaying
        if playing != lastPublishedPlaying { publishState() }
    }

    private func publishState() {
        lastPublishedPlaying = isPlaying
        onStateChange?()
    }

    private func minTime(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
        CMTimeCompare(lhs, rhs) <= 0 ? lhs : rhs
    }

    #if DEBUG
    var statisticsForTesting: (resets: Int, segments: Int, requested: Bool, gain: Float) {
        (decoderResetCount, appendedSegmentCount, playbackRequested, renderer.volume)
    }
    var preparedMediaForTesting: (first: Double?, end: Double, pendingBatches: Int, ready: Bool) {
        (firstEnqueuedTime?.seconds, scheduledEnd.seconds,
         pendingBuffers.count - pendingIndex, renderer.hasSufficientMediaDataForReliablePlaybackStart)
    }
    func simulateOutputFlushForTesting() { recoverOutputFlush(reason: "test output flush") }
    #endif
}
