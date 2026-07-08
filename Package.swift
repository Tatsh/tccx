// swift-tools-version:5.7
// version: 0.0.1
import PackageDescription

let package = Package(
    name: "tcc-preapprove",
    platforms: [.macOS(.v10_15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "tcc-preapprove",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "tcc-preapproveTests",
            dependencies: ["tcc-preapprove"]
        ),
    ]
)
