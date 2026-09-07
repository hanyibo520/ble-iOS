// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ble-iOS",
    defaultLocalization: "zh-Hans",
    platforms: [
        .iOS(.v14),
        .macOS(.v13)
    ],
    products: [
        .library(name: "BRBluetoothLib", targets: ["BRBluetoothLib"])
    ],
    targets: [
        .target(name: "BRBluetoothLib", path: "Sources/BRBluetoothLib"),
        .testTarget(
            name: "BRBluetoothLibTests",
            dependencies: ["BRBluetoothLib"],
            path: "Tests/BRBluetoothLibTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
