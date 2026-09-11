// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CandleKit",
    platforms: [
        .iOS(.v17),
        // Listed so the core engine and its tests run with `swift test` on a Mac.
        // The SwiftUI chart itself is iOS-only for now.
        .macOS(.v14),
    ],
    products: [
        .library(name: "CandleKit", targets: ["CandleKit"]),
        .library(name: "CandleKitCore", targets: ["CandleKitCore"]),
    ],
    targets: [
        // Pure Foundation: viewport math, scales, indicators, series diffing.
        // Builds and tests on any platform, including Linux CI.
        .target(name: "CandleKitCore"),
        // SwiftUI + UIKit rendering and gestures.
        .target(name: "CandleKit", dependencies: ["CandleKitCore"]),
        .testTarget(name: "CandleKitCoreTests", dependencies: ["CandleKitCore"]),
    ]
)
