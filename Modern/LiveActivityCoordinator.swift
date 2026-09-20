import ActivityKit
import UIKit

@MainActor final class LiveActivityCoordinator {
    private var activity: Activity<KUSCActivityAttributes>?
    private var lastState: KUSCActivityAttributes.ContentState?
    private var task: Task<Void, Never>?

    init() {
        // Reuse one system activity after process death, without restoring any audio
        // cursor. Its content is replaced by this launch's live playback state.
        activity = Activity<KUSCActivityAttributes>.activities.first
        for duplicate in Activity<KUSCActivityAttributes>.activities.dropFirst() {
            Task { await duplicate.end(nil, dismissalPolicy: .immediate) }
        }
    }

    func update(item: ProgrammeItem?, artwork: UIImage?, playing: Bool, visible: Bool) {
        guard visible else {
            guard let activity else { return }
            self.activity = nil; lastState = nil
            task?.cancel()
            task = Task { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        var state = KUSCActivityAttributes.ContentState(title: String((item?.title ?? "KUSC FM 91.5").prefix(180)),
            composer: String((item?.composer ?? "Classical California").prefix(100)),
            playing: playing, artwork: thumbnail(artwork))
        if let activity, activity.activityState == .dismissed { return }
        if let activity, activity.activityState == .ended { self.activity = nil; lastState = nil }
        if ((try? JSONEncoder().encode(state).count) ?? 4096) > 3500 {
            state.artwork = nil
            state.title = String(state.title.prefix(60)); state.composer = String(state.composer.prefix(40))
        }
        guard state != lastState else { return }
        lastState = state
        // JSON size stays below ActivityKit's 4 KB limit, including Base64 encoding.
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity, activity.activityState == .active || activity.activityState == .stale {
            task?.cancel()
            task = Task { await activity.update(content) }
        } else {
            // The OS may refuse a request made while backgrounded, or remove the activity
            // at its maximum lifetime. The next foreground/state change can request again.
            guard UIApplication.shared.applicationState == .active else { lastState = nil; return }
            do { activity = try Activity.request(attributes: KUSCActivityAttributes(), content: content, pushType: nil) }
            catch { lastState = nil }
        }
    }
    private func thumbnail(_ image: UIImage?) -> Data? {
        guard let image else { return nil }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format)
        let scaled = renderer.image { _ in image.draw(in: CGRect(x: 0, y: 0, width: 32, height: 32)) }
        guard let data = scaled.jpegData(compressionQuality: 0.35), data.count <= 1600 else { return nil }
        return data
    }
}
