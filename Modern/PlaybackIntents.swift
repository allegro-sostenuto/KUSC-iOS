import AppIntents

struct TogglePhilharmonicPlaybackIntent: LiveActivityIntent, AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play or pause Philharmonic"
    @Parameter(title: "Station") var stationID: String?
    init() { stationID = nil }
    init(stationID: String?) { self.stationID = stationID }
    func perform() async throws -> some IntentResult {
        // AudioPlaybackIntent dispatches this intent to the app process. This source is
        // also compiled into the extension so WidgetKit can encode its identity.
        #if !WIDGET_EXTENSION
        await MainActor.run {
            AppModel.shared.handleStationPlaybackIntent(playing: nil, stationID: stationID)
        }
        #endif
        return .result()
    }
}
struct GoLiveIntent: LiveActivityIntent, AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Philharmonic Live"
    @Parameter(title: "Station") var stationID: String?
    init() { stationID = nil }
    init(stationID: String?) { self.stationID = stationID }
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await MainActor.run { AppModel.shared.handleStationLiveIntent(stationID: stationID) }
        #endif
        return .result()
    }
}
