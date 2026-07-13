// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ClipFlow",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClipFlowCore", targets: ["ClipFlowCore"]),
        .library(name: "ClipFlowStorage", targets: ["ClipFlowStorage"]),
        .library(name: "ClipFlowSystem", targets: ["ClipFlowSystem"]),
        .library(name: "ClipFlowUI", targets: ["ClipFlowUI"]),
        .executable(name: "ClipFlowApp", targets: ["ClipFlowApp"]),
        .executable(name: "ClipFlowCoreTests", targets: ["ClipFlowCoreTests"])
    ],
    targets: [
        .target(name: "ClipFlowCore"),
        .systemLibrary(
            name: "CSQLCipher",
            path: "Sources/CSQLCipher"
        ),
        .target(
            name: "ClipFlowStorage",
            dependencies: ["ClipFlowCore", "CSQLCipher"],
            linkerSettings: [
                .unsafeFlags([
                    "-L", ".build-tools/sqlcipher/static-lib",
                    "-L", ".build-tools/openssl/lib",
                    "-lcrypto", "-lz"
                ])
            ]
        ),
        .target(name: "ClipFlowSystem", dependencies: ["ClipFlowCore"]),
        .target(
            name: "ClipFlowUI",
            dependencies: ["ClipFlowCore", "ClipFlowStorage", "ClipFlowSystem"]
        ),
        .executableTarget(
            name: "ClipFlowApp",
            dependencies: ["ClipFlowCore", "ClipFlowStorage", "ClipFlowSystem", "ClipFlowUI"]
        ),
        .executableTarget(
            name: "ClipFlowCoreTests",
            dependencies: ["ClipFlowCore", "ClipFlowStorage", "ClipFlowSystem", "ClipFlowUI"],
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
