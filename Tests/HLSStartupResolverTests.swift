import Foundation
import XCTest
#if canImport(KUSCCore)
@testable import KUSCCore
#else
@testable import KUSC_SE
#endif

final class HLSStartupResolverTests: XCTestCase {
    private let master = URL(string: "https://station.example.test/redirect.m3u8")!
    private let media = URL(string: "https://cdn.example.test/session/playlist.m3u8")!

    private func advertisement() throws -> Data {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let url = bundle.url(forResource: "kusc-startup-ad", withExtension: "m3u8", subdirectory: "Fixtures")
            ?? bundle.url(forResource: "kusc-startup-ad", withExtension: "m3u8")
        return try Data(contentsOf: XCTUnwrap(url))
    }

    private var programme: Data {
        Data("""
        #EXTM3U
        #EXT-X-TARGETDURATION:10
        #EXT-X-MEDIA-SEQUENCE:4
        #EXTINF:9.98458,Leo Delibes - Lakme: Flower Duet
        4.aac
        #EXTINF:9.98458,Leo Delibes - Lakme: Flower Duet
        5.aac
        #EXTINF:9.98458,VT Classical California
        6.aac
        """.utf8)
    }

    func testCapturedStartupPromoHasExactMarkedBoundaries() throws {
        let manifest = try HLSManifest.parse(advertisement(), baseURL: media)
        XCTAssertEqual(manifest.segments.map(\.isMarkedAdvertisement), [true, true, true, false])
        XCTAssertEqual(manifest.segments.prefix(3).reduce(0) { $0 + $1.duration }, 21.59456, accuracy: 0.00001)
        XCTAssertEqual(manifest.segments[3].start, manifest.segments[2].end)
    }

    func testWaitsOnSameSessionWithoutDownloadingAdsOrRequestingAnotherMaster() async throws {
        let ad = try advertisement()
        let masterData = Data("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=96000\n\(media.absoluteString)\n".utf8)
        var requests: [URL] = []
        var advances: [URL] = []
        var waits = 0
        let resolved = try await HLSStartupResolver.resolve(master, fetch: { url in
            requests.append(url)
            if url == self.master { return (masterData, self.master) }
            XCTAssertEqual(url, self.media)
            return (advances.isEmpty ? ad : self.programme, self.media)
        }, advance: { url in
            advances.append(url)
        }, wait: { seconds in
            XCTAssertGreaterThan(seconds, 0)
            XCTAssertLessThanOrEqual(seconds, 2)
            waits += 1
            if waits > 3 { throw AudioStreamError.stalled }
        })
        XCTAssertEqual(requests, [master, media, media])
        XCTAssertEqual(waits, 1)
        XCTAssertEqual(advances, [media.deletingLastPathComponent().appendingPathComponent("4.aac")])
        XCTAssertEqual(resolved.url, media)
        XCTAssertFalse(resolved.manifest.segments.contains(where: \.isMarkedAdvertisement))
        // Sliding away the only date tag must retain the verified music clock.
        let initial = try HLSManifest.parse(ad, baseURL: media)
        XCTAssertEqual(resolved.manifest.segments.first?.start, initial.segments.last?.start)
        XCTAssertNotNil(resolved.manifest.segments.last?.start)
    }

    func testMusicAndUnknownLabelsStartWithoutWaiting() async throws {
        let text = """
        #EXTM3U
        #EXTINF:10,
        1.aac
        #EXTINF:10,VT Classical California
        2.aac
        #EXTINF:10,A work, with a comma
        3.aac
        """
        let resolved = try await HLSStartupResolver.resolve(media, fetch: { _ in (Data(text.utf8), self.media) }, advance: { _ in
            XCTFail("A clean session needs no extra media request")
        }, wait: { _ in
            XCTFail("Unmarked station content must not be withheld")
        })
        XCTAssertEqual(resolved.manifest.segments.last?.title, "A work, with a comma")
        XCTAssertEqual(resolved.manifest.segments.count, 3)
    }

    func testAllAdvertisedAdSegmentsMustLeaveBeforeHandingSessionToPlayer() async throws {
        let text = "#EXTM3U\n#EXTINF:10,Music\n1.aac\n#EXTINF:10,Advertisement\n2.aac\n"
        var waits = 0
        let resolved = try await HLSStartupResolver.resolve(media, fetch: { _ in
            (waits == 0 ? Data(text.utf8) : self.programme, self.media)
        }, advance: { _ in XCTFail("Music before the final ad cannot advance beyond it") }, wait: { _ in waits += 1 })
        XCTAssertEqual(waits, 1)
        XCTAssertFalse(resolved.manifest.segments.contains(where: \.isMarkedAdvertisement))
    }

    func testStuckAdWindowFailsInsteadOfPlayingAnAdOrWaitingForever() async throws {
        let ad = try advertisement()
        do {
            _ = try await HLSStartupResolver.resolve(media, maximumWait: 0, fetch: { _ in (ad, self.media) }, advance: { _ in XCTFail("Deadline already expired") }, wait: { _ in XCTFail("Deadline already expired") })
            XCTFail("An uncleared ad window must not be returned")
        } catch AudioStreamError.unsupportedFormat(let detail) {
            XCTAssertEqual(detail, "startup advertisement did not clear")
        }
    }

    func testCancellationDuringWaitNeverHandsAnAdSessionToPlayer() async throws {
        let ad = try advertisement()
        do {
            _ = try await HLSStartupResolver.resolve(media, fetch: { _ in (ad, self.media) }, advance: { _ in }, wait: { _ in throw CancellationError() })
            XCTFail("Cancellation must propagate")
        } catch is CancellationError { }
    }

    func testWaitsForProgrammeThenAdvancesEachSegmentAtMostOnce() async throws {
        let ad = try advertisement()
        let allAds = Data("#EXTM3U\n#EXTINF:10,Advertisement\n1.aac\n".utf8)
        var polls = 0
        var advances: [URL] = []
        _ = try await HLSStartupResolver.resolve(media, fetch: { _ in
            polls += 1
            let data = polls == 1 ? allAds : (polls <= 3 ? ad : self.programme)
            return (data, self.media)
        }, advance: { advances.append($0) }, wait: { _ in
            if polls > 5 { throw AudioStreamError.stalled }
        })
        XCTAssertEqual(polls, 4)
        XCTAssertEqual(advances, [media.deletingLastPathComponent().appendingPathComponent("4.aac")])
    }
}
