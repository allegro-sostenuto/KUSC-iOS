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
        let packetPayloads: [Data]
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
        let packetPayloads = frames.map { frame -> Data in
            let headerLength = frame.bytes[1] & 1 == 1 ? 7 : 9
            return Data(frame.bytes.dropFirst(headerLength))
        }
        return Files(whole: whole, segments: segments, segmentDurations: durations, packetPayloads: packetPayloads)
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
        try packetPayloads(buffers).reduce(into: Data()) { $0.append($1) }
    }

    /// AudioStreamPacketDescription defines the actual compressed byte ranges.
    /// A CMBlockBuffer's backing bytes may also include bytes outside packets.
    static func packetPayloads(_ buffers: [CMSampleBuffer]) throws -> [Data] {
        var result: [Data] = []
        for buffer in buffers {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { throw AudioStreamError.invalidAAC }
            let blockSize = CMBlockBufferGetDataLength(block)
            let count = CMSampleBufferGetNumSamples(buffer)
            var descriptions: UnsafePointer<AudioStreamPacketDescription>?
            var size = 0
            let status = CMSampleBufferGetAudioStreamPacketDescriptionsPtr(buffer,
                packetDescriptionsPointerOut: &descriptions, sizeOut: &size)
            guard status == noErr, count > 0 else {
                throw NSError(domain: "KUSC.Tests.CompressedPackets", code: Int(status), userInfo: [
                    NSLocalizedDescriptionKey: "Packet description lookup failed: status=\(status) samples=\(count) blockBytes=\(blockSize) sampleBytes=\(CMSampleBufferGetTotalSampleSize(buffer))"
                ])
            }
            let packets: [AudioStreamPacketDescription]
            if let descriptions {
                guard size == count * MemoryLayout<AudioStreamPacketDescription>.stride else { throw AudioStreamError.invalidAAC }
                packets = Array(UnsafeBufferPointer(start: descriptions, count: count))
            } else {
                guard let format = CMSampleBufferGetFormatDescription(buffer),
                      let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
                      asbd.mBytesPerPacket > 0, count <= blockSize / Int(asbd.mBytesPerPacket) else { throw AudioStreamError.invalidAAC }
                packets = (0..<count).map { index in
                    AudioStreamPacketDescription(mStartOffset: Int64(index * Int(asbd.mBytesPerPacket)),
                        mVariableFramesInPacket: asbd.mFramesPerPacket, mDataByteSize: asbd.mBytesPerPacket)
                }
            }
            for packet in packets {
                guard packet.mStartOffset >= 0, packet.mStartOffset <= Int64(blockSize), packet.mDataByteSize > 0,
                      Int(packet.mDataByteSize) <= blockSize - Int(packet.mStartOffset) else { throw AudioStreamError.invalidAAC }
                var bytes = Data(count: Int(packet.mDataByteSize))
                let copied = bytes.withUnsafeMutableBytes { memory in
                    CMBlockBufferCopyDataBytes(block, atOffset: Int(packet.mStartOffset), dataLength: memory.count,
                                               destination: memory.baseAddress!)
                }
                guard copied == noErr else { throw AudioStreamError.invalidAAC }
                result.append(bytes)
            }
        }
        return result
    }

    static func rawPayload(_ buffers: [CMSampleBuffer]) throws -> Data {
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

    static func difference(_ lhs: [Data], _ rhs: [Data]) -> String {
        guard lhs.count == rhs.count else { return "packet counts \(lhs.count) vs \(rhs.count)" }
        guard let index = lhs.indices.first(where: { lhs[$0] != rhs[$0] }) else { return "none" }
        let left = [UInt8](lhs[index]), right = [UInt8](rhs[index])
        let offset = (0..<min(left.count, right.count)).first(where: { left[$0] != right[$0] }) ?? min(left.count, right.count)
        let leftBytes = left.dropFirst(max(0, offset - 2)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let rightBytes = right.dropFirst(max(0, offset - 2)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return "packet=\(index) sizes=\(left.count)/\(right.count) firstOffset=\(offset) bytes=\(leftBytes)/\(rightBytes)"
    }

    static func packetSummary(_ buffers: [CMSampleBuffer]) -> String {
        buffers.prefix(5).enumerated().map { index, buffer in
            var descriptions: UnsafePointer<AudioStreamPacketDescription>?
            var size = 0
            let status = CMSampleBufferGetAudioStreamPacketDescriptionsPtr(buffer,
                packetDescriptionsPointerOut: &descriptions, sizeOut: &size)
            let count = size / MemoryLayout<AudioStreamPacketDescription>.stride
            let packets = descriptions.map { Array(UnsafeBufferPointer(start: $0, count: count)) } ?? []
            let ends = packets.prefix(2).map { "\($0.mStartOffset)+\($0.mDataByteSize)" }.joined(separator: ",")
            let blockSize = CMSampleBufferGetDataBuffer(buffer).map { CMBlockBufferGetDataLength($0) } ?? 0
            return "buffer\(index) samples=\(CMSampleBufferGetNumSamples(buffer)) block=\(blockSize) packetStatus=\(status) descriptorBytes=\(size) packetBytes=\(packets.reduce(0) { $0 + Int($1.mDataByteSize) }) firstRanges=\(ends)"
        }.joined(separator: "; ")
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
        XCTAssertTrue(whole.buffers.allSatisfy { CMSampleBufferGetNumSamples($0) > 0 },
                      "File boundaries must not be returned as empty audio samples")
        var joinedPackets: [Data] = []
        var splitBuffers: [CMSampleBuffer] = []
        var joinedDuration = CMTime.zero
        var joinedSampleCount = 0
        for (index, url) in fixture.segments.enumerated() {
            let part = try await BufferedAudioSampleSource.load(url: url)
            XCTAssertFalse(part.buffers.isEmpty)
            XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(part.buffers[0]).seconds, 0, accuracy: 0.000_001)
            XCTAssertEqual(part.duration.seconds, fixture.segmentDurations[index], accuracy: 0.000_001)
            var precedingEnd = CMTime.zero
            for buffer in part.buffers {
                XCTAssertGreaterThan(CMSampleBufferGetNumSamples(buffer), 0,
                                     "A file-end control marker must not become an AAC packet")
                XCTAssertGreaterThan(CMSampleBufferGetTotalSampleSize(buffer), 0,
                                     "Compressed AAC must include sample sizes for packet access and suffix copies")
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
            joinedPackets.append(contentsOf: try BufferedAudioTestFixture.packetPayloads(part.buffers))
            splitBuffers.append(contentsOf: part.buffers)
            joinedDuration = CMTimeAdd(joinedDuration, part.duration)
        }
        let wholePackets = try BufferedAudioTestFixture.packetPayloads(whole.buffers)
        print("Whole packets: \(BufferedAudioTestFixture.packetSummary(whole.buffers))")
        print("Split packets: \(BufferedAudioTestFixture.packetSummary(splitBuffers))")
        print("Raw block comparison: \(BufferedAudioTestFixture.difference([try BufferedAudioTestFixture.rawPayload(splitBuffers)], [try BufferedAudioTestFixture.rawPayload(whole.buffers)]))")
        XCTAssertTrue(joinedPackets == wholePackets,
                      "Split vs whole packet data: \(BufferedAudioTestFixture.difference(joinedPackets, wholePackets))")
        XCTAssertTrue(wholePackets == fixture.packetPayloads,
                      "Whole read vs original ADTS packet data: \(BufferedAudioTestFixture.difference(wholePackets, fixture.packetPayloads))")
        XCTAssertTrue(joinedPackets == fixture.packetPayloads,
                      "Split read vs original ADTS packet data: \(BufferedAudioTestFixture.difference(joinedPackets, fixture.packetPayloads))")
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

    func testPacketSuffixPreservesBytesAndOriginalTimestampsAtEveryCutoff() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try BufferedAudioTestFixture.make(in: directory)
        let samples = try await BufferedAudioSampleSource.load(url: fixture.whole)
        // A nonzero origin proves slicing preserves the renderer's timeline.
        let origin = CMTime(value: 7 * 44_100, timescale: 44_100)
        let buffers = try samples.buffers.map { try BufferedAudioSampleSource.retimed($0, by: origin) }
        let originalPackets = try BufferedAudioTestFixture.packetPayloads(buffers)
        let packetCount = originalPackets.count
        XCTAssertGreaterThan(packetCount, 101)
        let format = try XCTUnwrap(CMSampleBufferGetFormatDescription(buffers[0]))
        let end = CMTimeAdd(origin, samples.duration)
        let cases: [(CMTime, Int)] = [
            (CMTimeSubtract(origin, CMTime(value: 1, timescale: 1)), 0),
            (origin, 0),
            (CMTimeAdd(origin, CMTime(value: 37 * 1024 + 512, timescale: 44_100)), 37),
            (CMTimeAdd(origin, CMTime(value: 38 * 1024, timescale: 44_100)), 38),
            // This also discards an earlier batch before slicing the next one.
            (CMTimeAdd(origin, CMTime(value: 100 * 1024 + 512, timescale: 44_100)), 100),
            (end, packetCount),
            (CMTimeAdd(end, CMTime(value: 1, timescale: 1)), packetCount)
        ]
        for (cutoff, firstIndex) in cases {
            let suffix = try BufferedAudioSampleSource.packets(buffers, endingAfter: cutoff)
            let retainedPackets = try BufferedAudioTestFixture.packetPayloads(suffix)
            let expectedPackets = Array(originalPackets.dropFirst(firstIndex))
            XCTAssertTrue(retainedPackets == expectedPackets,
                          "cutoff=\(cutoff.seconds): \(BufferedAudioTestFixture.difference(retainedPackets, expectedPackets))")
            XCTAssertEqual(suffix.reduce(0) { $0 + CMSampleBufferGetNumSamples($1) }, packetCount - firstIndex)
            if firstIndex == packetCount {
                XCTAssertTrue(suffix.isEmpty)
                continue
            }
            let first = try XCTUnwrap(suffix.first)
            let last = try XCTUnwrap(suffix.last)
            let expectedStart = CMTimeAdd(origin, CMTime(value: Int64(firstIndex * 1024), timescale: 44_100))
            XCTAssertEqual(CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(first), expectedStart), 0)
            XCTAssertEqual(CMTimeCompare(CMTimeAdd(CMSampleBufferGetPresentationTimeStamp(last),
                                                 CMSampleBufferGetDuration(last)), end), 0)
            for buffer in suffix {
                XCTAssertTrue(CMFormatDescriptionEqual(format,
                    otherFormatDescription: try XCTUnwrap(CMSampleBufferGetFormatDescription(buffer))))
                for key in [kCMSampleBufferAttachmentKey_TrimDurationAtStart,
                            kCMSampleBufferAttachmentKey_TrimDurationAtEnd,
                            kCMSampleBufferAttachmentKey_ResetDecoderBeforeDecoding,
                            kCMSampleBufferAttachmentKey_DrainAfterDecoding] {
                    XCTAssertNil(CMGetAttachment(buffer, key: key, attachmentModeOut: nil))
                }
            }
        }
        XCTAssertThrowsError(try BufferedAudioSampleSource.packets(buffers, endingAfter: .invalid))
        XCTAssertThrowsError(try BufferedAudioSampleSource.packets(buffers, endingAfter: .positiveInfinity))
    }

    func testSeekPrerollTrimsOnlyDecodedOutputAndLeavesOriginalPacketsUntouched() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try BufferedAudioTestFixture.make(in: directory)
        let samples = try await BufferedAudioSampleSource.load(url: fixture.whole)
        let first = try XCTUnwrap(samples.buffers.first)
        let origin = CMTime(value: 7 * 44_100, timescale: 44_100)
        let original = try BufferedAudioSampleSource.retimed(first, by: origin)
        let duration = CMSampleBufferGetDuration(original)
        let format = try XCTUnwrap(CMSampleBufferGetFormatDescription(original))
        let packets = try BufferedAudioTestFixture.packetPayloads([original])
        let partial = CMTimeMultiplyByRatio(duration, multiplier: 1, divisor: 2)
        let oneSecond = CMTime(value: 1, timescale: 1)
        let cases: [(offset: CMTime, trim: CMTime)] = [
            (CMTimeMultiply(oneSecond, multiplier: -1), .zero),
            (.zero, .zero),
            (partial, partial),
            (duration, duration),
            (CMTimeAdd(duration, oneSecond), duration)
        ]
        for item in cases {
            let prepared = try BufferedAudioSampleSource.preparingForSeek(original, at: CMTimeAdd(origin, item.offset))
            XCTAssertEqual(try BufferedAudioTestFixture.packetPayloads([prepared]), packets)
            XCTAssertTrue(CMFormatDescriptionEqual(format,
                otherFormatDescription: try XCTUnwrap(CMSampleBufferGetFormatDescription(prepared))))
            XCTAssertEqual(CMSampleBufferGetNumSamples(prepared), CMSampleBufferGetNumSamples(original))
            XCTAssertEqual(CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(prepared), origin), 0)
            XCTAssertEqual(CMTimeCompare(CMSampleBufferGetDuration(prepared), duration), 0)
            XCTAssertEqual(CMTimeCompare(CMSampleBufferGetOutputPresentationTimeStamp(prepared),
                                         CMTimeAdd(origin, item.trim)), 0)
            XCTAssertEqual(CMTimeCompare(CMSampleBufferGetOutputDuration(prepared),
                                         CMTimeSubtract(duration, item.trim)), 0)
            for index in 0..<CMSampleBufferGetNumSamples(original) {
                var before = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid,
                                                decodeTimeStamp: .invalid)
                var after = before
                XCTAssertEqual(CMSampleBufferGetSampleTimingInfo(original, at: index, timingInfoOut: &before), noErr)
                XCTAssertEqual(CMSampleBufferGetSampleTimingInfo(prepared, at: index, timingInfoOut: &after), noErr)
                XCTAssertEqual(CMTimeCompare(before.presentationTimeStamp, after.presentationTimeStamp), 0)
                XCTAssertEqual(CMTimeCompare(before.duration, after.duration), 0)
                XCTAssertEqual(before.decodeTimeStamp.isValid, after.decodeTimeStamp.isValid)
                if before.decodeTimeStamp.isValid {
                    XCTAssertEqual(CMTimeCompare(before.decodeTimeStamp, after.decodeTimeStamp), 0)
                }
            }
            XCTAssertNil(CMGetAttachment(original, key: kCMSampleBufferAttachmentKey_TrimDurationAtStart, attachmentModeOut: nil))
            XCTAssertEqual(CMTimeCompare(CMSampleBufferGetOutputPresentationTimeStamp(original), origin), 0)
            XCTAssertEqual(CMTimeCompare(CMSampleBufferGetOutputDuration(original), duration), 0)
            for key in [kCMSampleBufferAttachmentKey_TrimDurationAtEnd,
                        kCMSampleBufferAttachmentKey_ResetDecoderBeforeDecoding,
                        kCMSampleBufferAttachmentKey_DrainAfterDecoding] {
                XCTAssertNil(CMGetAttachment(prepared, key: key, attachmentModeOut: nil))
            }
        }
        XCTAssertThrowsError(try BufferedAudioSampleSource.preparingForSeek(original, at: .invalid))
        XCTAssertThrowsError(try BufferedAudioSampleSource.preparingForSeek(original, at: .positiveInfinity))
    }

    func testRetimingPacketDescriptionsDoesNotRequireAnAssetReader() throws {
        var asbd = AudioStreamBasicDescription(mSampleRate: 44_100, mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: 0, mBytesPerPacket: 0, mFramesPerPacket: 1024, mBytesPerFrame: 0,
            mChannelsPerFrame: 2, mBitsPerChannel: 0, mReserved: 0)
        var format: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &format), noErr)
        let description = try XCTUnwrap(format)
        let bytes = Data([1, 2, 3, 4, 5, 6]) // Packet contents aren't decoded in this Core Media timing test.
        var block: CMBlockBuffer?
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: bytes.count, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: bytes.count, flags: 0, blockBufferOut: &block), noErr)
        let dataBlock = try XCTUnwrap(block)
        XCTAssertEqual(bytes.withUnsafeBytes { memory in
            CMBlockBufferReplaceDataBytes(with: memory.baseAddress!, blockBuffer: dataBlock,
                                          offsetIntoDestination: 0, dataLength: memory.count)
        }, noErr)
        var packets = [AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 1024, mDataByteSize: 3),
                       AudioStreamPacketDescription(mStartOffset: 3, mVariableFramesInPacket: 1024, mDataByteSize: 3)]
        var original: CMSampleBuffer?
        XCTAssertEqual(CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault,
            dataBuffer: dataBlock, formatDescription: description, sampleCount: packets.count,
            presentationTimeStamp: .zero, packetDescriptions: &packets, sampleBufferOut: &original), noErr)
        let buffer = try XCTUnwrap(original)
        let offset = CMTime(value: 44_100, timescale: 44_100)
        let copy = try BufferedAudioSampleSource.retimed(buffer, by: offset)
        XCTAssertEqual(CMSampleBufferGetNumSamples(copy), 2)
        XCTAssertEqual(CMSampleBufferGetDuration(copy).seconds, 2048.0 / 44_100, accuracy: 0.000_001)
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(copy).seconds, 1, accuracy: 0.000_001)
        XCTAssertEqual(try BufferedAudioTestFixture.payload([copy]), bytes)
        XCTAssertTrue(CMFormatDescriptionEqual(description, otherFormatDescription: CMSampleBufferGetFormatDescription(copy)!))
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
