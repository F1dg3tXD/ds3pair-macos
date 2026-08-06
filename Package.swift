// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation
import IOKit

let package = Package(
    name: "ds3pair-macos",
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "ds3pair-macos",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("IOBluetooth"),
            ]
        ),
        .testTarget(
            name: "ds3pair-macosTests",
            dependencies: ["ds3pair-macos"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
