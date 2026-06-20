// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "MacOptimizingLooper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MacOptimizingLooperCore", targets: ["MacOptimizingLooperCore"]),
        .executable(name: "MacOptimizingLooper", targets: ["MacOptimizingLooper"])
    ],
    targets: [
        .target(name: "MacOptimizingLooperCore"),
        .executableTarget(name: "MacOptimizingLooper", dependencies: ["MacOptimizingLooperCore"]),
        .testTarget(name: "MacOptimizingLooperCoreTests", dependencies: ["MacOptimizingLooperCore"])
    ]
)
