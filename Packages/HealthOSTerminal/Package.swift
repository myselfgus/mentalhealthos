// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HealthOSTerminal",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HealthOSTerminal", targets: ["HealthOSTerminal"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.0"),
        .package(path: "../HealthOSCore"),
        .package(path: "../HealthOSPipeline")
    ],
    targets: [
        .target(
            name: "HealthOSTerminal",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "HealthOSCore", package: "HealthOSCore"),
                .product(name: "HealthOSPipeline", package: "HealthOSPipeline")
            ],
            path: "Sources/HealthOSTerminal"
        ),
        .testTarget(
            name: "HealthOSTerminalTests",
            dependencies: ["HealthOSTerminal"],
            path: "Tests/HealthOSTerminalTests"
        ),
    ]
)
