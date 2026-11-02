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
    // Optional storage preserves settings.v1 on upgrade; unknown future values
    // also use Standard without discarding appearance or scheduled defaults.
    private var audioQualityPreference: String?
    var audioQuality: StationAudioQuality {
        get { audioQualityPreference.flatMap(StationAudioQuality.init(rawValue:)) ?? .standard }
        set { audioQualityPreference = newValue.rawValue }
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
