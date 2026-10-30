// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Clefwise",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Clefwise", path: "Sources/Clefwise"),
        .testTarget(
            name: "ClefwiseTests",
            dependencies: ["Clefwise"],
            path: "Tests/ClefwiseTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
