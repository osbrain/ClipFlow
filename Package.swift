// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ClipFlow",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClipFlowCore", targets: ["ClipFlowCore"]),
        .library(name: "ClipFlowStorage", targets: ["ClipFlowStorage"]),
        .library(name: "ClipFlowSystem", targets: ["ClipFlowSystem"]),
        .executable(name: "ClipFlowApp", targets: ["ClipFlowApp"]),
        .executable(name: "ClipFlowCoreTests", targets: ["ClipFlowCoreTests"])
    ],
    targets: [
        .target(name: "ClipFlowCore"),
        .target(name: "ClipFlowStorage", dependencies: ["ClipFlowCore"]),
        .target(name: "ClipFlowSystem", dependencies: ["ClipFlowCore"]),
        .executableTarget(name: "ClipFlowApp", dependencies: ["ClipFlowCore"]),
        .executableTarget(
            name: "ClipFlowCoreTests",
            dependencies: ["ClipFlowCore", "ClipFlowStorage", "ClipFlowSystem"],
            path: "Tests/ClipFlowCoreTests",
            swiftSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xfrontend", "-disable-cross-import-overlays"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
                ])
            ]
        )
    ]
)
