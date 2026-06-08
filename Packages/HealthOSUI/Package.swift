// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HealthOSUI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HealthOSUI", targets: ["HealthOSUI"]),
    ],
    dependencies: [
        .package(path: "../HealthOSCore"),
        .package(path: "../HealthOSPipeline"),
        .package(path: "../HealthOSAgents"),
    ],
    targets: [
        .target(
            name: "HealthOSUI",
            dependencies: [
                "HealthOSCore",
                "HealthOSPipeline",
                "HealthOSAgents",
            ],
            path: "Sources/HealthOSUI"
        ),
        .testTarget(
            name: "HealthOSUITests",
            dependencies: ["HealthOSUI"],
            path: "Tests/HealthOSUITests"
        ),
    ]
)
