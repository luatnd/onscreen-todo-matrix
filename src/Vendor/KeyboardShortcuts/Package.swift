// swift-tools-version:6.2
// Vendored KeyboardShortcuts 3.1.0 (MIT, see license) WITHOUT its localization resource bundle:
// SwiftPM's Bundle.module accessor cannot find a bundle inside a signed .app and traps (see README in this folder).
import PackageDescription

let package = Package(
	name: "KeyboardShortcuts",
	platforms: [
		.macOS(.v10_15)
	],
	products: [
		.library(name: "KeyboardShortcuts", targets: ["KeyboardShortcuts"])
	],
	targets: [
		.target(
			name: "KeyboardShortcuts",
			swiftSettings: [
				.defaultIsolation(MainActor.self),
				.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
				.enableUpcomingFeature("InferIsolatedConformances")
			]
		)
	]
)
