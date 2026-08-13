// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenLoopADHD",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ADHDCore", targets: ["ADHDCore"]),
    ],
    targets: [
        .target(name: "ADHDCore"),
        .testTarget(name: "ADHDCoreTests", dependencies: ["ADHDCore"]),
    ]
)
