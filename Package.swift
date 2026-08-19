// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OpenCodexDesktop",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OpenCodexDesktop", targets: ["OpenCodexDesktop"]),
    ],
    targets: [
        .executableTarget(
            name: "OpenCodexDesktop",
            path: "Sources/OpenCodexDesktop"
        ),
        .testTarget(
            name: "OpenCodexDesktopTests",
            dependencies: ["OpenCodexDesktop"],
            path: "Tests/OpenCodexDesktopTests"
        ),
    ]
)
