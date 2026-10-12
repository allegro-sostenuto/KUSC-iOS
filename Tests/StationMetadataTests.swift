import Foundation
import XCTest
#if canImport(UIKit) && !canImport(KUSCCore)
import UIKit
#endif
#if canImport(KUSCCore)
@testable import KUSCCore
#else
@testable import KUSC_SE
#endif

final class StationMetadataTests: XCTestCase {
    func testDirectMetadataAdvancesWhenProgrammeDatesDisappearOrFreeze() {
        let start = Date(timeIntervalSince1970: 1000)
        var clock = DirectMetadataClock()
        XCTAssertEqual(clock.update(station: start, seconds: 10, now: start, advancing: true), start)
        XCTAssertEqual(clock.update(station: nil, seconds: 40, now: start.addingTimeInterval(600), advancing: true), start.addingTimeInterval(30))
        XCTAssertEqual(clock.update(station: start, seconds: 70, now: start.addingTimeInterval(800), advancing: true), start.addingTimeInterval(60))
        let corrected = start.addingTimeInterval(80)
        XCTAssertEqual(clock.update(station: corrected, seconds: 71, now: corrected, advancing: true), corrected)
    }

    func testDirectMetadataWithoutDatesUsesMediaProgressAndHonorsPause() {
        let start = Date(timeIntervalSince1970: 1000)
        var clock = DirectMetadataClock()
        XCTAssertNil(clock.update(station: nil, seconds: 0, now: start, advancing: false))
        XCTAssertEqual(clock.update(station: nil, seconds: 4, now: start, advancing: true), start)
        XCTAssertEqual(clock.update(station: nil, seconds: 14, now: start, advancing: true), start.addingTimeInterval(10))
        XCTAssertEqual(clock.update(station: nil, seconds: 14, now: start.addingTimeInterval(600), advancing: false), start.addingTimeInterval(10))
        XCTAssertEqual(clock.update(station: nil, seconds: 15, now: start, advancing: true), start.addingTimeInterval(11))
        XCTAssertEqual(clock.update(station: nil, seconds: 0, now: start.addingTimeInterval(700), advancing: true), start.addingTimeInterval(700))
    }

    #if canImport(UIKit) && !canImport(KUSCCore)
    @MainActor func testChangedInlineArtworkForTheSamePieceGetsANewCacheURL() throws {
        let store = StationArtworkStore()
        let id = "artwork-regression-\(UUID().uuidString)"
        let first = Data([0xff, 0xd8, 0xff, 1])
        let second = Data([0xff, 0xd8, 0xff, 2])
        let a = try XCTUnwrap(store.resolve("data:image/jpeg;base64," + first.base64EncodedString(), itemID: id))
        let b = try XCTUnwrap(store.resolve("data:image/jpeg;base64," + second.base64EncodedString(), itemID: id))
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        XCTAssertNotEqual(a, b, "ArtworkCache must not reuse the previous image for a corrected station response")
        XCTAssertEqual(try Data(contentsOf: b), second)
        XCTAssertEqual(store.resolve("data:image/jpeg;base64," + second.base64EncodedString(), itemID: id), b)
    }

