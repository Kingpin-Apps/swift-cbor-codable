// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CBORCodable",
    platforms: [
        .iOS(.v16),
        .macOS(.v14),
        .watchOS(.v8),
        .tvOS(.v15),
        .visionOS(.v1),
        .macCatalyst(.v15),
    ],
    products: [
        .library(
            name: "CBORCodable",
            targets: ["CBORCodable"]
        ),
    ],
    targets: [
        .target(
            name: "CBORCodable"
        ),
        .testTarget(
            name: "CBORCodableTests",
            dependencies: ["CBORCodable"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
