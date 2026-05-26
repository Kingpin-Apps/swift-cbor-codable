// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-cbor-codable",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "swift-cbor-codable",
            targets: ["swift-cbor-codable"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "swift-cbor-codable"
        ),
        .testTarget(
            name: "swift-cbor-codableTests",
            dependencies: ["swift-cbor-codable"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
