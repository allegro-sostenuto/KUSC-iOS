import Foundation

struct ResolvedHLSPlaylist {
    let url: URL
    let manifest: HLSManifest
}

/// A fresh Triton session can advertise an inserted promo before programme
/// audio. Advance that same session with programme-only reads until its window
/// is clear: Triton can pin the pre-roll until a media segment is requested.
/// Handing AVPlayer the master again would create another pre-roll session.
/// This runs only when connecting, never across an established broadcast.
enum HLSStartupResolver {
    static func resolve(
        _ url: URL,
        maximumWait: TimeInterval = 45,
        fetch: (URL) async throws -> (Data, URL),
        advance: (URL) async throws -> Void,
        wait: (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        },
        diagnostic: (String) async -> Void = { _ in }
    ) async throws -> ResolvedHLSPlaylist {
        let began = ProcessInfo.processInfo.systemUptime
        var mediaURL = url
        var initial: HLSManifest?
        for _ in 0..<4 {
            try Task.checkCancellation()
            let (data, responseURL) = try await fetch(mediaURL)
            let manifest = try HLSManifest.parse(data, baseURL: responseURL)
            if let variant = manifest.variants.max(by: { $0.bandwidth < $1.bandwidth }) {
                mediaURL = variant.url
            } else {
                mediaURL = responseURL
                initial = manifest
                break
            }
        }
        guard var manifest = initial else {
            throw AudioStreamError.unsupportedFormat("nested HLS playlists")
        }
        var waitedForAdvertisement = false
        var advancedSegments: Set<URL> = []
        while manifest.segments.contains(where: \.isMarkedAdvertisement) {
            try Task.checkCancellation()
            guard !manifest.ended, ProcessInfo.processInfo.systemUptime - began < maximumWait else {
                throw AudioStreamError.unsupportedFormat("startup advertisement did not clear")
            }
            waitedForAdvertisement = true
            await diagnostic("startup promo withheld segments=\(manifest.segments.filter(\.isMarkedAdvertisement).count)")
            // Fetch only a programme segment *after* the marked ad. A playlist
            // read alone does not advance Triton's per-listener media cursor.
            // These bounded bytes are discarded, never retained or played.
            if let programme = manifest.segments.last, !programme.isMarkedAdvertisement,
               advancedSegments.insert(programme.url).inserted {
                try await advance(programme.url)
                await diagnostic("startup advanced to programme seq=\(programme.sequence)")
            }
            // Never request another master/session, which could add a new ad.
            try await wait(min(2, manifest.targetDuration / 2))
            try Task.checkCancellation()
            let (data, responseURL) = try await fetch(mediaURL)
            let refreshed = try HLSManifest.parse(data, baseURL: responseURL, previous: manifest)
            guard refreshed.variants.isEmpty else {
                throw AudioStreamError.unsupportedFormat("media playlist became a master playlist")
            }
            mediaURL = responseURL
            manifest = refreshed
        }
        try Task.checkCancellation()
        if waitedForAdvertisement { await diagnostic("startup promo cleared; joining programme") }
        return ResolvedHLSPlaylist(url: mediaURL, manifest: manifest)
    }
}
