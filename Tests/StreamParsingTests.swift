import Foundation
import XCTest
#if canImport(KUSCCore)
@testable import KUSCCore
#else
@testable import KUSC_SE
#endif

final class HLSManifestTests: XCTestCase {
    private let base = URL(string: "https://stream.example.test/live/playlist.m3u8")!
    private func parse(_ text: String, previous: HLSManifest? = nil) throws -> HLSManifest {
        try HLSManifest.parse(Data(text.utf8), baseURL: base, previous: previous)
    }

    private func window(_ range: ClosedRange<Int>, anchor: String? = nil, duration: String = "9.98458",
                        epoch: Int = 0, prefix: String = "") -> String {
        var lines = ["#EXTM3U", "#EXT-X-MEDIA-SEQUENCE:\(range.lowerBound)",
                     "#EXT-X-DISCONTINUITY-SEQUENCE:\(epoch)", "#EXT-X-TARGETDURATION:10"]
        if let anchor { lines.append("#EXT-X-PROGRAM-DATE-TIME:\(anchor)") }
        for sequence in range { lines += ["#EXTINF:\(duration),", "\(prefix)\(sequence).aac"] }
        return lines.joined(separator: "\n")
    }

    func testProgrammeDateTimePropagatesAcrossSegmentBoundaries() throws {
        let manifest = try parse("""
        #EXTM3U
        #EXT-X-TARGETDURATION:10
        #EXT-X-MEDIA-SEQUENCE:400
        #EXT-X-PROGRAM-DATE-TIME:2026-09-19T12:00:00.500Z
        #EXTINF:9.5,
        400.aac
        #EXTINF:10,
        401.aac
        #EXT-X-ENDLIST
        """)
        XCTAssertEqual(manifest.targetDuration, 10)
        XCTAssertTrue(manifest.ended)
        XCTAssertEqual(manifest.segments.map(\.sequence), [400, 401])
        XCTAssertEqual(manifest.segments[0].url.absoluteString, "https://stream.example.test/live/400.aac")
        XCTAssertNotNil(manifest.segments[0].start)
        XCTAssertEqual(manifest.segments[1].start, manifest.segments[0].end)
        XCTAssertEqual(manifest.segments[1].start!.timeIntervalSince(manifest.segments[0].start!), 9.5)
    }

    func testNewProgrammeDateTimeReanchorsAfterDiscontinuity() throws {
        let manifest = try parse("""
        #EXTM3U
        #EXT-X-PROGRAM-DATE-TIME:2026-09-19T12:00:00Z
        #EXTINF:10,
        a.aac
        #EXT-X-DISCONTINUITY
        #EXT-X-PROGRAM-DATE-TIME:2026-09-19T12:01:00Z
        #EXTINF:10,
        b.aac
        """)
        XCTAssertEqual(manifest.segments[1].start!.timeIntervalSince(manifest.segments[0].start!), 60)
        XCTAssertTrue(manifest.segments[1].discontinuity)
        XCTAssertFalse(manifest.segments[0].discontinuity)
    }

    func testDiscontinuityWithoutNewStationClockDoesNotInventTimestamp() throws {
        let manifest = try parse("""
        #EXTM3U
        #EXT-X-PROGRAM-DATE-TIME:2026-09-19T12:00:00Z
        #EXTINF:10,
        a.aac
        #EXT-X-DISCONTINUITY
        #EXTINF:10,
        b.aac
        """)
        XCTAssertNil(manifest.segments[1].start)
        XCTAssertTrue(manifest.segments[1].discontinuity)
    }

    func testPendingExplicitProgrammeDateSurvivesEitherDiscontinuityTagOrder() throws {
        let pdt = "#EXT-X-PROGRAM-DATE-TIME:2026-09-21T00:00:14Z"
        let discontinuity = "#EXT-X-DISCONTINUITY"
        for tags in [[pdt, discontinuity], [discontinuity, pdt]] {
            let manifest = try parse((["#EXTM3U", "#EXT-X-MEDIA-SEQUENCE:4"] + tags +
                ["#EXTINF:7,", "4.aac"]).joined(separator: "\n"))
            XCTAssertEqual(manifest.segments[0].start, ISO8601DateFormatter().date(from: "2026-09-21T00:00:14Z"))
            XCTAssertTrue(manifest.segments[0].discontinuity)
            XCTAssertEqual(manifest.segments[0].discontinuitySequence, 1)
        }
    }

