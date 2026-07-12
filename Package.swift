// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Shrike",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(name: "ShrikeCore"),
        .executableTarget(
            name: "shrike",
            dependencies: [
                "ShrikeCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        // The Command Line Tools toolchain ships no XCTest/Testing module, so
        // tests are a plain executable: `swift run shrike-tests`.
        .executableTarget(name: "shrike-tests", dependencies: ["ShrikeCore"]),
    ]
)
