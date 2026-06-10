// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ZoomIt",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        // Platform-independent logic: zoom math, drawing model, parsers, stitching.
        .target(
            name: "ZoomItCore",
            path: "Sources/ZoomItCore"
        ),
        // The menu-bar application.
        .executableTarget(
            name: "ZoomIt",
            dependencies: ["ZoomItCore"],
            path: "Sources/ZoomIt"
        ),
        .testTarget(
            name: "ZoomItCoreTests",
            dependencies: ["ZoomItCore"],
            path: "Tests/ZoomItCoreTests"
        ),
    ]
)
