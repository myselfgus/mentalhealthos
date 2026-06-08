// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HealthOSPipeline",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HealthOSPipeline", targets: ["HealthOSPipeline"]),
    ],
    dependencies: [
        .package(path: "../HealthOSCore"),
    ],
    targets: [
        .target(
            name: "HealthOSPipeline",
            dependencies: ["HealthOSCore"],
            path: "Sources/HealthOSPipeline"
        ),
        .testTarget(
            name: "HealthOSPipelineTests",
            dependencies: ["HealthOSPipeline"],
            path: "Tests/HealthOSPipelineTests"
        ),
    ]
)
