#if canImport(UIKit) && !canImport(PhilharmonicCore) && DEBUG
import AVFoundation
import XCTest
@testable import Philharmonic_SE

/// An opt-in hosted network check, selected by the native source/audio scripts.
/// It establishes AVPlayer readiness and a moving decoder clock on a disposable
/// simulator. It does not establish audibility, station identity by ear, source
/// fidelity, Shanghai reachability, or physical-device/background operation.
final class StationSourcePlaybackTests: XCTestCase {
    private struct Attempt: Codable {
        let number: Int
        let ready: Bool
        let advancing: Bool
        let elapsedSeconds: Double
        let decoderSeconds: Double
        let error: String?
        let diagnosticReport: String?
    }

    private struct Result: Codable {
        let stationID: String
        let name: String
        let source: String
        let format: String
        let quality: String
        let ready: Bool
        let advancing: Bool
        let elapsedSeconds: Double
        let decoderSeconds: Double
        let error: String?
        let firstFailure: String?
        let attemptCount: Int
        let attempts: [Attempt]
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
        var sources: [(RadioStation, StationAudioQuality, StationAudioSource)] = []
        for station in StationCatalog.stations {
            let standard = station.audioSource(for: .standard)
            let high = station.audioSource(for: .high)
            sources.append((station, .standard, standard))
            if high != standard { sources.append((station, .high, high)) }
        }
        for (station, quality, source) in sources {
            let began = ProcessInfo.processInfo.systemUptime
            let deadline = began + 60
            var attempts: [Attempt] = []
            for number in 1...3 {
                let now = ProcessInfo.processInfo.systemUptime
                guard now < deadline else { break }
                // Match the app's bounded live reconnect behavior. KUSC may
                // spend its full remaining window preparing a marked pre-roll.
                let attemptDeadline = min(deadline, now + (station.id == "kusc" ? 60 : 20))
                let attempt = try await probe(station, source: source, number: number, deadline: attemptDeadline)
                attempts.append(attempt)
                print("[station-source-attempt] \(station.id) attempt=\(number) ready=\(attempt.ready) advancing=\(attempt.advancing) elapsed=\(attempt.elapsedSeconds) decoderDelta=\(attempt.decoderSeconds) error=\(attempt.error ?? "none")")
                if attempt.advancing { break }
                let remaining = deadline - ProcessInfo.processInfo.systemUptime
                guard number < 3, remaining > 3 else { break }
                try await Task.sleep(nanoseconds: 3_000_000_000)
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - began
            let last = try XCTUnwrap(attempts.last)
            let result = Result(stationID: station.id, name: station.name,
                source: source.url.absoluteString, format: source.format.rawValue, quality: quality.rawValue,
                ready: last.ready, advancing: last.advancing, elapsedSeconds: elapsed,
                decoderSeconds: last.decoderSeconds, error: last.error,
                firstFailure: attempts.compactMap(\.error).first,
                attemptCount: attempts.count, attempts: attempts)
            results.append(result)
            print("[station-source] \(station.id) quality=\(quality.rawValue) ready=\(result.ready) advancing=\(result.advancing) attempts=\(result.attemptCount) elapsed=\(elapsed) decoderDelta=\(result.decoderSeconds) firstFailure=\(result.firstFailure ?? "none") error=\(result.error ?? "none")")
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let report = try encoder.encode(results)
        let attachment = XCTAttachment(data: report, uniformTypeIdentifier: "public.json")
        attachment.name = "Native station source results"; attachment.lifetime = .keepAlways
        add(attachment)
        let summary = results.map {
            "\($0.stationID) [\($0.quality)]: \($0.advancing ? "PASS" : "FAIL") · attempts=\($0.attemptCount) · \($0.error ?? "ready and decoder advancing") · firstFailure=\($0.firstFailure ?? "none")"
        }.joined(separator: "\n")
        let text = XCTAttachment(string: summary)
        text.name = "Native station source summary"; text.lifetime = .keepAlways
        add(text)
        for result in results {
            XCTAssertTrue(result.ready && result.advancing, "\(result.stationID): \(result.error ?? "native playback did not advance")")
        }
    }

    @MainActor private func probe(_ station: RadioStation, source: StationAudioSource, number: Int, deadline: TimeInterval) async throws -> Attempt {
        let engine = RollingAudioEngine()
        engine.volume = 0 // Decoder readiness is tested without audible output.
        engine.diagnostics.start(context: "Native station source \(station.id), attempt \(number)")
        var latest: EngineSnapshot?
        var failure: String?
        engine.onUpdate = { latest = $0 }
        engine.onFailure = { if failure == nil { failure = Self.describe($0) } }
        let began = ProcessInfo.processInfo.systemUptime
        let starting = Task {
            do { try await engine.start(url: source.url, retentionMinutes: 0) }
            catch is CancellationError { }
            catch { if failure == nil { failure = Self.describe(error) } }
        }
        defer { starting.cancel(); engine.stop() }
        var firstDecoderSeconds: Double?
        var decoderDelta: Double = 0
        var advancing = false
        var ready = false
        while ProcessInfo.processInfo.systemUptime < deadline && failure == nil {
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
        let error = failure ?? (advancing ? nil : "Timed out before one second of native decoder advancement")
        let report = advancing ? nil : engine.diagnostics.report
        starting.cancel()
        engine.stop()
        await starting.value
        return Attempt(number: number, ready: ready, advancing: advancing,
            elapsedSeconds: elapsed, decoderSeconds: decoderDelta, error: error, diagnosticReport: report)
    }

    private static func describe(_ error: Error) -> String {
        let error = error as NSError
        var description = "\(error.domain) \(error.code): \(error.localizedDescription)"
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            description += " (\(underlying.domain) \(underlying.code): \(underlying.localizedDescription))"
        }
        return description
    }
}
#endif
