// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftDeflate",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "SwiftDeflate",
            targets: ["SwiftDeflate"]
        )
    ],
    targets: [
        .systemLibrary(
            name: "CLibDeflate",
            path: "Sources/CLibDeflate",
            pkgConfig: "libdeflate",
            providers: [
                .apt(["libdeflate-dev"]),
                .brew(["libdeflate"]),
            ],
        ),
        .target(
            name: "SwiftDeflate",
            dependencies: [
                .target(name: "CLibDeflate")
            ]
        ),
        .testTarget(
            name: "SwiftDeflateTests",
            dependencies: ["SwiftDeflate"]
        ),
    ]
)
