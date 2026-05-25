// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pulsar",
    platforms: [
        .macOS(.v15),
    ],
    targets: [
        .executableTarget(
            name: "Pulsar",
            path: "Sources/Pulsar",
            exclude: ["Info.plist"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PulsarTests",
            dependencies: ["Pulsar"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
