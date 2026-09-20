import Foundation
import XCTest
#if canImport(KUSCCore)
@testable import KUSCCore
#else
@testable import KUSC_SE
#endif

final class HLSManifestTests: XCTestCase {
    private let base = URL(string: "https://stream.example.test/live/playlist.m3u8")!
    private func parse(_ text: String) throws -> HLSManifest {
        try HLSManifest.parse(Data(text.utf8), baseURL: base)
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
