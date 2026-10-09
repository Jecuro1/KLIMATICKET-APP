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
        // Fixtures are bundled (Bundle.module: ÖBB live fixtures, docs/OEBB_LIVE.md §D1); the places tests read the same
        // folder from disk via #filePath (shared with scripts/places_reference.py).
        .testTarget(name: "KlimaCoreTests", dependencies: ["KlimaCore"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v5]
)
