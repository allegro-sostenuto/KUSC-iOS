import SwiftUI
import WidgetKit
import UIKit

enum HomeWidgetLayout: String, CaseIterable {
    case playback = "KUSCPlaybackWidget"
    case artwork = "KUSCArtworkWidget"
    case details = "KUSCDetailsWidget"
    case everything = "KUSCEverythingWidget"
    case artworkOnly = "KUSCArtworkOnlyWidget"
    case detailsOnly = "KUSCDetailsOnlyWidget"
}

/// Shared with native layout fixtures so the captured views are the widget views.
struct HomeWidgetView: View {
    let snapshot: WidgetPlaybackSnapshot
    let date: Date
    let layout: HomeWidgetLayout
    @Environment(\.colorScheme) private var colorScheme

    private var playing: Bool { snapshot.requestingPlayback(at: date) }
    private var ink: Color { colorScheme == .dark ? .white : .black }
    private var paper: Color { colorScheme == .dark ? .black : .white }

    var body: some View {
        Group {
            switch layout {
            case .artworkOnly:
                albumArtwork(cornerRadius: 0, outlined: false).ignoresSafeArea()
            case .detailsOnly:
                ViewThatFits(in: .vertical) {
                    details(large: false)
                    details(large: false).dynamicTypeSize(.large)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            case .playback:
                GeometryReader { proxy in
                    control(size: min(proxy.size.width, proxy.size.height) * 0.78)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .artwork:
                GeometryReader { proxy in
                    HStack(spacing: 20) {
                        cover.frame(width: min(proxy.size.height, proxy.size.width * 0.52), height: proxy.size.height)
                        control(size: min(76, proxy.size.height * 0.65))
                            .frame(maxWidth: .infinity)
                    }
                }
            case .details:
                HStack(spacing: 14) {
                    ViewThatFits(in: .vertical) {
                        details(large: false)
                        details(large: false).dynamicTypeSize(.large)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    control(size: 58)
                }
            case .everything:
                GeometryReader { proxy in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 18) {
                            cover.frame(width: min(136, proxy.size.height * 0.43), height: min(136, proxy.size.height * 0.43))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(snapshot.programme.isEmpty ? "KUSC" : snapshot.programme)
                                    .font(.subheadline.weight(.semibold)).lineLimit(2)
                                if !snapshot.host.isEmpty {
                                    Text(snapshot.host).font(.caption).foregroundStyle(ink.opacity(0.75)).lineLimit(2)
                                }
                                Spacer(minLength: 4)
                                control(size: 56)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(height: min(136, proxy.size.height * 0.43))
                        Rectangle().fill(ink.opacity(0.22)).frame(height: 1)
                        details(large: true).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
        }
        .foregroundStyle(ink)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .modifier(HomeWidgetBackground(edgeToEdge: layout == .artworkOnly))
    }

    private func details(large: Bool) -> some View {
        VStack(alignment: .leading, spacing: large ? 5 : 3) {
            Text(snapshot.work).font(large ? .headline : .subheadline.weight(.semibold))
                .lineLimit(2).minimumScaleFactor(0.85).layoutPriority(1)
            if !snapshot.movement.isEmpty {
                Text(snapshot.movement).font(.caption).lineLimit(large ? 2 : 1)
            }
            if !snapshot.composer.isEmpty {
                Text(snapshot.composer).font(.subheadline).lineLimit(1)
            }
            if !snapshot.performers.isEmpty {
                Text(snapshot.performers).font(.caption).foregroundStyle(ink.opacity(0.75)).lineLimit(large ? 2 : 1)
            }
        }.accessibilityElement(children: .combine)
    }

    private var cover: some View {
        albumArtwork(cornerRadius: 12, outlined: true)
    }

    private func albumArtwork(cornerRadius: CGFloat, outlined: Bool) -> some View {
        GeometryReader { proxy in
            Group {
                if let data = snapshot.artwork, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    paper.overlay { Image(systemName: "music.note").font(.system(size: 36, weight: .light)) }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                if outlined { RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(ink.opacity(0.22), lineWidth: 1) }
            }
        }.accessibilityLabel(snapshot.artwork == nil ? "Album artwork unavailable" : "Album artwork")
    }

    @ViewBuilder private func control(size: CGFloat) -> some View {
        if #available(iOS 17.0, *) {
            Button(intent: SetKUSCWidgetPlaybackIntent(playing: !playing)) { controlImage(size: size) }
                .buttonStyle(.plain)
                .accessibilityLabel(playing ? "Pause KUSC" : "Play KUSC")
        } else {
            Link(destination: WidgetPlaybackLink.url(playing: !playing)) { controlImage(size: size) }
                .accessibilityLabel(playing ? "Pause KUSC" : "Play KUSC")
        }
    }

    private func controlImage(size: CGFloat) -> some View {
        Image(systemName: playing ? "pause.fill" : "play.fill")
            .font(.system(size: size * 0.36, weight: .semibold))
            .offset(x: playing ? 0 : size * 0.025)
            .frame(width: size, height: size)
            .background(paper, in: Circle())
            .overlay { Circle().strokeBorder(ink.opacity(0.55), lineWidth: 1.5) }
            .contentShape(Circle())
    }
}

private struct HomeWidgetBackground: ViewModifier {
    var edgeToEdge = false
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        let color: Color = colorScheme == .dark ? .black : .white
        if #available(iOS 17.0, *) { content.containerBackground(for: .widget) { color } }
        else { content.padding(edgeToEdge ? 0 : 16).background(color) }
    }
}
