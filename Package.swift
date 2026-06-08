// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HealthOS",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HealthOSApp", targets: ["HealthOSApp"]),
        .executable(name: "HealthOSCLI", targets: ["HealthOSCLI"]),
    ],
    dependencies: [
        .package(path: "Packages/HealthOSCore"),
        .package(path: "Packages/HealthOSPipeline"),
        .package(path: "Packages/HealthOSAgents"),
        .package(path: "Packages/HealthOSUI"),
        .package(path: "Packages/HealthOSTerminal"),
    ],
    targets: [
        .executableTarget(
            name: "HealthOSCLI",
            dependencies: [
                "HealthOSCore",
                "HealthOSPipeline",
                "HealthOSAgents",
                "HealthOSTerminal"
            ],
            path: "HealthOSCLI"
        ),
        .executableTarget(
            name: "HealthOSApp",
            dependencies: [
                "HealthOSCore",
                "HealthOSPipeline",
                "HealthOSAgents",
                "HealthOSUI",
                "HealthOSTerminal",
            ],
            path: "HealthOSApp",
            resources: [
                .copy("Resources"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "HealthOSApp/Info.plist",
                ]),
            ]
        ),
    ]
)
