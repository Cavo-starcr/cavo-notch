// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cyclop",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Cyclop", targets: ["Cyclop"])
    ],
    targets: [
        .executableTarget(
            name: "Cyclop",
            path: "Sources/Cyclop",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