    func testRollingWindowsKeepTheDeviceReportsFractionalClockAfterAnchorEviction() throws {
        let origin = Date(timeIntervalSince1970: 1_789_924_548)
        let anchor = ISO8601DateFormatter().string(from: origin)
        var manifest = try parse(window(1...3, anchor: anchor))
        XCTAssertEqual(manifest.segments[1].start!.timeIntervalSince1970, 1_789_924_557.98458, accuracy: 0.000_001)
        XCTAssertEqual(manifest.segments[2].start!.timeIntervalSince1970, 1_789_924_567.96916, accuracy: 0.000_001)
        manifest = try parse(window(2...4), previous: manifest)
        XCTAssertEqual(manifest.segments[2].start!.timeIntervalSince1970, 1_789_924_577.9537401, accuracy: 0.000_001)
        // More than one reload proves the newly resolved edge becomes the next
        // bounded manifest's evidence, without a global history or wall clock.
        for lower in 3...40 {
            manifest = try parse(window(lower...(lower + 2)), previous: manifest)
            XCTAssertTrue(manifest.segments.allSatisfy { $0.start != nil })
            XCTAssertEqual(manifest.segments[0].start!.timeIntervalSince(origin),
                           Double(lower - 1) * 9.98458, accuracy: 0.000_02)
            XCTAssertEqual(manifest.segments.last!.end!.timeIntervalSince(origin),
                           Double(lower + 2) * 9.98458, accuracy: 0.000_02)
            XCTAssertEqual(manifest.segments.count, 3)
        }
    }

    func testNoPreviousManifestAndNoOverlapCannotInventDates() throws {
        let previous = try parse(window(1...3, anchor: "2026-09-21T00:00:00Z"))
        XCTAssertTrue(try parse(window(2...4)).segments.allSatisfy { $0.start == nil })
        for range in [4...6, 7...9] {
            XCTAssertTrue(try parse(window(range), previous: previous).segments.allSatisfy { $0.start == nil },
                          "Neither adjacent nor skipped windows prove a shared media identity")
        }
    }

    func testChangedOverlappingIdentityOrDurationRejectsAllCachedClockReuse() throws {
        let previous = try parse(window(1...3, anchor: "2026-09-21T00:00:00Z"))
        let changedURL = window(2...4).replacingOccurrences(of: "2.aac", with: "replacement-2.aac")
        let changedDuration = window(2...4).replacingOccurrences(of: "#EXTINF:9.98458,\n2.aac", with: "#EXTINF:9.5,\n2.aac")
        for text in [changedURL, changedDuration] {
            let manifest = try parse(text, previous: previous)
            XCTAssertTrue(manifest.segments.allSatisfy { $0.start == nil }, "Partial matching overlap must not hide changed media")
        }
    }

    func testSequenceResetOrPlaylistIdentityChangeCannotInheritClock() throws {
        let previous = try parse(window(2...4, anchor: "2026-09-21T00:00:00Z"))
        // Retain matching URLs in the overlap to prove the regressing window
        // itself blocks reuse, rather than an incidental filename mismatch.
        XCTAssertTrue(try parse(window(1...3), previous: previous).segments.allSatisfy { $0.start == nil })
        let otherURL = URL(string: "https://stream.example.test/live/another-session.m3u8")!
        let anotherSession = try HLSManifest.parse(Data(window(3...5).utf8), baseURL: otherURL, previous: previous)
        XCTAssertTrue(anotherSession.segments.allSatisfy { $0.start == nil })
    }

    func testExplicitFreshProgrammeDateOverridesCachedOverlap() throws {
        let previous = try parse(window(1...3, anchor: "2026-09-21T00:00:00Z"))
        let fresh = try parse(window(2...4, anchor: "2026-09-21T00:02:00Z"), previous: previous)
        XCTAssertEqual(fresh.segments[0].start, ISO8601DateFormatter().date(from: "2026-09-21T00:02:00Z"))
        XCTAssertEqual(fresh.segments[1].start, fresh.segments[0].end)
        XCTAssertEqual(fresh.segments[2].start, fresh.segments[1].end)
        XCTAssertNotEqual(fresh.segments[0].start, previous.segments[1].start)
    }

