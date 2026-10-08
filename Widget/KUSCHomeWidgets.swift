import SwiftUI
import WidgetKit

struct KUSCWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetPlaybackSnapshot
}

struct KUSCWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> KUSCWidgetEntry {
        .init(date: Date(), snapshot: .init(item: ProgrammeItem(id: "widget-preview", start: Date(),
            work: "Classical California", composer: "KUSC", performers: "Music for your day")))
    }
    func getSnapshot(in context: Context, completion: @escaping (KUSCWidgetEntry) -> Void) {
        completion(.init(date: Date(), snapshot: WidgetSnapshotStore.shared?.read() ?? .init()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<KUSCWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshotStore.shared?.read() ?? .init()
        var entries = [KUSCWidgetEntry(date: now, snapshot: snapshot)]
        let expires = snapshot.updatedAt.addingTimeInterval(WidgetPlaybackSnapshot.lifetime)
        if snapshot.playbackRequested && expires > now {
            entries.append(.init(date: expires, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(snapshot.requestingPlayback(at: now) ? 60 : 900))))
    }
}

struct KUSCPlaybackWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HomeWidgetLayout.playback.rawValue, provider: KUSCWidgetProvider()) {
            HomeWidgetView(snapshot: $0.snapshot, date: $0.date, layout: .playback)
                .widgetURL(WidgetPlaybackLink.url(playing: !$0.snapshot.requestingPlayback(at: $0.date)))
        }.configurationDisplayName("Play / Pause").description("Just one button for KUSC.")
            .supportedFamilies([.systemSmall])
    }
}
struct KUSCArtworkWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HomeWidgetLayout.artwork.rawValue, provider: KUSCWidgetProvider()) {
            HomeWidgetView(snapshot: $0.snapshot, date: $0.date, layout: .artwork)
        }.configurationDisplayName("Album Art").description("Album artwork and Play/Pause.")
            .supportedFamilies([.systemMedium])
    }
}
struct KUSCDetailsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HomeWidgetLayout.details.rawValue, provider: KUSCWidgetProvider()) {
            HomeWidgetView(snapshot: $0.snapshot, date: $0.date, layout: .details)
        }.configurationDisplayName("Now Playing").description("Work, movement, composer, performers and Play/Pause.")
            .supportedFamilies([.systemMedium])
    }
}
struct KUSCEverythingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HomeWidgetLayout.everything.rawValue, provider: KUSCWidgetProvider()) {
            HomeWidgetView(snapshot: $0.snapshot, date: $0.date, layout: .everything)
        }.configurationDisplayName("The Full Picture").description("Artwork, music details, programme, host and Play/Pause.")
            .supportedFamilies([.systemLarge])
    }
}

#if !MODERN
@main struct KUSCHomeWidgetBundle: WidgetBundle {
    var body: some Widget {
        KUSCPlaybackWidget()
        KUSCArtworkWidget()
        KUSCDetailsWidget()
        KUSCEverythingWidget()
    }
}
#endif
