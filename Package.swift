// swift-tools-version: 5.9
import PackageDescription

// Core policy tests also run without Xcode or an iOS SDK: swift test
let package = Package(
    name: "PhilharmonicCore",
    platforms: [.macOS(.v12), .iOS(.v16)],
    products: [.library(name: "PhilharmonicCore", targets: ["PhilharmonicCore"])],
    targets: [
        .target(name: "PhilharmonicCore", path: "Shared",
                exclude: ["AppSettings.swift", "AppModel.swift", "PhilharmonicApp.swift", "StationConfiguration.swift", "Metadata/MetadataService.swift",
                          "System", "Timers", "UI", "Audio/RollingAudioEngine.swift", "Audio/HLSIngestor.swift", "Audio/PlaybackDiagnostics.swift",
                          "Audio/BufferedAudioSampleSource.swift", "Audio/BufferedAudioRenderer.swift", "Audio/SpeakerVolumeSetup.swift"],
                sources: ["Core", "Audio/ADTSParser.swift", "Audio/HLSManifest.swift",
                          "Metadata/StationMetadataParser.swift", "Metadata/BroadcastMetadataParser.swift"]),
        .testTarget(name: "PhilharmonicCoreTests", dependencies: ["PhilharmonicCore"], path: "Tests",
                    resources: [.copy("Fixtures")])
    ]
)
