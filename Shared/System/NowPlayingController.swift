import MediaPlayer
import UIKit

@MainActor final class NowPlayingController {
    private var targets: [(MPRemoteCommand, Any)] = []
    private var previousItem: ProgrammeItem?
    private var previousArtwork: UIImage?
    private var previousPlaying: Bool?
    init(play: @escaping () -> Void, pause: @escaping () -> Void, toggle: @escaping () -> Void) {
        let c = MPRemoteCommandCenter.shared()
        for command in [c.previousTrackCommand, c.nextTrackCommand, c.skipBackwardCommand,
                        c.skipForwardCommand, c.seekBackwardCommand, c.seekForwardCommand,
                        c.changePlaybackPositionCommand, c.changePlaybackRateCommand,
                        c.ratingCommand, c.likeCommand, c.dislikeCommand, c.bookmarkCommand] {
            command.isEnabled = false
        }
        for (command, action) in [(c.playCommand, play), (c.pauseCommand, pause), (c.togglePlayPauseCommand, toggle)] {
            command.isEnabled = true
            let target = command.addTarget { _ in
                Task { @MainActor in action() }
                return .success
            }
            targets.append((command, target))
        }
    }
    func update(item: ProgrammeItem?, artwork: UIImage?, playing: Bool) {
        guard item != previousItem || artwork !== previousArtwork || playing != previousPlaying else { return }
        previousItem = item; previousArtwork = artwork; previousPlaying = playing
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item?.title ?? "KUSC FM 91.5",
            MPMediaItemPropertyArtist: item?.composer ?? "Classical California",
            MPMediaItemPropertyAlbumTitle: item?.performers ?? "",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if let artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
        }
        // No duration/elapsed fields: system scrubbing remains disabled even while locally delayed.
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
