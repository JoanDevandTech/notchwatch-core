// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchwatchCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "NotchwatchCore", targets: ["NotchwatchCore"]),
    ],
    targets: [
        // Solo Foundation: compila y se testea en macOS y en Linux.
        .target(
            name: "NotchwatchCore",
            path: "Sources/NotchwatchCore"
        ),
        .testTarget(
            name: "NotchwatchCoreTests",
            dependencies: ["NotchwatchCore"],
            path: "Tests/NotchwatchCoreTests",
            resources: [.process("Fixtures")]
        ),
    ]
)
