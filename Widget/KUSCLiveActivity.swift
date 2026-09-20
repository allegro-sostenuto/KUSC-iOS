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
                        Button(intent: ToggleKUSCPlaybackIntent()) { Image(systemName: (context.state.playbackRequested ?? context.state.playing) ? "pause.fill" : "play.fill") }
                        Button("Live", intent: GoLiveIntent())
                    }.buttonStyle(ActivityControlStyle())
                    if let status = context.state.status { Text(status).font(.caption).foregroundStyle(.secondary) }
                }
            }.padding().activityBackgroundTint(Color(.systemBackground))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityArtwork(data: context.state.artwork).frame(width: 56, height: 56)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading) {
                        Text(context.state.title).font(.headline).lineLimit(2)
                        Text(context.state.composer).font(.caption).lineLimit(1)
                        if let status = context.state.status { Text(status).font(.caption2).lineLimit(1) }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 28) {
                        Button(intent: ToggleKUSCPlaybackIntent()) {
                            Label((context.state.playbackRequested ?? context.state.playing) ? "Pause" : "Play",
                                  systemImage: (context.state.playbackRequested ?? context.state.playing) ? "pause.fill" : "play.fill")
                        }
                        Button("Live", intent: GoLiveIntent())
                    }.buttonStyle(ActivityControlStyle()).tint(.white)
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
            else { Image(systemName: "music.note").resizable().scaledToFit().padding(5).foregroundStyle(.red).background(Color(.systemBackground)) }
        }.clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private struct ActivityControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 12).frame(minHeight: 44)
            .background(Color(.systemBackground), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.35), lineWidth: 0.75))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
