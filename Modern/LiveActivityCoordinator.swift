import ActivityKit
import UIKit

@MainActor final class LiveActivityCoordinator {
    private var activity: Activity<PhilharmonicActivityAttributes>?
    private var lastState: PhilharmonicActivityAttributes.ContentState?
    private var task: Task<Void, Never>?
    private var thumbnailSource: UIImage?
    private var cachedThumbnail: Data?

    init() {
        // Reuse one system activity after process death, without restoring any audio
        // cursor. Its content is replaced by this launch's live playback state.
        activity = Activity<PhilharmonicActivityAttributes>.activities.first
        for duplicate in Activity<PhilharmonicActivityAttributes>.activities.dropFirst() {
            Task { await duplicate.end(nil, dismissalPolicy: .immediate) }
        }
    }

    func update(item: ProgrammeItem?, artwork: UIImage?, playing: Bool, requested: Bool, status: String?, visible: Bool,
                station: RadioStation = StationCatalog.defaultStation) {
        guard visible else {
            guard let activity else { return }
            self.activity = nil; lastState = nil
            enqueue(always: true) { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        var state = PhilharmonicActivityAttributes.ContentState(title: String((item?.title ?? station.name).prefix(180)),
            composer: String((item?.composer ?? station.subtitle ?? "Live radio").prefix(100)),
            playing: playing, artwork: thumbnail(artwork), playbackRequested: requested, status: status,
            stationID: station.id, stationName: station.name)
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
            enqueue { await activity.update(content) }
        } else {
            // The OS may refuse a request made while backgrounded, or remove the activity
            // at its maximum lifetime. The next foreground/state change can request again.
            guard UIApplication.shared.applicationState == .active else { lastState = nil; return }
            do { activity = try Activity.request(attributes: PhilharmonicActivityAttributes(station: station.id), content: content, pushType: nil) }
            catch { lastState = nil }
        }
    }

    private func enqueue(always: Bool = false, _ operation: @escaping @MainActor () async -> Void) {
        // ActivityKit update may finish after cancellation. Serializing updates
        // ensures an old station can never overwrite a newer station's state.
        let preceding = task
        preceding?.cancel()
        task = Task {
            await preceding?.value
            guard always || !Task.isCancelled else { return }
            await operation()
        }
    }
    private func thumbnail(_ image: UIImage?) -> Data? {
        guard let image else {
            thumbnailSource = nil; cachedThumbnail = nil
            return nil
        }
        if thumbnailSource === image { return cachedThumbnail }
        thumbnailSource = image
        cachedThumbnail = nil
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format)
        let scaled = renderer.image { _ in image.draw(in: CGRect(x: 0, y: 0, width: 32, height: 32)) }
        guard let data = scaled.jpegData(compressionQuality: 0.35), data.count <= 1600 else { return nil }
        cachedThumbnail = data
        return data
    }
}
