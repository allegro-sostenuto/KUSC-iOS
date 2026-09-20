import Foundation

/// One HLS audio downloader feeds both the local player and the retained history.
/// Its actor keeps parsing and disk writes off the UI actor. Each completed file is
/// acknowledged by the player before another is fetched, bounding pending work.
actor HLSIngestor {
    func run(url: URL, directory: URL,
             receive: @escaping @MainActor (AudioSegment) -> Void) async throws {
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
            let (data, responseURL) = try await fetch(mediaURL, session: session, maximumSize: 1024 * 1024)
            let manifest = try HLSManifest.parse(data, baseURL: responseURL)
            if let highest = manifest.variants.max(by: { $0.bandwidth < $1.bandwidth }) {
                mediaURL = highest.url
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
                guard let start = remote.start else {
                    throw AudioStreamError.unsupportedFormat("HLS lacks PROGRAM-DATE-TIME")
                }
                if let lastEnd, start.timeIntervalSince(lastEnd) < -0.25 {
                    throw AudioStreamError.unsupportedFormat("HLS clock moved backwards")
                }
                let (bytes, _) = try await fetch(remote.url, session: session, maximumSize: 2 * 1024 * 1024)
                var parser = ADTSParser()
                let frames = try parser.append(bytes)
                guard !frames.isEmpty else { throw AudioStreamError.invalidAAC }
                let encodedDuration = frames.reduce(0) { $0 + $1.duration }
                guard abs(encodedDuration - remote.duration) <= max(0.2, remote.duration * 0.01) else {
                    throw AudioStreamError.unsupportedFormat("AAC duration disagrees with the HLS clock")
                }
                try Task.checkCancellation()
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
                                           end: start.addingTimeInterval(remote.duration), byteCount: bytes.count)
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: local)
                    throw CancellationError()
                }
                await receive(segment)
                lastSequence = remote.sequence
                lastEnd = segment.end
                lastNewAudio = Date()
            }
            if manifest.ended { throw AudioStreamError.disconnected }
            if Date().timeIntervalSince(lastNewAudio) > max(30, manifest.targetDuration * 3) {
                throw AudioStreamError.stalled
            }
            let delay = max(1, min(5, manifest.targetDuration / 2))
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            let (data, responseURL) = try await fetch(mediaURL, session: session, maximumSize: 1024 * 1024)
            mediaURL = responseURL
            manifest = try HLSManifest.parse(data, baseURL: mediaURL)
            guard manifest.variants.isEmpty else {
                throw AudioStreamError.unsupportedFormat("media playlist became a master playlist")
            }
            // A server-side HLS session reset requires a new connection. Keeping
            // the previous media-sequence would otherwise silently stall forever.
            if let newest = manifest.segments.last?.sequence, let lastSequence, newest < lastSequence {
                throw AudioStreamError.disconnected
            }
        }
    }

    private func fetch(_ url: URL, session: URLSession, maximumSize: Int) async throws -> (Data, URL) {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("KUSCPrivate/1.0", forHTTPHeaderField: "User-Agent")
        let (incoming, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw AudioStreamError.disconnected }
        guard (200..<300).contains(response.statusCode) else { throw AudioStreamError.httpStatus(response.statusCode) }
        guard response.expectedContentLength <= Int64(maximumSize) else { throw AudioStreamError.storageLimit }
        var data = Data()
        data.reserveCapacity(min(maximumSize, max(0, Int(response.expectedContentLength))))
        for try await byte in incoming {
            guard data.count < maximumSize else { throw AudioStreamError.storageLimit }
            data.append(byte)
        }
        return (data, response.url ?? url)
    }
}