    func testConflictingLaterProgrammeDateDoesNotMixWithCachedPrefix() throws {
        let previous = try parse(window(1...3, anchor: "2026-09-21T00:00:00Z", duration: "10"))
        let current = window(2...4, duration: "10").replacingOccurrences(of: "#EXTINF:10,\n3.aac",
            with: "#EXT-X-PROGRAM-DATE-TIME:2026-09-21T00:00:30Z\n#EXTINF:10,\n3.aac")
        let fresh = try parse(current, previous: previous)
        XCTAssertNil(fresh.segments[0].start, "A conflicting fresh anchor cannot share an inferred cached prefix")
        XCTAssertEqual(fresh.segments[1].start, ISO8601DateFormatter().date(from: "2026-09-21T00:00:30Z"))
        XCTAssertEqual(fresh.segments[2].start, fresh.segments[1].end)
    }

    func testKnownDiscontinuityAnchorSurvivesProgrammeDateRemoval() throws {
        let boundary = "#EXT-X-DISCONTINUITY\n"
        let initial = window(1...3, anchor: "2026-09-21T00:00:00Z").replacingOccurrences(
            of: "#EXTINF:9.98458,\n2.aac",
            with: boundary + "#EXT-X-PROGRAM-DATE-TIME:2026-09-21T00:01:00Z\n#EXTINF:9.98458,\n2.aac")
        let previous = try parse(initial)
        let current = window(2...4).replacingOccurrences(of: "#EXTINF:9.98458,\n2.aac",
                                                        with: boundary + "#EXTINF:9.98458,\n2.aac")
        let fresh = try parse(current, previous: previous)
        XCTAssertTrue(fresh.segments[0].discontinuity)
        XCTAssertEqual(fresh.segments[0].start, previous.segments[1].start)
        XCTAssertEqual(fresh.segments[1].start, previous.segments[2].start)
        XCTAssertEqual(fresh.segments[2].start, fresh.segments[1].end)
        XCTAssertTrue(fresh.segments.allSatisfy { $0.discontinuitySequence == 1 && $0.start != nil })
    }

    func testUndatedNewDiscontinuityStopsForwardClockPropagation() throws {
        let previous = try parse(window(1...3, anchor: "2026-09-21T00:00:00Z"))
        let text = window(2...5).replacingOccurrences(of: "#EXTINF:9.98458,\n4.aac",
                                                   with: "#EXT-X-DISCONTINUITY\n#EXTINF:9.98458,\n4.aac")
        let manifest = try parse(text, previous: previous)
        XCTAssertEqual(manifest.segments[0].start, previous.segments[1].start)
        XCTAssertEqual(manifest.segments[1].start, previous.segments[2].start)
        XCTAssertNil(manifest.segments[2].start)
        XCTAssertNil(manifest.segments[3].start)
        XCTAssertNil(manifest.segments.last?.end)
    }

    func testChangedDiscontinuityEpochOrNewBoundaryOnOverlapRejectsCachedDates() throws {
        let previous = try parse(window(1...3, anchor: "2026-09-21T00:00:00Z", epoch: 2))
        let changedEpoch = window(2...4, epoch: 3)
        let newBoundary = window(2...4, epoch: 2).replacingOccurrences(of: "#EXTINF:9.98458,\n3.aac",
                                                                    with: "#EXT-X-DISCONTINUITY\n#EXTINF:9.98458,\n3.aac")
        for text in [changedEpoch, newBoundary] {
            XCTAssertTrue(try parse(text, previous: previous).segments.allSatisfy { $0.start == nil })
        }
    }

    func testDiscontinuityEpochSurvivesWhenBoundaryLeavesWindow() throws {
        let initial = """
        #EXTM3U
        #EXT-X-MEDIA-SEQUENCE:1
        #EXT-X-DISCONTINUITY-SEQUENCE:0
        #EXT-X-PROGRAM-DATE-TIME:2026-09-21T00:00:00Z
        #EXTINF:9.98458,
        1.aac
        #EXT-X-DISCONTINUITY
        #EXT-X-PROGRAM-DATE-TIME:2026-09-21T00:01:00Z
        #EXTINF:9.98458,
        2.aac
        #EXTINF:9.98458,
        3.aac
        """
        let previous = try parse(initial)
        let fresh = try parse(window(3...5, epoch: 1), previous: previous)
        XCTAssertEqual(fresh.segments[0].start, previous.segments[2].start)
        XCTAssertTrue(fresh.segments.allSatisfy { $0.discontinuitySequence == 1 && $0.start != nil })
        XCTAssertEqual(fresh.segments[2].start, fresh.segments[1].end)
    }

