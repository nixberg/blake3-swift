// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "BLAKE3",
    products: [
        .library(
            name: "BLAKE3",
            targets: ["BLAKE3"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-algorithms", from: "1.0.0"),
        
        .package(url: "https://github.com/nixberg/crypto-traits-swift", "0.2.1"..<"0.3.0"),
        .package(url: "https://github.com/nixberg/endianbytes-swift", "0.5.0"..<"0.6.0"),
        .package(url: "https://github.com/nixberg/hexstring-swift", "0.5.0"..<"0.6.0"),
    ],
    targets: [
        .target(
            name: "BLAKE3",
            dependencies: [
                .product(name: "Algorithms", package: "swift-algorithms"),
                .product(name: "Duplex", package: "crypto-traits-swift"),
                .product(name: "SIMDEndianBytes", package: "endianbytes-swift"),
            ]),
        .testTarget(
            name: "BLAKE3Tests",
            dependencies: [
                "BLAKE3",
                .product(name: "HexString", package: "hexstring-swift"),
            ],
            resources: [
                .copy("test_vectors.json")
            ]),
    ]
)
