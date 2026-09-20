import AVFoundation

/// Only used for the explicit, charging-gated scheduled-start policy.
/// iOS may still suspend/terminate this process; the local notification is independent.
@MainActor final class SilentStandby {
    private var player: AVAudioPlayer?
    var running: Bool { player?.isPlaying == true }

    func start() throws {
        if running { return }
        let sampleRate = 8_000
        let sampleCount = sampleRate
        var data = Data()
        func ascii(_ value: String) { data.append(contentsOf: value.utf8) }
        func u16(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        ascii("RIFF"); u32(UInt32(36 + sampleCount * 2)); ascii("WAVEfmt "); u32(16)
        u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        ascii("data"); u32(UInt32(sampleCount * 2)); data.append(Data(count: sampleCount * 2))
        let p = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
        p.numberOfLoops = -1
        p.volume = 0
        p.prepareToPlay()
        guard p.play() else { throw StandbyError.failed }
        player = p
    }
    func stop() { player?.stop(); player = nil }
    enum StandbyError: Error { case failed }
}
