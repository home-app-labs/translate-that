// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TranslatePlus",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "TranslatePlus", path: "Sources/TranslatePlus"),
        .testTarget(name: "TranslatePlusTests", dependencies: ["TranslatePlus"], path: "Tests/TranslatePlusTests"),
    ]
)
