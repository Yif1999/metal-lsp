// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "metal-lsp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "metal-lsp",
            targets: ["MetalLSP"]
        ),
        .executable(
            name: "metal-doc-generator",
            targets: ["MetalDocGenerator"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        // Main executable target
        .executableTarget(
            name: "MetalLSP",
            dependencies: [
                "MetalLanguageServer",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),

        // Core LSP implementation
        .target(
            name: "MetalLanguageServer",
            dependencies: ["MetalCore"]
        ),

        // Metal language specifics (parser, compiler integration, built-ins)
        .target(
            name: "MetalCore",
            dependencies: []
        ),

        // Documentation generator tool
        .executableTarget(
            name: "MetalDocGenerator",
            dependencies: ["MetalCore"]
        ),

        // Tests
        .testTarget(
            name: "MetalLSPTests",
            dependencies: ["MetalLanguageServer", "MetalCore"]
        ),
    ]
)
