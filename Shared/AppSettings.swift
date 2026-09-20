import Foundation

struct AppSettings: Codable, Equatable {
    var autoplay = true
    var resumeWherePaused = false
    var retentionMinutes = 0
    var minimalist = false
    var appearance = "system"
    var lastSleepMinutes = 0

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: "settings.v1"),
              var value = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        value.retentionMinutes = min(15, max(0, value.retentionMinutes))
        value.lastSleepMinutes = min(720, max(0, value.lastSleepMinutes))
        return value
    }
    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "settings.v1") }
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
