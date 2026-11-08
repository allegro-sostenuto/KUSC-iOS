import Foundation

struct AppSettings: Codable, Equatable {
    init() {}
    var autoplay = true
    // Time shifting is unavailable until a server-backed implementation exists.
    // Computed values also ignore (and omit on save) legacy Codable preferences.
    var resumeWherePaused: Bool { false }
    var retentionMinutes: Int { 0 }
    var minimalist = false
    var appearance = "system"
    var lastSleepMinutes = 0
    var scheduledStartDefaults: ScheduledStartOptions?
    var scheduledOutputDefault: ScheduledOutputPreference?
    private var stationMapAppearance: String?
    private var appliedAudioQualityPreset: String?
    var stationMapStyle: StationMapStyle {
        get { stationMapAppearance.flatMap(StationMapStyle.init(rawValue:)) ?? .satellite }
        set { stationMapAppearance = newValue.rawValue }
    }
    var audioQualityPreset: StationQualityPreset? {
        get { appliedAudioQualityPreset.flatMap(StationQualityPreset.init(rawValue:)) }
        set { appliedAudioQualityPreset = newValue?.rawValue }
    }
    // Optional storage preserves settings.v1 on upgrade. Unknown/retired source
    // IDs use that station's default without discarding unrelated preferences.
    private var stationAudioSources: [String: String]?
    func audioSource(for station: RadioStation) -> StationAudioSource {
        station.audioSources.first { $0.id == stationAudioSources?[station.id] } ?? station.defaultAudioSource
    }
    mutating func setAudioSource(_ sourceID: String, for station: RadioStation) {
        guard station.audioSources.contains(where: { $0.id == sourceID }) else { return }
        if stationAudioSources == nil { stationAudioSources = [:] }
        stationAudioSources?[station.id] = sourceID
    }

    static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        guard let data = defaults.data(forKey: "settings.v1"),
              var value = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        value.lastSleepMinutes = min(720, max(0, value.lastSleepMinutes))
        value.save(to: defaults)
        return value
    }
    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: "settings.v1") }
    }
}

enum PlaybackState: Equatable {
    case idle, connecting, playingLive, playingDelayed, pausedLive, pausedDelayed
    case reconnecting(since: Date), buffering, seeking, interrupted, fadingOut, scheduledStandby, scheduledSilent, scheduledFadeIn, stoppedBySleepTimer
    var active: Bool {
        switch self {
        case .connecting, .playingLive, .playingDelayed, .reconnecting, .buffering, .seeking, .interrupted,
             .fadingOut, .scheduledSilent, .scheduledFadeIn: return true
        default: return false
        }
    }
}
enum TimerPauseChoice { case keepCounting, pauseTimer, cancelTimer }
