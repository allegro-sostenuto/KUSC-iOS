#if DEBUG
import SwiftUI
import UIKit

struct HomeWidgetFixture: View {
    let state: String
    private var layout: HomeWidgetLayout {
        if state.contains("artwork") { return .artwork }
        if state.contains("details") { return .details }
        if state.contains("everything") { return .everything }
        return .playback
    }
    private var dark: Bool { ProcessInfo.processInfo.environment["KUSC_UI_DARK"] == "1" }
    private var snapshot: WidgetPlaybackSnapshot {
        let artwork: Data? = state.contains("empty") ? nil : UIGraphicsImageRenderer(size: CGSize(width: 240, height: 240)).image { _ in
            UIColor(red: 0.48, green: 0.12, blue: 0.19, alpha: 1).setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 240, height: 240))
            UIColor.white.withAlphaComponent(0.8).setStroke()
            let circle = UIBezierPath(ovalIn: CGRect(x: 40, y: 40, width: 160, height: 160))
            circle.lineWidth = 2; circle.stroke()
        }.pngData()
        return .init(playbackRequested: !state.contains("empty"), item: state.contains("empty") ? nil : ProgrammeItem(
            id: "widget-fixture", start: Date(), work: "Piano Concerto in A minor, Op. 16",
            movement: "II. Adagio · layout fixture", composer: "Edvard Grieg",
            performers: "Piano soloist · orchestra · conductor · test data",
            programme: "Classical California · test data", host: "Host · test data"), artwork: artwork)
    }

    var body: some View {
        GeometryReader { proxy in
            let width: CGFloat = proxy.size.width < 390 ? 292 : 338
            let small: CGFloat = proxy.size.width < 390 ? 141 : 158
            let height: CGFloat = layout == .everything ? (proxy.size.width < 390 ? 311 : 354) : small
            VStack(spacing: 24) {
                Text("Widget layout fixture").font(.headline)
                HomeWidgetView(snapshot: snapshot, date: Date(), layout: layout)
                    .padding(16)
                    .frame(width: layout == .playback ? small : width, height: height)
                    .background(dark ? Color.black : .white, in: RoundedRectangle(cornerRadius: 24))
                    .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(dark ? Color.white.opacity(0.3) : .black.opacity(0.2)) }
                Text("Native widget view · synthetic metadata\nHome Screen installation is tested separately.")
                    .font(.caption).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(dark ? Color.black : .white)
        .preferredColorScheme(dark ? .dark : .light)
    }
}
#endif
