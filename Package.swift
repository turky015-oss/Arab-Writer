// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ArabWriter",
    defaultLocalization: "ar",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "ArabWriter", targets: ["ArabWriter"]),
    ],
    targets: [
        .target(
            name: "ArabWriterCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "ArabWriter",
            dependencies: ["ArabWriterCore"],
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
