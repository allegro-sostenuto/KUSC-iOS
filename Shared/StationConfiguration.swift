import Foundation

/// Endpoints observed in the station's public player on 2026-09-19. See docs/endpoints.md.
/// These are the station's own services and its designated audio CDN, never a metadata proxy.
enum StationConfiguration {
    static let name = "KUSC"
    static let stationID = "KUSC"
    static let audioURL = URL(string: "https://playerservices.streamtheworld.com/api/livestream-redirect/KUSCAAC96.m3u8")!
    static let continuousAACURL = URL(string: "https://playerservices.streamtheworld.com/api/livestream-redirect/KUSCAAC96.aac")!
    static let audioPlaylistURL = URL(string: "https://playerservices.streamtheworld.com/pls/KUSCAAC96.pls")!
    static let websiteURL = URL(string: "https://www.classicalcalifornia.org")!
    static let metadataBaseURL = URL(string: "https://schedule.kusc.org/v3")!
    static let nowPlayingURL = metadataBaseURL.appendingPathComponent("songs/\(stationID)/now").appending(queryItems: [URLQueryItem(name: "includeImage", value: "true")])
    static let metadataRefreshInterval: TimeInterval = 30
    static let playlistRefreshInterval: TimeInterval = 60
    static let metadataRequestTimeout: TimeInterval = 15
    static let stationTimeZone = TimeZone(identifier: "America/Los_Angeles")!

    static func playlistURL(date: String) -> URL {
        metadataBaseURL.appendingPathComponent("combined/\(stationID)").appending(queryItems: [
            URLQueryItem(name: "date", value: date),
            URLQueryItem(name: "combinedFormat", value: "true"),
            URLQueryItem(name: "reversed", value: "true"),
            URLQueryItem(name: "env", value: "master")
        ])
    }

    static func programmeURL(date: String) -> URL {
        metadataBaseURL.appendingPathComponent("programs/\(stationID)/day").appending(queryItems: [
            URLQueryItem(name: "date", value: date), URLQueryItem(name: "env", value: "master")
        ])
    }
}
