import UIKit
import WidgetKit

@MainActor final class HomeWidgetCoordinator {
    private lazy var store = WidgetSnapshotStore.shared
    private var lastSnapshot: WidgetPlaybackSnapshot?
    private var lastArtwork: UIImage?
    private var thumbnail: Data?

    func update(item: ProgrammeItem?, programme: String?, host: String?, artwork: UIImage?, requested: Bool) {
        guard let store else { return }
        if lastArtwork !== artwork {
            lastArtwork = artwork
            thumbnail = artwork.flatMap { image in
                guard image.size.width > 0, image.size.height > 0 else { return nil }
                let scale = min(1, 360 / max(image.size.width, image.size.height))
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
                return UIGraphicsImageRenderer(size: size, format: format).image { _ in
                    UIColor.black.setFill(); UIRectFill(CGRect(origin: .zero, size: size))
                    image.draw(in: CGRect(origin: .zero, size: size))
                }.jpegData(compressionQuality: 0.75)
            }
        }
        let snapshot = WidgetPlaybackSnapshot(playbackRequested: requested, item: item,
                                              programme: programme, host: host, artwork: thumbnail)
        // Publish on content changes and keep a short lease alive during audio.
        // This bounds a stale Pause button after the process is force-quit.
        if let last = lastSnapshot, snapshot.hasSameContent(as: last),
           !requested || snapshot.updatedAt.timeIntervalSince(last.updatedAt) < 30 { return }
        do {
            try store.write(snapshot)
            lastSnapshot = snapshot
            for kind in HomeWidgetLayout.allCases { WidgetCenter.shared.reloadTimelines(ofKind: kind.rawValue) }
        } catch {
            // A widget storage failure must never prevent a transport command.
            NSLog("KUSC widget snapshot unavailable: %@", error.localizedDescription)
        }
    }
}
