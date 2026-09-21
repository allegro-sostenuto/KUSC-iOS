// Native media tests use locally encoded AAC, never station audio or networking.
#if DEBUG && canImport(AVFoundation) && !canImport(KUSCCore)
import AVFoundation
import CoreMedia
import Foundation
import XCTest
@testable import KUSC_SE

enum BufferedAudioTestFixture {
    struct Files {
        let whole: URL
        let segments: [URL]
        let segmentDurations: [Double]
        var duration: Double { segmentDurations.reduce(0, +) }
    }

    /// One encoder produces the entire stream. Splitting existing ADTS packets
    /// must not insert fresh encoder priming or throw away an AAC boundary.
    static func make(in directory: URL, segmentCount: Int = 3, duration: Double = 4) throws -> Files {
        guard segmentCount > 0, segmentCount <= 8, duration.isFinite, duration > 0, duration <= 60 else {
            throw AudioStreamError.invalidAAC
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let whole = directory.appendingPathComponent("continuous.aac")
        try encode(to: whole, duration: duration)
        var parser = ADTSParser()
        let frames = try parser.append(Data(contentsOf: whole))
        guard frames.count >= segmentCount else { throw AudioStreamError.invalidAAC }
        var segments: [URL] = []
        var durations: [Double] = []
        for index in 0..<segmentCount {
            let range = (frames.count * index / segmentCount)..<(frames.count * (index + 1) / segmentCount)
            let url = directory.appendingPathComponent("segment-\(index).aac")
            let bytes = frames[range].reduce(into: Data()) { $0.append($1.bytes) }
            try bytes.write(to: url)
            segments.append(url)
            durations.append(frames[range].reduce(0) { $0 + $1.duration })
        }
        return Files(whole: whole, segments: segments, segmentDurations: durations)
    }

    private static func encode(to url: URL, duration: Double) throws {
        // Deinitializing the writer at this function boundary flushes the last
        // encoded packets before the caller splits the resulting ADTS file.
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ])
        let frameCount = AVAudioFrameCount((44_100 * duration).rounded())
        guard let pcm = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount),
              let channels = pcm.floatChannelData else { throw AudioStreamError.invalidAAC }
        pcm.frameLength = frameCount
        for index in 0..<Int(frameCount) {
            let value = Float(sin(Double(index) * 2 * .pi * 440 / 44_100) * 0.2)
            for channel in 0..<Int(pcm.format.channelCount) { channels[channel][index] = value }
        }
        try file.write(from: pcm)
    }

    static func payload(_ buffers: [CMSampleBuffer]) throws -> Data {
        try buffers.reduce(into: Data()) { result, buffer in
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { throw AudioStreamError.invalidAAC }
            var bytes = Data(count: CMBlockBufferGetDataLength(block))
            let status = bytes.withUnsafeMutableBytes { memory in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: memory.count, destination: memory.baseAddress!)
            }
            guard status == noErr else { throw AudioStreamError.invalidAAC }
            result.append(bytes)
        }
    }
}

