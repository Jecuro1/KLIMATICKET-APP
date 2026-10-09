// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KlimaCore",
    defaultLocalization: "de",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "KlimaCore", targets: ["KlimaCore"]),
    ],
    targets: [
        .target(name: "KlimaCore"),
        // Fixtures are read from disk via #filePath (shared with scripts/places_reference.py), not bundled.
        .testTarget(name: "KlimaCoreTests", dependencies: ["KlimaCore"], exclude: ["Fixtures"]),
    ],
    swiftLanguageModes: [.v5]
)
