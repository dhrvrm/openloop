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
            dependencies: ["ADHDCore", "LocalStore", "RuleClarifier"]
        ),
        .testTarget(name: "ADHDCoreTests", dependencies: ["ADHDCore"]),
        .testTarget(name: "LocalStoreTests", dependencies: ["ADHDCore", "LocalStore"]),
        .testTarget(name: "RuleClarifierTests", dependencies: ["ADHDCore", "RuleClarifier"]),
        .testTarget(
            name: "VaultStoreTests",
            dependencies: ["ADHDCore", "LocalStore", "VaultStore"],
            linkerSettings: [.linkedFramework("Security")]
        ),
    ]
)
