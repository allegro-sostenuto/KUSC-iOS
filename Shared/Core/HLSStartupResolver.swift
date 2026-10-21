import Foundation

struct ResolvedHLSPlaylist {
    let url: URL
    let manifest: HLSManifest
}

/// A fresh Triton session can advertise an inserted promo before programme
/// audio. Keep that same session alive until its advertised window is clear.
/// Handing AVPlayer the master again would create another pre-roll session.
/// This runs only when connecting, never across an established broadcast.
enum HLSStartupResolver {
    static func resolve(
        _ url: URL,
        maximumWait: TimeInterval = 45,
        fetch: (URL) async throws -> (Data, URL),
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
        while manifest.segments.contains(where: \.isMarkedAdvertisement) {
            try Task.checkCancellation()
            guard !manifest.ended, ProcessInfo.processInfo.systemUptime - began < maximumWait else {
                throw AudioStreamError.unsupportedFormat("startup advertisement did not clear")
            }
            waitedForAdvertisement = true
            await diagnostic("startup promo withheld segments=\(manifest.segments.filter(\.isMarkedAdvertisement).count)")
            // Download no ad audio, and never request another master/session to
            // get past it. Polling lets the server advance its own live window.
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
