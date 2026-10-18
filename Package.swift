// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Melicum",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Melicum", targets: ["Melicum"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "AudioDSP", publicHeadersPath: "include", linkerSettings: [.linkedFramework("AudioToolbox"), .linkedFramework("CoreAudio")]),
        .target(name: "AudioCore", dependencies: ["AudioDSP"], resources: [.process("Localizations")]),
        .executableTarget(name: "Melicum", dependencies: ["AudioCore", "AudioDSP", .product(name: "Sparkle", package: "Sparkle")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "AudioCoreTests", dependencies: ["AudioCore", "AudioDSP"]),
        .testTarget(name: "MelicumTests", dependencies: ["Melicum"])
    ]
)