    @MainActor func testLiveMetadataPublishesBeforeSlowHistoryAndBypassesResponseCache() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MetadataResponseProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        MetadataResponseProtocol.current = try fixture("official-now-2026-09-19")
        MetadataResponseProtocol.history = try fixture("official-combined-2026-09-19")
        MetadataResponseProtocol.historyCompleted = false
        MetadataResponseProtocol.requests = []
        let service = MetadataService(session: session)
        var receivedEarly = false
        _ = try await service.fetch { items in
            receivedEarly = !MetadataResponseProtocol.historyCompleted
            XCTAssertFalse(items.isEmpty)
        }
        XCTAssertTrue(receivedEarly, "The /now result cannot wait for the day schedule")
        XCTAssertTrue(MetadataResponseProtocol.requests.allSatisfy {
            $0.cachePolicy == .reloadIgnoringLocalCacheData && $0.value(forHTTPHeaderField: "Cache-Control") == "no-cache"
        })
        XCTAssertEqual(StationConfiguration.metadataRefreshInterval, 5)
    }

    @MainActor func testManualRefreshBypassesDayIntervalsAndKeepsHistoryOnFailure() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MetadataResponseProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); MetadataResponseProtocol.failRequests = false }
        MetadataResponseProtocol.current = try fixture("official-now-2026-09-19")
        MetadataResponseProtocol.history = try fixture("official-combined-2026-09-19")
        MetadataResponseProtocol.requests = []
        let service = MetadataService(session: session)
        let original = try await service.fetch()
        XCTAssertFalse(original.isEmpty)
        XCTAssertEqual(MetadataResponseProtocol.requests.count, 4)
        _ = try await service.fetch()
        XCTAssertEqual(MetadataResponseProtocol.requests.count, 5, "Normal polls reuse fresh day history")
        _ = try await service.fetch(force: true)
        XCTAssertEqual(MetadataResponseProtocol.requests.count, 9, "Pull-to-refresh reloads all three days immediately")
        MetadataResponseProtocol.failRequests = true
        let retained = try await service.fetch(force: true)
        XCTAssertEqual(Set(retained.map(\.id)), Set(original.map(\.id)))
        XCTAssertNotNil(service.lastWarning)
    }

    @MainActor func testManualArtworkRefreshReloadsSameURLAndPreservesCacheOnFailure() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("refresh-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        func picture(_ color: UIColor) throws -> Data {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
                color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            }
            return try XCTUnwrap(image.pngData())
        }
        try picture(.red).write(to: url)
        let cache = ArtworkCache()
        let original = await cache.image(at: url)
        XCTAssertNotNil(original)
        try picture(.blue).write(to: url)
        let cached = await cache.image(at: url)
        XCTAssertEqual(cached?.pngData(), original?.pngData())
        let refreshed = await cache.image(at: url, forceReload: true)
        XCTAssertNotNil(refreshed)
        XCTAssertNotEqual(refreshed?.pngData(), original?.pngData())
        try Data("invalid image".utf8).write(to: url)
        let failed = await cache.image(at: url, forceReload: true)
        XCTAssertNil(failed)
        let preserved = await cache.image(at: url)
        XCTAssertEqual(preserved?.pngData(), refreshed?.pngData())
    }
    #endif
    private func fixture(_ name: String) throws -> Data {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: StationMetadataTests.self)
        #endif
        let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? bundle.url(forResource: name, withExtension: "json")
        return try Data(contentsOf: XCTUnwrap(url, "Missing station fixture \(name).json"))
    }

    func testObservedCombinedResponsePreservesBroadcastFactsAndProgrammeContext() throws {
        let response = try StationMetadataParser.combined(fixture("official-combined-2026-09-19"))
        XCTAssertEqual(response.records.count, 6)
        XCTAssertEqual(response.programmes.count, 1)
        XCTAssertEqual(response.programmes[0].name, "Classical Music with Maggie Clennon Reberg")
        XCTAssertEqual(response.programmes[0].host, "Maggie Clennon Reberg")
        let piece = try XCTUnwrap(response.records.first { $0.item.composer == "Claude Debussy" })
        XCTAssertEqual(piece.item.work, "Prelude to the Afternoon of a Faun L.86")
        XCTAssertEqual(piece.item.performers, "Philharmonia Orchestra · Pablo Heras-Casado")
        XCTAssertEqual(piece.item.programme, response.programmes[0].name)
        XCTAssertEqual(piece.item.host, response.programmes[0].host)
        XCTAssertEqual(piece.item.start, StationMetadataParser.timestamp("2026-09-19T16:49:54Z"))
        XCTAssertEqual(piece.item.end, StationMetadataParser.timestamp("2026-09-19T16:59:32Z"))
        XCTAssertNil(piece.item.movement, "The station supplied no separate movement title.")
    }

    func testNowAndDayFormatsIdentifyTheSameAiringWithoutDuplicatingTimeline() throws {
        let day = try StationMetadataParser.combined(fixture("official-combined-2026-09-19"))
        let current = try XCTUnwrap(StationMetadataParser.now(fixture("official-now-2026-09-19"),
                                                             programmes: day.programmes))
        let history = try XCTUnwrap(day.records.first { $0.item.work == current.item.work })
        XCTAssertEqual(current.item.id, history.item.id)
        XCTAssertEqual(current.item.start, history.item.start)
        XCTAssertEqual(current.item.end, history.item.end)
        XCTAssertEqual(current.item.host, "Maggie Clennon Reberg")
        var timeline = PlaybackTimeline(items: day.records.map(\.item))
        timeline.merge([current.item])
        XCTAssertEqual(timeline.items.count, 6)
        XCTAssertEqual(timeline.item(at: current.item.start)?.id, current.item.id)
    }

    func testTimezoneAndFractionalTimestampFormatsReferToSameInstant() {
        let utc = StationMetadataParser.timestamp("2026-09-19T16:49:54Z")
        XCTAssertNotNil(utc)
        XCTAssertEqual(utc, StationMetadataParser.timestamp("2026-09-19T09:49:54-07:00"))
        XCTAssertEqual(utc, StationMetadataParser.timestamp(["dateTime": "2026-09-19T16:49:54.000Z"]))
        XCTAssertNil(StationMetadataParser.timestamp("not a timestamp"))
        XCTAssertNil(StationMetadataParser.timestamp(NSNull()))
    }

    func testMalformedRowDoesNotEraseUsableDayHistoryAndSpeechIsExcluded() throws {
        var blocks = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("official-combined-2026-09-19")) as? [[String: Any]])
        var songs = try XCTUnwrap(blocks[0]["songs"] as? [[String: Any]])
        songs.append(["name": "Bad row", "start": "yesterday"])
        songs.append(["name": "Station announcement", "start": "2026-09-19T17:00:00Z",
                      "extraInfo": ["media_type": "Announcement"]])
        blocks[0]["songs"] = songs
        let result = try StationMetadataParser.combined(JSONSerialization.data(withJSONObject: blocks))
        XCTAssertEqual(result.records.count, 6)
    }

    func testMissingOrReversedEndDoesNotSupplyReliableSleepTiming() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("official-now-2026-09-19")) as? [String: Any])
        var extra = try XCTUnwrap(object["extraInfo"] as? [String: Any])
        object.removeValue(forKey: "end")
        extra.removeValue(forKey: "AirStoptime")
        object["extraInfo"] = extra
        let missing = try XCTUnwrap(StationMetadataParser.now(JSONSerialization.data(withJSONObject: object), programmes: []))
        XCTAssertNil(missing.item.end)
        XCTAssertFalse(missing.item.timingReliable)
        extra["AirStoptime"] = "2026-09-19T16:40:00Z"
        object["extraInfo"] = extra
        let reversed = try XCTUnwrap(StationMetadataParser.now(JSONSerialization.data(withJSONObject: object), programmes: []))
        XCTAssertNil(reversed.item.end)
        XCTAssertFalse(reversed.item.timingReliable)
    }

    func testWrongTopLevelShapeFailsInsteadOfInventingMetadata() {
        XCTAssertThrowsError(try StationMetadataParser.combined(Data("{}".utf8)))
        XCTAssertThrowsError(try StationMetadataParser.now(Data("[]".utf8), programmes: []))
        XCTAssertThrowsError(try StationMetadataParser.combined(Data("{truncated".utf8)))
    }
}

#if canImport(UIKit) && !canImport(KUSCCore)
private final class MetadataResponseProtocol: URLProtocol {
    static var failRequests = false
    static var current = Data()
    static var history = Data()
    static var historyCompleted = false
    static var requests: [URLRequest] = []
    private var delivery: DispatchWorkItem?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        // Serial main queue owns the stub's shared test state.
        DispatchQueue.main.async { [self] in
            Self.requests.append(request)
            let isCurrent = request.url!.path.contains("/now")
            let work = DispatchWorkItem { [self] in
                if Self.failRequests {
                    client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                    return
                }
                if !isCurrent { Self.historyCompleted = true }
                client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: isCurrent ? Self.current : Self.history)
                client?.urlProtocolDidFinishLoading(self)
            }
            delivery = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (isCurrent ? 0 : 0.5), execute: work)
        }
    }
    override func stopLoading() { DispatchQueue.main.async { [self] in delivery?.cancel() } }
}
#endif
