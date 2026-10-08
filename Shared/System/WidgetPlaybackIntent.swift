import AppIntents
import Foundation

/// AudioPlaybackIntent executes in the containing app, including a cold launch.
/// Encode the action shown on the button; stale widgets must not invert intent.
@available(iOS 17.0, *)
struct SetKUSCWidgetPlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Set KUSC playback"
    static var isDiscoverable: Bool = false
    @Parameter(title: "Play") var playing: Bool

    init() { playing = true }
    init(playing: Bool) { self.playing = playing }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await MainActor.run { AppModel.shared.setPlaybackFromWidget(playing) }
        #endif
        return .result()
    }
}

enum WidgetPlaybackLink {
    static func url(playing: Bool) -> URL {
        let scheme = Bundle.main.object(forInfoDictionaryKey: "KUSCURLScheme") as? String ?? "kusc-modern"
        return URL(string: "\(scheme)://playback/\(playing ? "play" : "pause")")!
    }

    static func action(for url: URL, scheme: String) -> Bool? {
        guard url.scheme == scheme, url.host == "playback", url.query == nil, url.fragment == nil else { return nil }
        switch url.path {
        case "/play": return true
        case "/pause": return false
        default: return nil
        }
    }
}
