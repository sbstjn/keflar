// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "keflar",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(
            name: "keflar",
            targets: ["keflar"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "keflar",
            dependencies: [],
            path: "keflar"
        ),
        .testTarget(
            name: "keflarTests",
            dependencies: ["keflar"],
            path: "keflarTests"
        )
    ]
)
