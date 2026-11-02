import AppIntents
import Foundation

/// AudioPlaybackIntent executes in the containing app, including a cold launch.
/// Encode the action shown on the button; stale widgets must not invert intent.
@available(iOS 17.0, *)
struct SetPhilharmonicWidgetPlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Set Philharmonic playback"
    static var isDiscoverable: Bool = false
    @Parameter(title: "Play") var playing: Bool
    @Parameter(title: "Station") var stationID: String?

    init() { playing = true; stationID = nil }
    init(playing: Bool, stationID: String? = nil) { self.playing = playing; self.stationID = stationID }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await MainActor.run { AppModel.shared.handleStationPlaybackIntent(playing: playing, stationID: stationID) }
        #endif
        return .result()
    }
}

enum WidgetPlaybackLink {
    static func url(playing: Bool, stationID: String? = nil) -> URL {
        let scheme = Bundle.main.object(forInfoDictionaryKey: "PhilharmonicURLScheme") as? String ?? "kusc-modern"
        var components = URLComponents()
        components.scheme = scheme; components.host = "playback"
        components.path = playing ? "/play" : "/pause"
        if let stationID { components.queryItems = [.init(name: "station", value: stationID)] }
        return components.url!
    }

    static func action(for url: URL, scheme: String) -> Bool? {
        guard url.scheme == scheme, url.host == "playback", url.fragment == nil else { return nil }
        if url.query != nil {
            guard let queries = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                  queries.count == 1, queries[0].name == "station", queries[0].value?.isEmpty == false else { return nil }
        }
        switch url.path {
        case "/play": return true
        case "/pause": return false
        default: return nil
        }
    }

    static func stationID(for url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "station" }?.value
    }
}
