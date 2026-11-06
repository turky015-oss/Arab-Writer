// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ArabWriter",
    defaultLocalization: "ar",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "ArabWriter", targets: ["ArabWriter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-examples", exact: "2.25.8"),
    ],
    targets: [
        .target(
            name: "ArabWriterCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "ArabWriter",
            dependencies: [
                "ArabWriterCore",
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
            ],
            exclude: ["Resources"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ArabWriterCoreTests",
            dependencies: ["ArabWriterCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
