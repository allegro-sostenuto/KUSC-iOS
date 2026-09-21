import AVFoundation
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
            try await read(url: url)
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            worker.cancel()
        }
    }

    private static func read(url: URL) async throws -> BufferedAudioSamples {
        try Task.checkCancellation()
        guard url.isFileURL else { throw AudioStreamError.unsupportedFormat("buffered audio must be a local file") }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= maximumBytes else {
            throw AudioStreamError.storageLimit
        }
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        try Task.checkCancellation()
        guard tracks.count == 1, let track = tracks.first else {
            throw failure("audio tracks", detail: "count=\(tracks.count)")
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = true
        guard reader.canAdd(output) else { throw failure("add compressed reader output") }
        reader.add(output)
        defer { reader.cancelReading() }
        guard reader.startReading() else {
            throw reader.error ?? failure("start reader", detail: "status=\(reader.status.rawValue)")
        }

        var buffers: [CMSampleBuffer] = []
        var firstPTS: CMTime?
        var previousEnd: CMTime?
        var byteCount = 0
        var readCount = 0
        var format: CMFormatDescription?
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard readCount < maximumBuffers else { throw AudioStreamError.storageLimit }
            readCount += 1
            let sampleCount = CMSampleBufferGetNumSamples(buffer)
            let block = CMSampleBufferGetDataBuffer(buffer)
            let blockBytes = block.map { CMBlockBufferGetDataLength($0) } ?? 0
            if sampleCount == 0 {
                // AssetReader emits an empty control buffer at the end of an
                // ADTS file. A storage cut must not drain/reset our continuous
                // decoder, change its clock, or become a fabricated AAC packet.
                // Only a ready marker with no payload can be discarded.
                guard CMSampleBufferDataIsReady(buffer), blockBytes == 0 else {
                    throw failure("empty control buffer", detail: "ready=\(CMSampleBufferDataIsReady(buffer)) bytes=\(blockBytes)")
                }
                continue
            }
            #if DEBUG
            if buffers.isEmpty {
                let description = CMSampleBufferGetFormatDescription(buffer)
                let asbd = description.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
                let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
                let duration = CMSampleBufferGetDuration(buffer)
                print("BufferedAAC first buffer: samples=\(sampleCount) ready=\(CMSampleBufferDataIsReady(buffer)) blockBytes=\(blockBytes) format=\(asbd?.mFormatID ?? 0) rate=\(asbd?.mSampleRate ?? 0) framesPerPacket=\(asbd?.mFramesPerPacket ?? 0) pts=\(pts.value)/\(pts.timescale)/\(pts.flags.rawValue) duration=\(duration.value)/\(duration.timescale)/\(duration.flags.rawValue)")
            }
            #endif
            guard CMSampleBufferDataIsReady(buffer), sampleCount > 0 else {
                throw failure("sample readiness", detail: "ready=\(CMSampleBufferDataIsReady(buffer)) samples=\(sampleCount) buffer=\(buffers.count)")
            }
            guard let block else { throw failure("sample data block") }
            guard let description = CMSampleBufferGetFormatDescription(buffer),
                  let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else {
                throw failure("audio format description")
            }
            guard [kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2].contains(asbd.mFormatID),
                  asbd.mSampleRate.isFinite, asbd.mSampleRate > 0 else {
                throw failure("AAC stream format", detail: "id=\(asbd.mFormatID) rate=\(asbd.mSampleRate)")
            }
            if let format, !CMFormatDescriptionEqual(format, otherFormatDescription: description) {
                throw AudioStreamError.unsupportedFormat("AAC format changed within a segment")
            }
            format = description
            let bytes = CMBlockBufferGetDataLength(block)
            guard bytes > 0, bytes <= maximumBytes - byteCount, buffers.count < maximumBuffers else {
                throw AudioStreamError.storageLimit
            }
            byteCount += bytes
            let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
            let duration = CMSampleBufferGetDuration(buffer)
            guard finite(pts), finite(duration), duration.seconds > 0 else {
                throw failure("sample timing", detail: "buffer=\(buffers.count) samples=\(sampleCount) pts=\(pts.value)/\(pts.timescale) flags=\(pts.flags.rawValue) duration=\(duration.value)/\(duration.timescale) flags=\(duration.flags.rawValue) framesPerPacket=\(asbd.mFramesPerPacket)")
            }
            if let previousEnd, abs(CMTimeSubtract(pts, previousEnd).seconds) > 0.000_001 {
                throw AudioStreamError.unsupportedFormat("noncontiguous AAC packet timing")
            }
            if firstPTS == nil { firstPTS = pts }
            let end = CMTimeAdd(pts, duration)
            guard finite(end), let firstPTS,
                  CMTimeSubtract(end, firstPTS).seconds <= maximumDuration else { throw AudioStreamError.storageLimit }
            let copy = try retimed(buffer, by: CMTimeMultiplyByFloat64(firstPTS, multiplier: -1))
            // An ADTS file is only a storage cut in a continuous encoder stream.
            // AssetReader's per-file priming/trailing policy must not discard
            // packets, drain, or reset the shared decoder at every HLS boundary.
            for key in [kCMSampleBufferAttachmentKey_TrimDurationAtStart,
                        kCMSampleBufferAttachmentKey_TrimDurationAtEnd,
                        kCMSampleBufferAttachmentKey_ResetDecoderBeforeDecoding,
                        kCMSampleBufferAttachmentKey_DrainAfterDecoding] {
                CMRemoveAttachment(copy, key: key)
            }
            buffers.append(copy)
            previousEnd = end
        }
        try Task.checkCancellation()
        guard reader.status == .completed else {
            throw reader.error ?? failure("finish reader", detail: "status=\(reader.status.rawValue) buffers=\(buffers.count)")
        }
        guard let firstPTS, let previousEnd, !buffers.isEmpty else { throw failure("empty compressed reader output") }
        return BufferedAudioSamples(buffers: buffers, duration: CMTimeSubtract(previousEnd, firstPTS))
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
