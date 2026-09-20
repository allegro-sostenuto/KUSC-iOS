#if DEBUG
import SwiftUI
import UIKit

/// Deterministic native layout fixtures. No audio or network is started, and this
/// entire source is excluded from Release builds. Captures are layout evidence,
/// never evidence that a stream, schedule, output route, or buffer actually ran.
@MainActor enum UIFixture {
    static var state: String? {
        ProcessInfo.processInfo.environment["KUSC_UI_STATE"]
    }

    static var largeText: Bool {
        ProcessInfo.processInfo.environment["KUSC_UI_LARGE_TEXT"] == "1"
    }

    @discardableResult
    static func configure(model: AppModel) -> Bool {
        guard let state else { return false }
        let paused = ["paused", "paused-buffer", "no-artwork"].contains(state)
        model.configureUIFixturePlayback(active: !paused)
        model.settings = AppSettings()
        model.settings.autoplay = false
        model.settings.appearance = state == "dark" ||
            ProcessInfo.processInfo.environment["KUSC_UI_DARK"] == "1" ? "dark" : "light"
        model.settings.minimalist = state == "minimal" ||
            ProcessInfo.processInfo.environment["KUSC_UI_MINIMAL"] == "1"
        model.settings.lastSleepMinutes = 30
        let anchor = ISO8601DateFormatter().date(from: "2026-09-20T09:41:00Z")!
        model.heardAt = anchor
        model.state = paused ? .pausedLive : .playingLive
        model.artwork = nil
        model.currentItem = ProgrammeItem(
            id: "ui-current", start: anchor.addingTimeInterval(-540),
            work: "Native layout fixture", movement: "Movement title for wrapping and spacing",
            composer: "Composer · test data", performers: "Orchestra · soloist · conductor · test data",
            programme: "Programme layout fixture", host: "Host · test data"
        )
        model.programmeName = "Programme layout fixture"
        model.hostName = "Host · test data"
        model.previousItems = (1...5).map { index in
            ProgrammeItem(id: "ui-previous-\(index)",
                          start: anchor.addingTimeInterval(TimeInterval(-540 - index * 600)),
                          work: "Earlier work \(index) · fixture", composer: "Composer · test data")
        }
        model.upcomingItems = (1...10).map { index in
            ProgrammeItem(id: "ui-next-\(index)",
                          start: anchor.addingTimeInterval(TimeInterval(index * 600)),
                          work: "Upcoming work \(index) · fixture", composer: "Composer · test data")
        }
        if state == "no-artwork" || state == "unavailable-programme" {
            model.currentItem = nil
            model.previousItems = []
            model.upcomingItems = []
            model.programmeName = nil
            model.hostName = nil
            model.state = .idle
        }
        if state == "reconnecting" {
            model.state = .reconnecting(since: Date().addingTimeInterval(-14))
        }
        if state == "partial-buffer" || state == "paused-buffer" {
            let window = BufferWindow(oldest: anchor.addingTimeInterval(-135), live: anchor)
            let heard = anchor.addingTimeInterval(-90)
            model.settings.retentionMinutes = 5
            model.bufferWindow = window
            model.heardAt = heard
            model.state = state == "paused-buffer" ? .pausedDelayed : .playingDelayed
            var sample = PlaybackTransportClock.Sample()
            sample.heardAt = heard
            sample.window = window
            sample.sampledAt = ProcessInfo.processInfo.systemUptime
            sample.playableRanges = [window.oldest...window.live]
            sample.maximumExtrapolation = 0
            model.transportClock.configureUIFixture(sample)
        }
        if state == "scheduled-silent" {
            model.state = .scheduledSilent
            model.scheduleDescription = "UI fixture · silent preparation"
        }
        if state == "scheduled-fade" {
            model.state = .scheduledFadeIn
            model.scheduleDescription = "UI fixture · fade-in"
        }
        if state == "unavailable-output" {
            model.configureUIFixtureOutputUnavailable()
        }
        // XCTest rotates the actual simulated device and captures its oriented
        // app image. A scene-only rotation leaves simctl's framebuffer portrait.
        if ProcessInfo.processInfo.environment["KUSC_UI_ROTATION_DRIVER"] == "xctest" {
            return true
        }
        let orientation: UIInterfaceOrientationMask =
            ProcessInfo.processInfo.environment["KUSC_UI_LANDSCAPE"] == "1" ? .landscapeRight : .portrait
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first else { return }
            scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { error in
                print("UI fixture orientation request failed: \(error.localizedDescription)")
            }
        }
        return true
    }
}

struct UIFixtureTextSize: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if UIFixture.largeText { content.dynamicTypeSize(.accessibility3) }
        else { content }
    }
}
#endif
