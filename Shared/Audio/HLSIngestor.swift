import Foundation

struct HLSAcquisitionStatus {
    let mediaSequence: Int64
    let advertisedEdge: Date?
    let targetDuration: TimeInterval
    var downloadedSequence: Int64? = nil
    var encodedDurationDelta: TimeInterval? = nil
}

struct HLSAcquisitionFailure: Error {
    let stage: String
    let sequence: Int64?
    let underlying: Error
}

/// One HLS audio downloader feeds both the local player and the retained history.
/// Its actor keeps parsing and disk writes off the UI actor. Each completed file is
/// acknowledged by the player before another is fetched, bounding pending work.
actor HLSIngestor {
    func run(url: URL, directory: URL,
             status: @escaping @MainActor (HLSAcquisitionStatus) -> Void,
             diagnostic: @escaping @MainActor (String) -> Void,
             receive: @escaping @MainActor (AudioSegment) -> Void) async throws {
        var stage = "initialPlaylist"
        var activeSequence: Int64?
        do {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 35
            configuration.httpMaximumConnectionsPerHost = 2
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }

            var mediaURL = url
            var initialManifest: HLSManifest?
            for _ in 0..<4 {
                let (data, responseURL) = try await fetch(mediaURL, session: session, maximumSize: 1024 * 1024, diagnostic: diagnostic)
                stage = "parseInitialPlaylist"
                let manifest = try HLSManifest.parse(data, baseURL: responseURL)
                if let highest = manifest.variants.max(by: { $0.bandwidth < $1.bandwidth }) {
                    mediaURL = highest.url
                    stage = "variantPlaylist"
                } else {
                    mediaURL = responseURL
                    initialManifest = manifest
                    break
                }
            }
            guard var manifest = initialManifest else {
                throw AudioStreamError.unsupportedFormat("nested HLS playlists")
            }
            var lastSequence: Int64?
            var lastEnd: Date?
            var lastNewAudio = Date()
            while !Task.isCancelled {
                let iterationUptime = ProcessInfo.processInfo.systemUptime
                await diagnostic("manifest first=\(manifest.segments.first?.sequence ?? -1) last=\(manifest.segments.last?.sequence ?? -1) count=\(manifest.segments.count) undated=\(manifest.segments.filter { $0.start == nil }.count) discontinuities=\(manifest.segments.filter(\.discontinuity).count) targetDuration=\(manifest.targetDuration) ended=\(manifest.ended) previousSeq=\(lastSequence ?? -1)")
                await status(HLSAcquisitionStatus(mediaSequence: manifest.segments.first?.sequence ?? 0,
                                                 advertisedEdge: manifest.segments.last?.end,
                                                 targetDuration: manifest.targetDuration))
                // Join close to the station's live edge. Do not download its complete
                // server window merely to start playback. Older history accumulates
                // from this point onward, according to the selected retention.
                let incoming: [HLSMediaSegment]
                if let lastSequence {
                    incoming = manifest.segments.filter { $0.sequence > lastSequence }
                } else {
                    incoming = Array(manifest.segments.suffix(2))
                }
                for remote in incoming {
                    try Task.checkCancellation()
                    activeSequence = remote.sequence
                    stage = "segmentClock"
                    await diagnostic("segment seq=\(remote.sequence) start=\(remote.start?.timeIntervalSince1970 ?? -1) duration=\(remote.duration) previousEnd=\(lastEnd?.timeIntervalSince1970 ?? -1) clockDelta=\(remote.start.flatMap { start in lastEnd.map { start.timeIntervalSince($0) } } ?? 0) discontinuity=\(remote.discontinuity)")
                    guard let start = remote.start else {
                        throw AudioStreamError.unsupportedFormat("HLS lacks PROGRAM-DATE-TIME")
                    }
                    if let lastEnd, start.timeIntervalSince(lastEnd) < -0.25 {
                        throw AudioStreamError.unsupportedFormat("HLS clock moved backwards")
                    }
                    stage = "segmentDownload"
                    let (bytes, _) = try await fetch(remote.url, session: session, maximumSize: 2 * 1024 * 1024, diagnostic: diagnostic)
                    stage = "parseAAC"
                    var parser = ADTSParser()
                    let frames = try parser.append(bytes)
                    await diagnostic("aac seq=\(remote.sequence) bytes=\(bytes.count) frames=\(frames.count)")
                    guard !frames.isEmpty else { throw AudioStreamError.invalidAAC }
                    let encodedDuration = frames.reduce(0) { $0 + $1.duration }
                    stage = "validateAACDuration"
                    await diagnostic("duration seq=\(remote.sequence) encoded=\(encodedDuration) manifest=\(remote.duration) delta=\(encodedDuration - remote.duration) tolerance=\(max(0.2, remote.duration * 0.01))")
                    guard abs(encodedDuration - remote.duration) <= max(0.2, remote.duration * 0.01) else {
                        throw AudioStreamError.unsupportedFormat("AAC duration disagrees with the HLS clock")
                    }
                    await status(HLSAcquisitionStatus(mediaSequence: manifest.segments.first?.sequence ?? 0,
                                                     advertisedEdge: manifest.segments.last?.end,
                                                     targetDuration: manifest.targetDuration,
                                                     downloadedSequence: remote.sequence,
                                                     encodedDurationDelta: encodedDuration - remote.duration))
                    try Task.checkCancellation()
                    stage = "writeSegmentFile"
                    let local = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("aac")
                    try bytes.write(to: local, options: .atomic)
                    try FileManager.default.setAttributes(
                        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                        ofItemAtPath: local.path)
                    var excluded = URLResourceValues()
                    excluded.isExcludedFromBackup = true
                    var protectedURL = local
                    try protectedURL.setResourceValues(excluded)
                    let segment = AudioSegment(url: local, start: start,
                                               end: start.addingTimeInterval(remote.duration), byteCount: bytes.count,
                                               discontinuity: remote.discontinuity)
                    if Task.isCancelled {
                        try? FileManager.default.removeItem(at: local)
                        throw CancellationError()
                    }
                    stage = "acceptSegment"
                    let acknowledgementBegan = ProcessInfo.processInfo.systemUptime
                    await receive(segment)
                    await diagnostic("acknowledged seq=\(remote.sequence) elapsed=\(ProcessInfo.processInfo.systemUptime - acknowledgementBegan)")
                    lastSequence = remote.sequence
                    lastEnd = segment.end
                    lastNewAudio = Date()
                }
                activeSequence = nil
                stage = "playlistEnded"
                if manifest.ended { throw AudioStreamError.disconnected }
                stage = "noNewAudio"
                if Date().timeIntervalSince(lastNewAudio) > max(30, manifest.targetDuration * 3) {
                    throw AudioStreamError.stalled
                }
                // Download/acknowledgement time counts toward the poll interval.
                // A slow batch must fetch a fresh manifest immediately, not add
                // another five seconds to a growing acquisition backlog.
                let delay = AcquisitionPollPolicy.delay(targetDuration: manifest.targetDuration,
                                                       elapsed: ProcessInfo.processInfo.systemUptime - iterationUptime)
                if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                stage = "refreshPlaylist"
                let (data, responseURL) = try await fetch(mediaURL, session: session, maximumSize: 1024 * 1024, diagnostic: diagnostic)
                mediaURL = responseURL
                stage = "parseRefreshedPlaylist"
                // A sliding playlist may drop its only program-date tag along
                // with an old segment. Verified overlap retains that timeline.
                let refreshed = try HLSManifest.parse(data, baseURL: mediaURL, previous: manifest)
                let previousSegments = Dictionary(manifest.segments.map { ($0.sequence, $0) },
                                                  uniquingKeysWith: { first, _ in first })
                let overlap = refreshed.segments.filter { previousSegments[$0.sequence] != nil }
                let matchingOverlap = overlap.filter { segment in
                    guard let old = previousSegments[segment.sequence] else { return false }
                    return segment.url == old.url && segment.duration == old.duration &&
                        segment.discontinuitySequence == old.discontinuitySequence
                }
                await diagnostic("reload overlap=\(overlap.count) matchingOverlap=\(matchingOverlap.count) resolved=\(refreshed.segments.filter { $0.start != nil }.count)/\(refreshed.segments.count)")
                manifest = refreshed
                guard manifest.variants.isEmpty else {
                    throw AudioStreamError.unsupportedFormat("media playlist became a master playlist")
                }
                // A server-side HLS session reset requires a new connection. Keeping
                // the previous media-sequence would otherwise silently stall forever.
                if let newest = manifest.segments.last?.sequence, let lastSequence, newest < lastSequence {
                    stage = "mediaSequenceReset"
                    await diagnostic("sequence reset previous=\(lastSequence) newest=\(newest)")
                    throw AudioStreamError.disconnected
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw HLSAcquisitionFailure(stage: stage, sequence: activeSequence, underlying: error)
        }
    }

    private func fetch(_ url: URL, session: URLSession, maximumSize: Int,
                       diagnostic: @escaping @MainActor (String) -> Void) async throws -> (Data, URL) {
        let began = ProcessInfo.processInfo.systemUptime
        await diagnostic("request begin host=\(url.host ?? "unknown")")
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("KUSCPrivate/1.0", forHTTPHeaderField: "User-Agent")
        let (incoming, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw AudioStreamError.disconnected }
        await diagnostic("response HTTP=\(response.statusCode) expectedBytes=\(response.expectedContentLength) headerElapsed=\(ProcessInfo.processInfo.systemUptime - began)")
        guard (200..<300).contains(response.statusCode) else { throw AudioStreamError.httpStatus(response.statusCode) }
        guard response.expectedContentLength <= Int64(maximumSize) else { throw AudioStreamError.storageLimit }
        var data = Data()
        data.reserveCapacity(min(maximumSize, max(0, Int(response.expectedContentLength))))
        do {
            for try await byte in incoming {
                guard data.count < maximumSize else { throw AudioStreamError.storageLimit }
                data.append(byte)
            }
        } catch {
            await diagnostic("download interrupted bytes=\(data.count) elapsed=\(ProcessInfo.processInfo.systemUptime - began)")
            throw error
        }
        await diagnostic("download complete bytes=\(data.count) elapsed=\(ProcessInfo.processInfo.systemUptime - began)")
        return (data, response.url ?? url)
    }
}
