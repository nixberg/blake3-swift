// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "BLAKE3",
    products: [
        .library(
            name: "BLAKE3",
            targets: ["BLAKE3"]),
    ],
    targets: [
        .target(
            name: "BLAKE3"),
        .testTarget(
            name: "BLAKE3Tests",
            dependencies: ["BLAKE3"]),
    ]
)
