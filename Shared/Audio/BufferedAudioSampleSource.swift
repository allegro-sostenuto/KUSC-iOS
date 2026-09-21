import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation

/// The worker hands off immutable compressed packets. No reader, decoder, or
/// mutable media state crosses into the renderer's execution context.
struct BufferedAudioSamples: @unchecked Sendable {
    let buffers: [CMSampleBuffer]
    let duration: CMTime
}

enum BufferedAudioSampleSource {
    private static let maximumBytes = 2 * 1024 * 1024
    private static let maximumBuffers = 16_384
    // Match the ingest validator's 1% packet-duration tolerance at the maximum
    // permitted 60-second EXTINF; whole AAC frames can straddle that boundary.
    private static let maximumDuration: Double = 60.6

    /// Demuxes one bounded local ADTS segment without instantiating an AAC
    /// decoder. Reading and packet copying stay off the main/render queue.
    static func load(url: URL) async throws -> BufferedAudioSamples {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try read(url: url)
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            worker.cancel()
        }
    }

    private static func read(url: URL) throws -> BufferedAudioSamples {
        try Task.checkCancellation()
        guard url.isFileURL else { throw AudioStreamError.unsupportedFormat("buffered audio must be a local file") }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= maximumBytes else {
            throw AudioStreamError.storageLimit
        }
        var opened: AudioFileID?
        let openStatus = AudioFileOpenURL(url as CFURL, .readPermission, kAudioFileAAC_ADTSType, &opened)
        guard openStatus == noErr, let file = opened else { throw failure("open audio file", status: openStatus) }
        defer { AudioFileClose(file) }
        try Task.checkCancellation()

        var asbd = AudioStreamBasicDescription()
        var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let formatStatus = AudioFileGetProperty(file, kAudioFilePropertyDataFormat, &asbdSize, &asbd)
        guard formatStatus == noErr, Int(asbdSize) == MemoryLayout<AudioStreamBasicDescription>.size else {
            throw failure("file audio format", status: formatStatus)
        }
        guard [kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2].contains(asbd.mFormatID),
              asbd.mSampleRate.isFinite, asbd.mSampleRate > 0,
              asbd.mSampleRate.rounded() == asbd.mSampleRate, asbd.mSampleRate <= Double(Int32.max),
              asbd.mChannelsPerFrame > 0 else {
            throw failure("AAC stream format", detail: "id=\(asbd.mFormatID) rate=\(asbd.mSampleRate)")
        }
        let timescale = CMTimeScale(asbd.mSampleRate)
        let cookie = try optionalProperty(file, id: kAudioFilePropertyMagicCookieData)
        let layout = try optionalProperty(file, id: kAudioFilePropertyChannelLayout)
        var description: CMAudioFormatDescription?
        let descriptionStatus = cookie.withUnsafeBytes { cookieBytes in
            layout.withUnsafeBytes { layoutBytes in
                CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd,
                    layoutSize: layout.count, layout: layout.isEmpty ? nil : layoutBytes.baseAddress?.assumingMemoryBound(to: AudioChannelLayout.self),
                    magicCookieSize: cookie.count, magicCookie: cookie.isEmpty ? nil : cookieBytes.baseAddress, extensions: nil,
                    formatDescriptionOut: &description)
            }
        }
        guard descriptionStatus == noErr, let description else {
            throw failure("create audio format", status: descriptionStatus)
        }

        var maximumPacketSize: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        let sizeStatus = AudioFileGetProperty(file, kAudioFilePropertyPacketSizeUpperBound, &propertySize, &maximumPacketSize)
        guard sizeStatus == noErr, Int(propertySize) == MemoryLayout<UInt32>.size else {
            throw failure("maximum packet size", status: sizeStatus)
        }
        // Keep temporary reads below 64 KiB; ADTS packets themselves have a
        // 13-bit length. Retained compressed payload remains capped at 2 MiB.
        guard maximumPacketSize > 0, maximumPacketSize <= 64 * 1024 else { throw AudioStreamError.storageLimit }
        let batchCount = min(64, (64 * 1024) / Int(maximumPacketSize))
        let capacity = batchCount * Int(maximumPacketSize)
        var readBytes = Data(count: capacity)
        var packetIndex: Int64 = 0
        var totalFrames: Int64 = 0
        var byteCount = 0
        var buffers: [CMSampleBuffer] = []
        while true {
            try Task.checkCancellation()
            var byteSize = UInt32(capacity)
            var packetCount = UInt32(batchCount)
            var packets = [AudioStreamPacketDescription](repeating: AudioStreamPacketDescription(), count: batchCount)
            let status = readBytes.withUnsafeMutableBytes { memory in
                AudioFileReadPacketData(file, false, &byteSize, &packets, packetIndex, &packetCount, memory.baseAddress)
            }
            guard status == noErr || status == kAudioFileEndOfFileError else {
                throw failure("read compressed packets", status: status, detail: "packet=\(packetIndex)")
            }
            guard Int(packetCount) <= batchCount, Int(byteSize) <= capacity else { throw failure("packet read bounds") }
            if packetCount == 0 {
                guard byteSize == 0 else { throw failure("empty packet read with payload") }
                break
            }
            guard Int(packetCount) <= maximumBuffers - Int(packetIndex), byteSize > 0 else {
                throw AudioStreamError.storageLimit
            }
            packets.removeLast(batchCount - Int(packetCount))
            if asbd.mBytesPerPacket > 0, asbd.mFramesPerPacket > 0 {
                for index in packets.indices {
                    packets[index] = AudioStreamPacketDescription(mStartOffset: Int64(index) * Int64(asbd.mBytesPerPacket),
                        mVariableFramesInPacket: asbd.mFramesPerPacket, mDataByteSize: asbd.mBytesPerPacket)
                }
            }
            var payload = Data()
            var batchFrames: Int64 = 0
            var previousPacketEnd = 0
            for index in packets.indices {
                let packet = packets[index]
                guard packet.mStartOffset >= Int64(previousPacketEnd), packet.mStartOffset <= Int64(byteSize),
                      packet.mDataByteSize > 0, Int(packet.mDataByteSize) <= Int(byteSize) - Int(packet.mStartOffset) else {
                    throw failure("compressed packet byte range", detail: "packet=\(packetIndex + Int64(index))")
                }
                let frames = packet.mVariableFramesInPacket > 0 ? packet.mVariableFramesInPacket : asbd.mFramesPerPacket
                guard frames > 0 else { throw failure("compressed packet frame count") }
                let start = Int(packet.mStartOffset)
                previousPacketEnd = start + Int(packet.mDataByteSize)
                // Pack only declared packet bytes; transport headers/padding
                // never become sample data or alter the decoder configuration.
                packets[index].mStartOffset = Int64(payload.count)
                payload.append(readBytes[start..<previousPacketEnd])
                batchFrames += Int64(frames)
            }
            guard payload.count <= maximumBytes - byteCount else { throw AudioStreamError.storageLimit }
            let end = CMTime(value: totalFrames + batchFrames, timescale: timescale)
            guard finite(end), end.seconds <= maximumDuration else { throw AudioStreamError.storageLimit }
            let buffer = try makeBuffer(payload: payload, packets: packets, description: description,
                                        start: CMTime(value: totalFrames, timescale: timescale))
            let expectedDuration = CMTime(value: batchFrames, timescale: timescale)
            guard finite(CMSampleBufferGetDuration(buffer)),
                  abs(CMTimeSubtract(CMSampleBufferGetDuration(buffer), expectedDuration).seconds) < 0.000_001 else {
                throw failure("constructed packet timing")
            }
            buffers.append(buffer)
            byteCount += payload.count
            totalFrames += batchFrames
            packetIndex += Int64(packetCount)
            if status == kAudioFileEndOfFileError { break }
        }
        try Task.checkCancellation()
        guard !buffers.isEmpty, totalFrames > 0 else { throw failure("empty compressed reader output") }
        return BufferedAudioSamples(buffers: buffers, duration: CMTime(value: totalFrames, timescale: timescale))
    }

    private static func optionalProperty(_ file: AudioFileID, id: AudioFilePropertyID) throws -> Data {
        var size: UInt32 = 0
        let infoStatus = AudioFileGetPropertyInfo(file, id, &size, nil)
        if infoStatus == kAudioFileUnsupportedPropertyError { return Data() }
        guard infoStatus == noErr else { throw failure("audio property size", status: infoStatus, detail: "id=\(id)") }
        guard size <= 64 * 1024 else { throw AudioStreamError.storageLimit }
        guard size > 0 else { return Data() }
        var bytes = Data(count: Int(size))
        let status = bytes.withUnsafeMutableBytes { memory in AudioFileGetProperty(file, id, &size, memory.baseAddress!) }
        guard status == noErr, Int(size) <= bytes.count else { throw failure("audio property data", status: status, detail: "id=\(id)") }
        return Data(bytes.prefix(Int(size)))
    }

    private static func makeBuffer(payload: Data, packets: [AudioStreamPacketDescription],
                                   description: CMAudioFormatDescription, start: CMTime) throws -> CMSampleBuffer {
        var block: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: payload.count, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: payload.count, flags: 0, blockBufferOut: &block)
        guard blockStatus == noErr, let block else { throw failure("allocate packet block", status: blockStatus) }
        let copied = payload.withUnsafeBytes { memory in
            CMBlockBufferReplaceDataBytes(with: memory.baseAddress!, blockBuffer: block,
                                          offsetIntoDestination: 0, dataLength: memory.count)
        }
        guard copied == noErr else { throw failure("copy packet bytes", status: copied) }
        var buffer: CMSampleBuffer?
        let status = packets.withUnsafeBufferPointer { pointer in
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault, dataBuffer: block,
                formatDescription: description, sampleCount: packets.count, presentationTimeStamp: start,
                packetDescriptions: pointer.baseAddress, sampleBufferOut: &buffer)
        }
        guard status == noErr, let buffer else { throw failure("create sized AAC buffer", status: status) }
        guard CMSampleBufferGetNumSamples(buffer) == packets.count,
              CMSampleBufferGetTotalSampleSize(buffer) == payload.count else {
            throw failure("constructed packet sizes")
        }
        // Storage cuts have no priming/trim/reset attachments: every packet is
        // represented once and all segments feed one continuous AAC decoder.
        return buffer
    }

    /// Core Media copies timing while retaining the original compressed data,
    /// format (including HE-AAC configuration), packet sizes and attachments.
    static func retimed(_ buffer: CMSampleBuffer, by offset: CMTime) throws -> CMSampleBuffer {
        guard finite(offset) else { throw failure("retime offset") }
        var count = 0
        let queryStatus = CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: 0, arrayToFill: nil,
                                                                entriesNeededOut: &count)
        guard queryStatus == noErr, count > 0, count <= maximumBuffers else {
            throw failure("retime timing count", status: queryStatus,
                          detail: "entries=\(count) samples=\(CMSampleBufferGetNumSamples(buffer))")
        }
        var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(duration: .invalid,
            presentationTimeStamp: .invalid, decodeTimeStamp: .invalid), count: count)
        let timingStatus = CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: count, arrayToFill: &timings,
                                                                 entriesNeededOut: nil)
        guard timingStatus == noErr else { throw failure("retime timing array", status: timingStatus) }
        for index in timings.indices {
            guard finite(timings[index].presentationTimeStamp) else { throw failure("retime PTS", detail: "index=\(index)") }
            timings[index].presentationTimeStamp = CMTimeAdd(timings[index].presentationTimeStamp, offset)
            if timings[index].decodeTimeStamp.isValid {
                guard finite(timings[index].decodeTimeStamp) else { throw failure("retime DTS", detail: "index=\(index)") }
                timings[index].decodeTimeStamp = CMTimeAdd(timings[index].decodeTimeStamp, offset)
            }
            guard finite(timings[index].presentationTimeStamp),
                  !timings[index].decodeTimeStamp.isValid || finite(timings[index].decodeTimeStamp) else {
                throw failure("retimed timestamp overflow", detail: "index=\(index)")
            }
        }
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: buffer,
            sampleTimingEntryCount: timings.count, sampleTimingArray: &timings, sampleBufferOut: &copy)
        guard status == noErr, let copy else {
            throw failure("copy with new timing", status: status,
                          detail: "entries=\(timings.count) samples=\(CMSampleBufferGetNumSamples(buffer))")
        }
        return copy
    }

    /// Keeps encoded preroll for the decoder while excluding its old output
    /// from the paused presentation queue. Core Media permits a full-duration
    /// start trim for buffers used only to prime the decoder during a seek.
    /// The source buffer, packet data and encoded timestamps remain unchanged.
    static func preparingForSeek(_ buffer: CMSampleBuffer, at target: CMTime) throws -> CMSampleBuffer {
        let start = CMSampleBufferGetPresentationTimeStamp(buffer)
        let duration = CMSampleBufferGetDuration(buffer)
        guard finite(target), finite(start), finite(duration), duration.seconds > 0,
              CMSampleBufferGetNumSamples(buffer) > 0 else { throw failure("seek trim timing") }
        let offset = CMTimeSubtract(target, start)
        guard finite(offset) else { throw failure("seek trim offset") }
        let trim: CMTime
        if CMTimeCompare(offset, .zero) <= 0 { trim = .zero }
        else if CMTimeCompare(offset, duration) >= 0 { trim = duration }
        else { trim = offset }

        var copied: CMSampleBuffer?
        let status = CMSampleBufferCreateCopy(allocator: kCFAllocatorDefault, sampleBuffer: buffer,
                                             sampleBufferOut: &copied)
        guard status == noErr, let copied else { throw failure("copy seek preroll", status: status) }
        if CMTimeCompare(trim, .zero) > 0 {
            guard let value = CMTimeCopyAsDictionary(trim, allocator: kCFAllocatorDefault) else {
                throw failure("seek trim attachment")
            }
            CMSetAttachment(copied, key: kCMSampleBufferAttachmentKey_TrimDurationAtStart,
                            value: value, attachmentMode: .shouldPropagate)
        } else {
            CMRemoveAttachment(copied, key: kCMSampleBufferAttachmentKey_TrimDurationAtStart)
        }
        return copied
    }

    /// Keeps complete compressed packets which overlap or follow the cutoff.
    /// A seek can provide a bounded amount of decoder preroll without filling
    /// the renderer with an entire earlier file while its timebase is paused.
    /// Retained packets keep their original timestamps and compressed format.
    static func packets(_ buffers: [CMSampleBuffer], endingAfter cutoff: CMTime) throws -> [CMSampleBuffer] {
        guard finite(cutoff) else { throw failure("packet cutoff") }
        var result: [CMSampleBuffer] = []
        var inspectedPackets = 0
        var previousEnd: CMTime?
        for buffer in buffers {
            try Task.checkCancellation()
            let count = CMSampleBufferGetNumSamples(buffer)
            guard count > 0, count <= maximumBuffers - inspectedPackets else { throw failure("packet suffix count") }
            inspectedPackets += count
            var firstKept: Int?
            for index in 0..<count {
                var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid)
                let status = CMSampleBufferGetSampleTimingInfo(buffer, at: index, timingInfoOut: &timing)
                guard status == noErr else { throw failure("packet suffix timing", status: status) }
                guard finite(timing.presentationTimeStamp), finite(timing.duration), timing.duration.seconds > 0 else {
                    throw failure("packet suffix timestamp", detail: "index=\(index)")
                }
                let end = CMTimeAdd(timing.presentationTimeStamp, timing.duration)
                guard finite(end) else { throw failure("packet suffix end", detail: "index=\(index)") }
                if let previousEnd, abs(CMTimeSubtract(timing.presentationTimeStamp, previousEnd).seconds) > 0.000_001 {
                    throw failure("packet suffix continuity", detail: "index=\(index)")
                }
                previousEnd = end
                if firstKept == nil, CMTimeCompare(end, cutoff) > 0 { firstKept = index }
            }
            guard let firstKept else { continue }
            if firstKept == 0 { result.append(buffer) }
            else {
                var copy: CMSampleBuffer?
                let status = CMSampleBufferCopySampleBufferForRange(allocator: kCFAllocatorDefault, sampleBuffer: buffer,
                    sampleRange: CFRange(location: firstKept, length: count - firstKept), sampleBufferOut: &copy)
                guard status == noErr, let copy else { throw failure("copy packet suffix", status: status) }
                result.append(copy)
            }
        }
        return result
    }

    private static func finite(_ time: CMTime) -> Bool {
        time.isValid && !time.isIndefinite && time.seconds.isFinite
    }

    private static func failure(_ stage: String, status: OSStatus? = nil, detail: String = "") -> NSError {
        // Numeric media properties and operation names only: no file paths,
        // request URLs, sample bytes, or arbitrary AVFoundation userInfo.
        NSError(domain: "KUSC.BufferedAudioSampleSource", code: Int(status ?? -1),
                userInfo: [NSLocalizedDescriptionKey: "Buffered AAC \(stage) failed. \(detail)"])
    }
}
