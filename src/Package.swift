// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OnscreenTodoMatrix",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OnscreenTodoMatrix", targets: ["OnscreenTodoMatrix"]),
    ],
    dependencies: [
        .package(path: "Vendor/KeyboardShortcuts"),
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
