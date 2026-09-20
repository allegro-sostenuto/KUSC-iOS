// swift-tools-version: 5.9
import PackageDescription

// Core policy tests also run without Xcode or an iOS SDK: swift test
let package = Package(
    name: "KUSCCore",
    platforms: [.macOS(.v12), .iOS(.v16)],
    products: [.library(name: "KUSCCore", targets: ["KUSCCore"])],
    targets: [
        .target(name: "KUSCCore", path: "Shared",
                exclude: ["AppSettings.swift", "AppModel.swift", "KUSCApp.swift", "StationConfiguration.swift", "Metadata/MetadataService.swift",
                          "System", "Timers", "UI", "Audio/RollingAudioEngine.swift", "Audio/HLSIngestor.swift", "Audio/PlaybackDiagnostics.swift"],
                sources: ["Core", "Audio/ADTSParser.swift", "Audio/HLSManifest.swift",
                          "Metadata/StationMetadataParser.swift"]),
        .testTarget(name: "KUSCCoreTests", dependencies: ["KUSCCore"], path: "Tests",
                    resources: [.copy("Fixtures")])
    ]
)
