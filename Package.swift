// swift-tools-version: 6.0
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
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.0.4"),
    ],
    targets: [
        .target(
            name: "CBORCodable",
            dependencies: [
                .product(name: "OrderedCollections", package: "swift-collections"),
            ]
        ),
        .testTarget(
            name: "CBORCodableTests",
            dependencies: ["CBORCodable"],
            resources: [
                .copy("Resources/cbor-test-vectors"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
