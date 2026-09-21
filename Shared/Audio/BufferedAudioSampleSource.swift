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
        guard tracks.count == 1, let track = tracks.first else { throw AudioStreamError.invalidAAC }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = true
        guard reader.canAdd(output) else { throw AudioStreamError.invalidAAC }
        reader.add(output)
        defer { reader.cancelReading() }
        guard reader.startReading() else { throw reader.error ?? AudioStreamError.invalidAAC }

        var buffers: [CMSampleBuffer] = []
        var firstPTS: CMTime?
        var previousEnd: CMTime?
        var byteCount = 0
        var format: CMFormatDescription?
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard CMSampleBufferDataIsReady(buffer), CMSampleBufferGetNumSamples(buffer) > 0,
                  let block = CMSampleBufferGetDataBuffer(buffer),
                  let description = CMSampleBufferGetFormatDescription(buffer),
                  let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
                  [kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2].contains(asbd.mFormatID),
                  asbd.mSampleRate.isFinite, asbd.mSampleRate > 0 else { throw AudioStreamError.invalidAAC }
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
            guard finite(pts), finite(duration), duration.seconds > 0 else { throw AudioStreamError.invalidAAC }
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
        guard reader.status == .completed else { throw reader.error ?? AudioStreamError.invalidAAC }
        guard let firstPTS, let previousEnd, !buffers.isEmpty else { throw AudioStreamError.invalidAAC }
        return BufferedAudioSamples(buffers: buffers, duration: CMTimeSubtract(previousEnd, firstPTS))
    }

    /// Core Media copies timing while retaining the original compressed data,
    /// format (including HE-AAC configuration), packet sizes and attachments.
    static func retimed(_ buffer: CMSampleBuffer, by offset: CMTime) throws -> CMSampleBuffer {
        guard finite(offset) else { throw AudioStreamError.invalidAAC }
        var count = 0
        guard CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: 0, arrayToFill: nil,
                                                    entriesNeededOut: &count) == noErr,
              count > 0, count <= maximumBuffers else { throw AudioStreamError.invalidAAC }
        var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(duration: .invalid,
            presentationTimeStamp: .invalid, decodeTimeStamp: .invalid), count: count)
        guard CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: count, arrayToFill: &timings,
                                                    entriesNeededOut: nil) == noErr else { throw AudioStreamError.invalidAAC }
        for index in timings.indices {
            guard finite(timings[index].presentationTimeStamp) else { throw AudioStreamError.invalidAAC }
            timings[index].presentationTimeStamp = CMTimeAdd(timings[index].presentationTimeStamp, offset)
            if timings[index].decodeTimeStamp.isValid {
                guard finite(timings[index].decodeTimeStamp) else { throw AudioStreamError.invalidAAC }
                timings[index].decodeTimeStamp = CMTimeAdd(timings[index].decodeTimeStamp, offset)
            }
            guard finite(timings[index].presentationTimeStamp),
                  !timings[index].decodeTimeStamp.isValid || finite(timings[index].decodeTimeStamp) else {
                throw AudioStreamError.invalidAAC
            }
        }
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: buffer,
            sampleTimingEntryCount: timings.count, sampleTimingArray: &timings, sampleBufferOut: &copy)
        guard status == noErr, let copy else { throw AudioStreamError.invalidAAC }
        return copy
    }

    private static func finite(_ time: CMTime) -> Bool {
        time.isValid && !time.isIndefinite && time.seconds.isFinite
    }
}
