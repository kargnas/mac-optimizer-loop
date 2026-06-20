// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "MacOptimizingLooper",
    // English is the source-of-truth localization; missing keys in any other
    // .lproj fall back to en (NSLocalizedString resolves against the en bundle).
    defaultLocalization: "en",
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
        .target(
            name: "MacOptimizingLooperCore",
            // Localized UI chrome lives in <locale>.lproj/Localizable.strings.
            // .process emits them into Bundle.module; AppStrings forces a specific
            // locale by loading the matching .lproj sub-bundle at runtime.
            resources: [.process("Resources")]
        ),
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
