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
    dependencies: [
        // Sparkle in-app auto-update. SwiftPM links @rpath/Sparkle.framework but does
        // NOT embed it; script/build-app.zsh copies the framework into the bundle.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.0")
    ],
    targets: [
        .target(name: "MacOptimizingLooperCore"),
        .executableTarget(
            name: "MacOptimizingLooper",
            dependencies: [
                "MacOptimizingLooperCore",
                .product(name: "Sparkle", package: "Sparkle")
            ]
        ),
        .testTarget(name: "MacOptimizingLooperCoreTests", dependencies: ["MacOptimizingLooperCore"])
    ]
)
