// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HealthOSCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HealthOSCore", targets: ["HealthOSCore"]),
    ],
    targets: [
        .target(
            name: "HealthOSCore",
            path: "Sources/HealthOSCore"
        ),
        .testTarget(
            name: "HealthOSCoreTests",
            dependencies: ["HealthOSCore"],
            path: "Tests/HealthOSCoreTests"
        ),
    ]
)
