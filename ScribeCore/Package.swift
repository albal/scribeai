// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ScribeCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ScribeCore", targets: ["ScribeCore"]),
        .executable(name: "prompt-harness", targets: ["PromptHarness"]),
    ],
    targets: [
        .target(name: "ScribeCore"),
        .executableTarget(name: "PromptHarness", dependencies: ["ScribeCore"]),
        .testTarget(name: "ScribeCoreTests", dependencies: ["ScribeCore", "PromptHarness"]),
    ]
)
