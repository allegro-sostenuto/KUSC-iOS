import ActivityKit
import Foundation

struct KUSCActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var composer: String
        var playing: Bool
        var artwork: Data?
        // Optional fields keep existing activities decodable across app updates.
        var playbackRequested: Bool? = nil
        var status: String? = nil
    }
    var station = "KUSC"
}