@MainActor final class BufferedAudioSampleSourceTests: XCTestCase {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("kusc-packets-\(UUID().uuidString)", isDirectory: true)
    }

    func testSplitContinuousAACPreservesEveryCompressedPacketAndUntrimmedDuration() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try BufferedAudioTestFixture.make(in: directory)
        let whole = try await BufferedAudioSampleSource.load(url: fixture.whole)
        var joinedPayload = Data()
        var joinedDuration = CMTime.zero
        var joinedSampleCount = 0
        for (index, url) in fixture.segments.enumerated() {
            let part = try await BufferedAudioSampleSource.load(url: url)
            XCTAssertFalse(part.buffers.isEmpty)
            XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(part.buffers[0]).seconds, 0, accuracy: 0.000_001)
            XCTAssertEqual(part.duration.seconds, fixture.segmentDurations[index], accuracy: 0.000_001)
            var precedingEnd = CMTime.zero
            for buffer in part.buffers {
                XCTAssertEqual(CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(buffer), precedingEnd), 0)
                let description = try XCTUnwrap(CMSampleBufferGetFormatDescription(buffer))
                let asbd = try XCTUnwrap(CMAudioFormatDescriptionGetStreamBasicDescription(description)).pointee
                XCTAssertEqual(asbd.mFormatID, kAudioFormatMPEG4AAC)
                XCTAssertNil(CMGetAttachment(buffer, key: kCMSampleBufferAttachmentKey_TrimDurationAtStart, attachmentModeOut: nil))
                XCTAssertNil(CMGetAttachment(buffer, key: kCMSampleBufferAttachmentKey_TrimDurationAtEnd, attachmentModeOut: nil))
                XCTAssertNil(CMGetAttachment(buffer, key: kCMSampleBufferAttachmentKey_ResetDecoderBeforeDecoding, attachmentModeOut: nil))
                XCTAssertNil(CMGetAttachment(buffer, key: kCMSampleBufferAttachmentKey_DrainAfterDecoding, attachmentModeOut: nil))
                precedingEnd = CMTimeAdd(CMSampleBufferGetPresentationTimeStamp(buffer), CMSampleBufferGetDuration(buffer))
                joinedSampleCount += CMSampleBufferGetNumSamples(buffer)
            }
            joinedPayload.append(try BufferedAudioTestFixture.payload(part.buffers))
            joinedDuration = CMTimeAdd(joinedDuration, part.duration)
        }
        XCTAssertEqual(joinedPayload, try BufferedAudioTestFixture.payload(whole.buffers),
                       "Reading a storage boundary cannot omit priming packets or alter compressed audio")
        XCTAssertEqual(joinedSampleCount, whole.buffers.reduce(0) { $0 + CMSampleBufferGetNumSamples($1) })
        XCTAssertEqual(joinedDuration.seconds, whole.duration.seconds, accuracy: 0.000_001)
        XCTAssertEqual(whole.duration.seconds, fixture.duration, accuracy: 0.000_001)
    }

    func testRetimingPreservesCompressedPayloadFormatAndEveryTimingEntry() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try BufferedAudioTestFixture.make(in: directory)
        let samples = try await BufferedAudioSampleSource.load(url: fixture.segments[0])
        let offset = CMTime(value: 123_456, timescale: 44_100)
        for buffer in samples.buffers {
            let copy = try BufferedAudioSampleSource.retimed(buffer, by: offset)
            XCTAssertEqual(try BufferedAudioTestFixture.payload([copy]), try BufferedAudioTestFixture.payload([buffer]))
            XCTAssertTrue(CMFormatDescriptionEqual(CMSampleBufferGetFormatDescription(buffer)!,
                                                   otherFormatDescription: CMSampleBufferGetFormatDescription(copy)!))
            XCTAssertEqual(CMSampleBufferGetNumSamples(copy), CMSampleBufferGetNumSamples(buffer))
            XCTAssertEqual(CMTimeCompare(CMSampleBufferGetDuration(copy), CMSampleBufferGetDuration(buffer)), 0)
            var count = 0
            XCTAssertEqual(CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count), noErr)
            var before = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid,
                                                                          decodeTimeStamp: .invalid), count: count)
            var after = before
            XCTAssertEqual(CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: count, arrayToFill: &before, entriesNeededOut: nil), noErr)
            XCTAssertEqual(CMSampleBufferGetSampleTimingInfoArray(copy, entryCount: count, arrayToFill: &after, entriesNeededOut: nil), noErr)
            for index in before.indices {
                XCTAssertEqual(CMTimeCompare(after[index].presentationTimeStamp, CMTimeAdd(before[index].presentationTimeStamp, offset)), 0)
                XCTAssertEqual(CMTimeCompare(after[index].duration, before[index].duration), 0)
                if before[index].decodeTimeStamp.isValid {
                    XCTAssertEqual(CMTimeCompare(after[index].decodeTimeStamp, CMTimeAdd(before[index].decodeTimeStamp, offset)), 0)
                } else { XCTAssertFalse(after[index].decodeTimeStamp.isValid) }
            }
        }
    }

    func testSourceRejectsRemoteEmptyMalformedAndOversizedSegments() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls = [URL(string: "https://example.invalid/segment.aac")!]
        for (name, bytes) in [("empty", Data()), ("malformed", Data("not AAC".utf8)),
                              ("oversized", Data(repeating: 0, count: 2 * 1024 * 1024 + 1))] {
            let url = directory.appendingPathComponent(name + ".aac")
            try bytes.write(to: url)
            urls.append(url)
        }
        for url in urls {
            do {
                _ = try await BufferedAudioSampleSource.load(url: url)
                XCTFail("Invalid or unbounded segment unexpectedly produced audio")
            } catch { /* Expected; no network or decoder should be started. */ }
        }
    }

    func testCanceledReadCannotReturnPacketsToAnObsoleteRenderer() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try BufferedAudioTestFixture.make(in: directory)
        let worker = Task { try await BufferedAudioSampleSource.load(url: fixture.whole) }
        worker.cancel()
        do {
            _ = try await worker.value
            XCTFail("A canceled segment read must not supply a replacement renderer")
        } catch is CancellationError { }
    }
}
#endif
