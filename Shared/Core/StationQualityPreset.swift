import Foundation

enum StationQualityPreset: String, CaseIterable, Identifiable {
    case lowest, balanced, highest
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lowest: return "Lowest"
        case .balanced: return "Balanced"
        case .highest: return "Highest"
        }
    }
    func source(for station: RadioStation) -> StationAudioSource {
        let target = StationCatalog.defaultStation.defaultAudioSource.bitrateKbps
        return station.audioSources.min { left, right in
            let leftScore = score(left.bitrateKbps, target: target)
            let rightScore = score(right.bitrateKbps, target: target)
            if leftScore != rightScore { return leftScore < rightScore }
            // Prefer availability when two rates are equally close to KUSC.
            if left.bitrateKbps != right.bitrateKbps { return left.bitrateKbps < right.bitrateKbps }
            if (left == station.defaultAudioSource) != (right == station.defaultAudioSource) {
                return left == station.defaultAudioSource
            }
            return left.id < right.id
        } ?? station.defaultAudioSource
    }

    private func score(_ bitrate: Int, target: Int) -> Int {
        switch self {
        case .lowest: return bitrate
        case .balanced: return abs(bitrate - target)
        case .highest: return -bitrate
        }
    }
}
