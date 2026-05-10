// swift-tools-version:5.10
// This Package.swift is for `swift build` compile-checks only.
// The shipping product is built via xcodegen + xcodebuild (see project.yml).

import PackageDescription

let package = Package(
    name: "José",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "José", targets: ["José"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.2.0")
    ],
    targets: [
        .executableTarget(
            name: "José",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Sources/José",
            exclude: [
                "Audio/VAD/convert_silero.py",
                "Audio/VAD/README.md"
            ],
            resources: [
                .copy("Audio/VAD/SileroVAD.mlmodel"),
                .process("Resources")
            ]
        )
    ]
)
