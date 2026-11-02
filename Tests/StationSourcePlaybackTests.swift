#if canImport(UIKit) && !canImport(PhilharmonicCore) && DEBUG
import AVFoundation
import XCTest
@testable import Philharmonic_SE

/// An opt-in hosted network check, selected by the native source/audio scripts.
/// It establishes AVPlayer readiness and a moving decoder clock on a disposable
/// simulator. It does not establish audibility, station identity by ear, source
/// fidelity, Shanghai reachability, or physical-device/background operation.
final class StationSourcePlaybackTests: XCTestCase {
    private struct Result: Codable {
        let stationID: String
        let name: String
        let source: String
        let format: String
        let ready: Bool
        let advancing: Bool
        let elapsedSeconds: Double
        let decoderSeconds: Double
        let error: String?
    }

    @MainActor func testApprovedSourcesBecomeReadyAndAdvanceThroughNativePlayer() async throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Source probes run only on an explicitly created disposable simulator.")
        #endif
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playback, mode: .default)
        try audio.setActive(true)
        defer { try? audio.setActive(false, options: .notifyOthersOnDeactivation) }
        var results: [Result] = []
        for station in StationCatalog.stations {
            let engine = RollingAudioEngine()
            engine.volume = 0 // Decoder readiness is tested without audible output.
            var latest: EngineSnapshot?
            var failure: String?
            engine.onUpdate = { latest = $0 }
            engine.onFailure = { failure = $0.localizedDescription }
            let began = ProcessInfo.processInfo.systemUptime
            let starting = Task {
                do { try await engine.start(url: station.audioURL, retentionMinutes: 0) }
                catch is CancellationError { }
                catch { failure = error.localizedDescription }
            }
            defer { starting.cancel(); engine.stop() }
            var firstDecoderSeconds: Double?
            var decoderDelta: Double = 0
            var advancing = false
            var ready = false
            let timeout: TimeInterval = station.id == "kusc" ? 60 : 30
            while ProcessInfo.processInfo.systemUptime - began < timeout && failure == nil {
                if latest?.isReady == true { ready = true }
                if latest?.isPlaying == true, latest?.isWaiting == false,
                   let seconds = engine.directSecondsForTesting {
                    if let first = firstDecoderSeconds {
                        decoderDelta = max(0, seconds - first)
                        if decoderDelta >= 1 { advancing = true; break }
                    } else { firstDecoderSeconds = seconds }
                }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - began
            starting.cancel()
            engine.stop()
            await starting.value
            let result = Result(stationID: station.id, name: station.name,
                source: station.audioURL.absoluteString, format: station.audioFormat.rawValue,
                ready: ready, advancing: advancing, elapsedSeconds: elapsed,
                decoderSeconds: decoderDelta,
                error: failure ?? (advancing ? nil : "Timed out before one second of native decoder advancement"))
            results.append(result)
            print("[station-source] \(station.id) ready=\(ready) advancing=\(advancing) elapsed=\(elapsed) decoderDelta=\(decoderDelta) error=\(result.error ?? "none")")
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let report = try encoder.encode(results)
        let attachment = XCTAttachment(data: report, uniformTypeIdentifier: "public.json")
        attachment.name = "Native station source results"; attachment.lifetime = .keepAlways
        add(attachment)
        let summary = results.map { "\($0.stationID): \($0.advancing ? "PASS" : "FAIL") · \($0.error ?? "ready and decoder advancing")" }.joined(separator: "\n")
        let text = XCTAttachment(string: summary)
        text.name = "Native station source summary"; text.lifetime = .keepAlways
        add(text)
        for result in results {
            XCTAssertTrue(result.ready && result.advancing, "\(result.stationID): \(result.error ?? "native playback did not advance")")
        }
    }
}
#endif
