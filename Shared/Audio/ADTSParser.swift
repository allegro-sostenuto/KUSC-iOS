import Foundation

/// A complete AAC access unit, including its ADTS transport header.
struct ADTSFrame {
    let bytes: Data
    let duration: TimeInterval
}

enum AudioStreamError: LocalizedError {
    case httpStatus(Int)
    case unsupportedFormat(String)
    case invalidAAC
    case disconnected
    case stalled
    case storageLimit

    var errorDescription: String? {
        switch self {
        case .httpStatus(let status): return "The station returned HTTP \(status)."
        case .unsupportedFormat(let format): return "The station returned an unsupported audio format: \(format)."
        case .invalidAAC: return "The station stream does not contain valid AAC audio."
        case .disconnected: return "The station closed the audio connection."
        case .stalled: return "The station audio connection stalled."
        case .storageLimit: return "The audio buffer exceeded its storage safety limit."
        }
    }
}

/// Stateful parser: a URLSession chunk may split a header or contain many access units.
/// HE-AAC SBR doubles both decoded samples and sample rate; the core ADTS ratio is
/// still the correct duration. This accepts MPEG-2/4 ADTS, not MP3, LATM or HLS.
struct ADTSParser {
    private var pending = Data()
    private var discardedBytes = 0
    private static let rates: [Double] = [96000, 88200, 64000, 48000, 44100, 32000,
                                         24000, 22050, 16000, 12000, 11025, 8000, 7350]

    mutating func append(_ data: Data) throws -> [ADTSFrame] {
        pending.append(data)
        guard pending.count <= 2 * 1024 * 1024 else { throw AudioStreamError.invalidAAC }
        let bytes = [UInt8](pending)
        var frames: [ADTSFrame] = []
        var offset = 0
        while bytes.count - offset >= 7 {
            // Twelve sync bits and the two reserved layer bits.
            guard bytes[offset] == 0xff, bytes[offset + 1] & 0xf6 == 0xf0 else {
                offset += 1
                discardedBytes += 1
                if discardedBytes > 64 * 1024 { throw AudioStreamError.invalidAAC }
                continue
            }
            let frequencyIndex = Int((bytes[offset + 2] >> 2) & 0x0f)
            guard frequencyIndex < Self.rates.count else {
                offset += 1
                discardedBytes += 1
                continue
            }
            let headerLength = bytes[offset + 1] & 1 == 1 ? 7 : 9
            let length = (Int(bytes[offset + 3] & 3) << 11)
                | (Int(bytes[offset + 4]) << 3) | Int(bytes[offset + 5] >> 5)
            guard length >= headerLength else {
                offset += 1
                discardedBytes += 1
                continue
            }
            guard bytes.count - offset >= length else { break }
            let rawBlocks = Int(bytes[offset + 6] & 3) + 1
            let duration = Double(1024 * rawBlocks) / Self.rates[frequencyIndex]
            frames.append(ADTSFrame(bytes: Data(bytes[offset..<(offset + length)]), duration: duration))
            offset += length
            discardedBytes = 0
        }
        if offset > 0 { pending = Data(bytes[offset...]) }
        return frames
    }
}

/// Separates optional ICY metadata from AAC bytes. Asking for Icy-MetaData: 0
/// normally disables it, but honoring the response protects against server changes.
struct ICYAudioFilter {
    private let interval: Int?
    private var audioRemaining: Int
    private var metadataRemaining = 0
    private var expectingLength = false

    init(metadataInterval: Int?) {
        interval = metadataInterval.flatMap { $0 > 0 ? $0 : nil }
        audioRemaining = interval ?? 0
    }

    mutating func append(_ data: Data) -> Data {
        guard let interval else { return data }
        let bytes = [UInt8](data)
        var audio = Data()
        var offset = 0
        while offset < bytes.count {
            if metadataRemaining > 0 {
                let count = min(metadataRemaining, bytes.count - offset)
                metadataRemaining -= count
                offset += count
                if metadataRemaining == 0 { audioRemaining = interval }
            } else if expectingLength {
                metadataRemaining = Int(bytes[offset]) * 16
                offset += 1
                expectingLength = false
                if metadataRemaining == 0 { audioRemaining = interval }
            } else {
                let count = min(audioRemaining, bytes.count - offset)
                audio.append(contentsOf: bytes[offset..<(offset + count)])
                offset += count
                audioRemaining -= count
                if audioRemaining == 0 { expectingLength = true }
            }
        }
        return audio
    }
}