    func testMasterVariantsPreserveBandwidthForHighestQualitySelection() throws {
        let manifest = try parse("""
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS="mp4a.40.2"
        low/index.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=256000,CODECS="mp4a.40.2"
        high/index.m3u8
        """)
        XCTAssertEqual(manifest.variants.map(\.bandwidth), [64_000, 256_000])
        let best = manifest.variants.max { $0.bandwidth < $1.bandwidth }
        XCTAssertEqual(best?.url.absoluteString, "https://stream.example.test/live/high/index.m3u8")
        XCTAssertTrue(manifest.segments.isEmpty)
    }

    func testUndatedPlaylistDoesNotInventReliableStationTime() throws {
        let manifest = try parse("#EXTM3U\n#EXTINF:10,\na.aac")
        XCTAssertNil(manifest.segments[0].start)
        XCTAssertNil(manifest.segments[0].end)
    }

    func testUnsupportedTransportAndMalformedDurationsFailSafely() {
        let invalid = [
            "not a playlist",
            "#EXTM3U\n",
            "#EXTM3U\n#EXTINF:\na.aac",
            "#EXTM3U\n#EXTINF:nan,\na.aac",
            "#EXTM3U\n#EXTINF:-1,\na.aac",
            "#EXTM3U\n#EXTINF:61,\na.aac",
            "#EXTM3U\n#EXTINF:10,\nhttp://stream.example.test/a.aac",
            "#EXTM3U\n#EXT-X-PROGRAM-DATE-TIME:invalid\n#EXTINF:10,\na.aac",
            "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"key\"\n#EXTINF:10,\na.aac",
            "#EXTM3U\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXTINF:10,\na.m4s",
            "#EXTM3U\n#EXT-X-BYTERANGE:100@0\n#EXTINF:10,\na.aac"
        ]
        for text in invalid { XCTAssertThrowsError(try parse(text), text) }
    }
}

final class ADTSParserTests: XCTestCase {
    // One structurally valid 11-byte, 44.1 kHz AAC-LC stereo transport frame.
    // Decoder validity is device-tested separately; these tests concern transport framing.
    private let frame = Data([0xff, 0xf1, 0x50, 0x80, 0x01, 0x7f, 0xfc, 0, 0, 0, 0])

    func testArbitrarilySplitFramesAreReassembledWithoutLossOrDuplication() throws {
        var parser = ADTSParser()
        var parsed: [ADTSFrame] = []
        for byte in frame + frame { parsed.append(contentsOf: try parser.append(Data([byte]))) }
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].bytes, frame)
        XCTAssertEqual(parsed[1].bytes, frame)
        XCTAssertEqual(parsed[0].duration, 1024 / 44_100, accuracy: 0.000_000_1)
    }

    func testParserResynchronizesAfterNonAudioPrefix() throws {
        var parser = ADTSParser()
        let result = try parser.append(Data("ID3 prefix".utf8) + frame)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].bytes, frame)
    }

    func testUnboundedGarbageOrOversizedChunksFail() {
        var parser = ADTSParser()
        XCTAssertThrowsError(try parser.append(Data(repeating: 0, count: 70_000)))
        var freshParser = ADTSParser()
        XCTAssertThrowsError(try freshParser.append(Data(repeating: 0, count: 2 * 1_024 * 1_024 + 1)))
    }

    func testICYMetadataIsRemovedEvenWhenLengthAndMetadataAreSplitAcrossChunks() {
        var filter = ICYAudioFilter(metadataInterval: 3)
        let source = Data("abc".utf8) + Data([1]) + Data(repeating: 120, count: 16)
            + Data("def".utf8) + Data([0]) + Data("ghi".utf8)
        var audio = Data()
        for byte in source { audio.append(filter.append(Data([byte]))) }
        XCTAssertEqual(String(data: audio, encoding: .utf8), "abcdefghi")
    }

    func testNoICYIntervalPreservesAllAudioBytes() {
        for interval in [nil, 0, -1] as [Int?] {
            var filter = ICYAudioFilter(metadataInterval: interval)
            XCTAssertEqual(filter.append(frame), frame)
        }
    }
}
