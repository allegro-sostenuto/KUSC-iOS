import ActivityKit
import WidgetKit
import AppIntents
import SwiftUI
import UIKit

@main struct KUSCLiveActivityBundle: WidgetBundle {
    var body: some Widget { KUSCLiveActivity() }
}
struct KUSCLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KUSCActivityAttributes.self) { context in
            HStack(spacing: 12) {
                ActivityArtwork(data: context.state.artwork).frame(width: 54, height: 54)
                VStack(alignment: .leading) {
                    Text(context.state.title).font(.headline).lineLimit(2)
                    Text(context.state.composer).font(.subheadline).lineLimit(1)
                    HStack {
                        Button(intent: ToggleKUSCPlaybackIntent()) { Image(systemName: context.state.playing ? "pause.fill" : "play.fill") }
                        Button("Live", intent: GoLiveIntent())
                    }.buttonStyle(.bordered)
                }
            }.padding().activityBackgroundTint(Color(.secondarySystemBackground))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityArtwork(data: context.state.artwork).frame(width: 56, height: 56)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading) {
                        Text(context.state.title).font(.headline).lineLimit(2)
                        Text(context.state.composer).font(.caption).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 28) {
                        Button(intent: ToggleKUSCPlaybackIntent()) {
                            Label(context.state.playing ? "Pause" : "Play", systemImage: context.state.playing ? "pause.fill" : "play.fill")
                        }
                        Button("Live", intent: GoLiveIntent())
                    }.buttonStyle(.bordered).tint(.white)
                }
            } compactLeading: {
                ActivityArtwork(data: context.state.artwork).frame(width: 28, height: 28)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                ActivityArtwork(data: context.state.artwork).frame(width: 24, height: 24)
            }
        }
    }
}
private struct ActivityArtwork: View {
    let data: Data?
    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: "music.note").resizable().scaledToFit().padding(5).foregroundStyle(.red).background(.white) }
        }.clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
