// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Arcmark",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // Foundation-only data layer for CLI and app
        .library(name: "ArcmarkData", targets: ["ArcmarkData"]),
        // AppKit UI layer for bundler to use
        .library(name: "ArcmarkCore", targets: ["ArcmarkCore"]),
        // GUI executable for development/testing
        .executable(name: "Arcmark", targets: ["ArcmarkApp"]),
        // CLI executable
        .executable(name: "arcmark", targets: ["ArcmarkCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        // Foundation-only data layer (Models, AppModel, DataStore, etc.)
        .target(name: "ArcmarkData", dependencies: []),
        // AppKit UI layer with all app logic
        .target(name: "ArcmarkCore", dependencies: ["ArcmarkData", "Sparkle"]),
        // Minimal executable entry point
        .executableTarget(
            name: "ArcmarkApp",
            dependencies: ["ArcmarkCore"]
        ),
        // CLI executable
        .executableTarget(
            name: "ArcmarkCLI",
            dependencies: [
                "ArcmarkData",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "ArcmarkCLITests",
            dependencies: ["ArcmarkCLI", "ArcmarkData"]
        ),
        .testTarget(
            name: "ArcmarkDataTests",
            dependencies: ["ArcmarkData"]
        ),
        .testTarget(
            name: "ArcmarkTests",
            dependencies: ["ArcmarkCore", "ArcmarkData"]
        )
    ]
)
