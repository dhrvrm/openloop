// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenLoopADHD",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ADHDCore", targets: ["ADHDCore"]),
        .library(name: "LocalStore", targets: ["LocalStore"]),
        .library(name: "RuleClarifier", targets: ["RuleClarifier"]),
        .library(name: "VaultStore", targets: ["VaultStore"]),
        .executable(name: "thought-loop", targets: ["ThoughtLoopCLI"]),
        .executable(name: "OpenLoopADHD", targets: ["OpenLoopApp"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/argmaxinc/argmax-oss-swift.git",
            from: "1.1.0"
        ),
        .package(
            url: "https://github.com/soniqo/speech-swift.git",
            revision: "17302bd13c2fc192d89fd79a71810a3a1d8c4f1a"
        ),
    ],
    targets: [
        .target(name: "ADHDCore"),
        .target(name: "LocalStore", dependencies: ["ADHDCore"]),
        .target(name: "RuleClarifier", dependencies: ["ADHDCore"]),
        .target(
            name: "VaultStore",
            dependencies: ["ADHDCore", "LocalStore"],
            linkerSettings: [.linkedFramework("Security")]
        ),
        .executableTarget(
            name: "ThoughtLoopCLI",
            dependencies: ["ADHDCore", "LocalStore", "RuleClarifier", "VaultStore"],
            linkerSettings: [.linkedFramework("Security")]
        ),
        .executableTarget(
            name: "OpenLoopApp",
            dependencies: [
                "ADHDCore",
                "LocalStore",
                "RuleClarifier",
                "VaultStore",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "SpeakerKit", package: "argmax-oss-swift"),
                .product(name: "Qwen3ASR", package: "speech-swift"),
                .product(name: "Qwen3Chat", package: "speech-swift"),
                .product(name: "SpeechVAD", package: "speech-swift"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("NaturalLanguage"),
                .linkedFramework("Security"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Speech"),
            ]
        ),
        .testTarget(name: "ADHDCoreTests", dependencies: ["ADHDCore"]),
        .testTarget(name: "LocalStoreTests", dependencies: ["ADHDCore", "LocalStore"]),
        .testTarget(name: "RuleClarifierTests", dependencies: ["ADHDCore", "RuleClarifier"]),
        .testTarget(
            name: "VaultStoreTests",
            dependencies: ["ADHDCore", "LocalStore", "VaultStore"],
            linkerSettings: [.linkedFramework("Security")]
        ),
        .testTarget(name: "OpenLoopAppTests", dependencies: ["OpenLoopApp"]),
    ]
)
