// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ClipFlow",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClipFlowCore", targets: ["ClipFlowCore"]),
        .executable(name: "ClipFlowApp", targets: ["ClipFlowApp"]),
        .executable(name: "ClipFlowCoreTests", targets: ["ClipFlowCoreTests"])
    ],
    targets: [
        .target(name: "ClipFlowCore"),
        .executableTarget(name: "ClipFlowApp", dependencies: ["ClipFlowCore"]),
        .executableTarget(
            name: "ClipFlowCoreTests",
            dependencies: ["ClipFlowCore"],
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
