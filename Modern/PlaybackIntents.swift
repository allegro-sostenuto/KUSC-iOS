import AppIntents

struct ToggleKUSCPlaybackIntent: LiveActivityIntent, AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play or pause KUSC"
    func perform() async throws -> some IntentResult {
        // AudioPlaybackIntent dispatches this intent to the app process. This source is
        // also compiled into the extension so WidgetKit can encode its identity.
        #if !WIDGET_EXTENSION
        await MainActor.run {
            let model = AppModel.shared
            if model.isPlaying { model.pauseRemote() } else { model.play() }
        }
        #endif
        return .result()
    }
}
struct GoLiveIntent: LiveActivityIntent, AudioPlaybackIntent {
    static var title: LocalizedStringResource = "KUSC Live"
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await MainActor.run { AppModel.shared.goLive() }
        #endif
        return .result()
    }
}
