// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Hashdrop",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Hashdrop",
            path: "Sources/Hashdrop",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
