// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Notchwatch",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Notchwatch", targets: ["Notchwatch"]),
        .library(name: "NotchwatchCore", targets: ["NotchwatchCore"]),
    ],
    targets: [
        // Núcleo sin UI: solo Foundation (compila también en Linux).
        .target(
            name: "NotchwatchCore",
            path: "Sources/NotchwatchCore"
        ),
        // App de barra de menús (SwiftUI/AppKit).
        .executableTarget(
            name: "Notchwatch",
            dependencies: ["NotchwatchCore"],
            path: "Sources/Notchwatch"
        ),
        // Tests del núcleo con fixtures JSON de Asana.
        .testTarget(
            name: "NotchwatchCoreTests",
            dependencies: ["NotchwatchCore"],
            path: "Tests/NotchwatchCoreTests",
            resources: [.process("Fixtures")]
        ),
    ]
)
