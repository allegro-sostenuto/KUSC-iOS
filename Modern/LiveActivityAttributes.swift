import ActivityKit
import Foundation

struct KUSCActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var composer: String
        var playing: Bool
        var artwork: Data?
    }
    var station = "KUSC"
}
