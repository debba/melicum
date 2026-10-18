// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Melicum",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Melicum", targets: ["Melicum"])],
    targets: [
        .target(name: "AudioDSP", publicHeadersPath: "include", linkerSettings: [.linkedFramework("AudioToolbox"), .linkedFramework("CoreAudio")]),
        .target(name: "AudioCore", dependencies: ["AudioDSP"], resources: [.process("Localizations")]),
        .executableTarget(name: "Melicum", dependencies: ["AudioCore", "AudioDSP"]),
        .testTarget(name: "AudioCoreTests", dependencies: ["AudioCore", "AudioDSP"])
    ]
)
