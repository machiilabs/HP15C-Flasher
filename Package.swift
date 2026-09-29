// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "HP15CFlasher",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "HP15CFlasherCore", targets: ["HP15CFlasherCore"]),
        .executable(name: "hp15c-flasher", targets: ["hp15c-flasher"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "HP15CFlasherCore",
            resources: [.copy("known-firmware.json")]
        ),
        .executableTarget(
            name: "hp15c-flasher",
            dependencies: [
                "HP15CFlasherCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "HP15CFlasherCoreTests",
            dependencies: ["HP15CFlasherCore"]
        ),
    ]
)
