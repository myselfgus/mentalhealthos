// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HealthOSAgents",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HealthOSAgents", targets: ["HealthOSAgents"]),
    ],
    dependencies: [
        .package(path: "../HealthOSCore"),
        .package(path: "../HealthOSPipeline"),
    ],
    targets: [
        .target(
            name: "HealthOSAgents",
            dependencies: ["HealthOSCore", "HealthOSPipeline"],
            path: "Sources/HealthOSAgents"
        ),
        .testTarget(
            name: "HealthOSAgentsTests",
            dependencies: ["HealthOSAgents"],
            path: "Tests/HealthOSAgentsTests"
        ),
    ]
)
