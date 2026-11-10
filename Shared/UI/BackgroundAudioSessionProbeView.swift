#if DEBUG
import SwiftUI
import AVFoundation
import UIKit

/// Explicit CI launch only. Unlike layout fixtures, this exercises real Apple
/// session APIs and silent standby across an actual Home/background transition.
/// It performs no station networking or system-volume writes.
@MainActor struct BackgroundAudioSessionProbeView: View {
    @State private var rows: [String] = []
    @State private var phase = "idle"
    @State private var standby = SilentStandby()
    private let audio = AVAudioSession.sharedInstance()

    var body: some View {
        ScrollView {
            VStack {
                Button("Prepare native probe", action: prepare).accessibilityIdentifier("audio-probe-prepare")
                Text(phase).accessibilityIdentifier("audio-probe-phase")
                Text(rows.joined(separator: "\n")).font(.caption).accessibilityIdentifier("audio-probe-report")
            }.padding()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            guard phase == "prepared" else { return }
            attempt("background_playback") {
                try audio.setCategory(.playback, mode: .default, policy: .default, options: [.mixWithOthers])
                try audio.setActive(true)
            }
            attempt("background_play_and_record") {
                try audio.setCategory(.playAndRecord, mode: .default, policy: .default,
                                      options: [.defaultToSpeaker, .mixWithOthers])
                try audio.setActive(true)
            }
            attempt("background_playback_restore") {
                try audio.setCategory(.playback, mode: .default, policy: .default, options: [.mixWithOthers])
                try audio.setActive(true)
            }
            cleanup(); phase = "complete"
        }
        .onDisappear(perform: cleanup)
    }
    private func prepare() {
        attempt("foreground_prepare") {
            try audio.setCategory(.playback, mode: .default, policy: .default, options: [.mixWithOthers])
            try audio.setActive(true)
            try standby.start()
        }
        phase = standby.running ? "prepared" : "failed"
    }
    private func attempt(_ name: String, action: () throws -> Void) {
        var entry: [String: Any] = ["name": name, "ios": UIDevice.current.systemVersion,
                                  "app_state": UIApplication.shared.applicationState == .background ? "background" : "foreground"]
        do { try action(); entry["result"] = "success" }
        catch { let error = error as NSError; entry["result"] = "failure"; entry["error_code"] = error.code; entry["error_domain"] = error.domain }
        entry["category"] = audio.category.rawValue
        entry["options"] = audio.categoryOptions.rawValue
        entry["outputs"] = audio.currentRoute.outputs.map { $0.portType.rawValue }
        entry["volume"] = audio.outputVolume
        entry["standby_running"] = standby.running
        let line = String(data: try! JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]), encoding: .utf8)!
        rows.append(line); print("NATIVE_SPEAKER_PROBE " + line)
    }
    private func cleanup() {
        standby.stop()
        try? audio.setCategory(.playback, mode: .default, policy: .default, options: [.mixWithOthers])
        try? audio.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
#endif
