// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pulsar",
    platforms: [
        .macOS("14.4"),
    ],
    targets: [
        .executableTarget(
            name: "Pulsar",
            path: "Sources/Pulsar",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "PulsarTests",
            dependencies: ["Pulsar"]
        ),
    ]
)
