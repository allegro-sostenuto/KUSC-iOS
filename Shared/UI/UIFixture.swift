#if DEBUG
import SwiftUI
import UIKit

/// Deterministic native layout fixtures. No audio or network is started, and this
/// entire source is excluded from Release builds. Captures are layout evidence,
/// never evidence that a stream, schedule, output route, or buffer actually ran.
@MainActor enum UIFixture {
    static var state: String? {
        ProcessInfo.processInfo.environment["PHILHARMONIC_UI_STATE"]
    }

    static var largeText: Bool {
        ProcessInfo.processInfo.environment["PHILHARMONIC_UI_LARGE_TEXT"] == "1"
    }

    @discardableResult
    static func configure(model: AppModel) -> Bool {
        guard let state else { return false }
        // The explicit native probe owns its real audio session separately.
        if state == "audio-session-probe" { return true }
        let paused = ["paused", "paused-live", "no-artwork", "schedule-reminder"].contains(state)
        model.configureUIFixturePlayback(active: !paused)
        model.settings = AppSettings()
        model.settings.autoplay = false
        model.settings.appearance = state == "dark" ||
            ProcessInfo.processInfo.environment["PHILHARMONIC_UI_DARK"] == "1" ? "dark" : "light"
        model.settings.minimalist = state == "minimal" ||
            ProcessInfo.processInfo.environment["PHILHARMONIC_UI_MINIMAL"] == "1"
        model.settings.lastSleepMinutes = 30
        if ProcessInfo.processInfo.environment["PHILHARMONIC_UI_TRANSPORT_TOGGLE"] == "1" {
            // Use the existing silent coordinator harness for genuine button
            // actions without an AVPlayer, network stream or session activation.
            model.configureAudioRecoveryForTesting(playing: !paused)
        }
        if state == "schedule-power" { model.settings.scheduledStartDefaults = .init(batteryOnlyStop: true) }
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
        if state == "schedule-reminder" { model.configureScheduleReminderFixture() }
        if ProcessInfo.processInfo.environment["PHILHARMONIC_UI_REPEAT_MODEL_UPDATES"] == "1" {
            Task { @MainActor in
                for _ in 0..<240 {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard !Task.isCancelled else { return }
                    model.objectWillChange.send()
                }
            }
        }
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
        if ProcessInfo.processInfo.environment["PHILHARMONIC_UI_ROTATION_DRIVER"] == "xctest" {
            return true
        }
        let orientation: UIInterfaceOrientationMask =
            ProcessInfo.processInfo.environment["PHILHARMONIC_UI_LANDSCAPE"] == "1" ? .landscapeRight : .portrait
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
        Group {
            if UIFixture.largeText { content.dynamicTypeSize(.accessibility3) }
            else { content }
        }
    }
}
#endif
