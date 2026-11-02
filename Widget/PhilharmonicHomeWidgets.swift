import SwiftUI
import WidgetKit

struct PhilharmonicWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetPlaybackSnapshot
}

struct PhilharmonicWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PhilharmonicWidgetEntry {
        .init(date: Date(), snapshot: .init(item: ProgrammeItem(id: "widget-preview", start: Date(),
            work: "Classical California", composer: "KUSC", performers: "Music for your day")))
    }
    func getSnapshot(in context: Context, completion: @escaping (PhilharmonicWidgetEntry) -> Void) {
        completion(.init(date: Date(), snapshot: WidgetSnapshotStore.shared?.read() ?? .init()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PhilharmonicWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshotStore.shared?.read() ?? .init()
        var entries = [PhilharmonicWidgetEntry(date: now, snapshot: snapshot)]
        let expires = snapshot.updatedAt.addingTimeInterval(WidgetPlaybackSnapshot.lifetime)
        if snapshot.playbackRequested && expires > now {
            entries.append(.init(date: expires, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(snapshot.requestingPlayback(at: now) ? 15 : 900))))
    }
}

struct PhilharmonicPlaybackWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HomeWidgetLayout.playback.rawValue, provider: PhilharmonicWidgetProvider()) {
            HomeWidgetView(snapshot: $0.snapshot, date: $0.date, layout: .playback)
                .widgetURL(WidgetPlaybackLink.url(playing: !$0.snapshot.requestingPlayback(at: $0.date), stationID: $0.snapshot.stationID))
        }.configurationDisplayName("Play / Pause").description("Just one button for Philharmonic.")
            .supportedFamilies([.systemSmall])
    }
}
struct PhilharmonicArtworkWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HomeWidgetLayout.artwork.rawValue, provider: PhilharmonicWidgetProvider()) {
            HomeWidgetView(snapshot: $0.snapshot, date: $0.date, layout: .artwork)
        }.configurationDisplayName("Album Art").description("Album artwork and Play/Pause.")
            .supportedFamilies([.systemMedium])
    }
}
struct PhilharmonicDetailsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HomeWidgetLayout.details.rawValue, provider: PhilharmonicWidgetProvider()) {
            HomeWidgetView(snapshot: $0.snapshot, date: $0.date, layout: .details)
        }.configurationDisplayName("Now Playing").description("Work, movement, composer, performers and Play/Pause.")
            .supportedFamilies([.systemMedium])
    }
}
struct PhilharmonicEverythingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HomeWidgetLayout.everything.rawValue, provider: PhilharmonicWidgetProvider()) {
            HomeWidgetView(snapshot: $0.snapshot, date: $0.date, layout: .everything)
        }.configurationDisplayName("The Full Picture").description("Artwork, music details, programme, host and Play/Pause.")
            .supportedFamilies([.systemLarge])
    }
}

struct PhilharmonicArtworkOnlyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HomeWidgetLayout.artworkOnly.rawValue, provider: PhilharmonicWidgetProvider()) {
            HomeWidgetView(snapshot: $0.snapshot, date: $0.date, layout: .artworkOnly)
        }.configurationDisplayName("Album Art Only").description("Just the album cover, without playback controls.")
            .supportedFamilies([.systemSmall])
            .contentMarginsDisabled()
    }
}
struct PhilharmonicDetailsOnlyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HomeWidgetLayout.detailsOnly.rawValue, provider: PhilharmonicWidgetProvider()) {
            HomeWidgetView(snapshot: $0.snapshot, date: $0.date, layout: .detailsOnly)
        }.configurationDisplayName("Music Details Only").description("Work, movement, composer and performers, without playback controls.")
            .supportedFamilies([.systemMedium])
    }
}

struct PhilharmonicControlWidgets: WidgetBundle {
    var body: some Widget {
        PhilharmonicPlaybackWidget()
        PhilharmonicArtworkWidget()
        PhilharmonicDetailsWidget()
        PhilharmonicEverythingWidget()
    }
}

struct PhilharmonicDisplayWidgets: WidgetBundle {
    var body: some Widget {
        PhilharmonicArtworkOnlyWidget()
        PhilharmonicDetailsOnlyWidget()
    }
}

#if !MODERN
@main struct PhilharmonicHomeWidgetBundle: WidgetBundle {
    var body: some Widget {
        PhilharmonicControlWidgets().body
        PhilharmonicDisplayWidgets().body
    }
}
#endif
