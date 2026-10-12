// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OnscreenTodoMatrix",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OnscreenTodoMatrix", targets: ["OnscreenTodoMatrix"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "3.1.0"),
    ],
    targets: [
        .target(name: "OTMCore"),
        .executableTarget(
            name: "OnscreenTodoMatrix",
            dependencies: ["OTMCore", "KeyboardShortcuts"]
        ),
        .testTarget(name: "OTMCoreTests", dependencies: ["OTMCore"]),
    ]
)
