// swift-tools-version: 6.0
import PackageDescription

/// Cloud core of KlimaBilanz (Cloudflare Worker + D1 backend, docs/CLOUDFLARE_BACKEND.md §6):
/// HTTP client, DTOs, merge rule, timestamps, PKCE. Foundation only, so it builds and tests on Linux.
let package = Package(
    name: "KlimaCloud",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "KlimaCloud", targets: ["KlimaCloud"]),
    ],
    targets: [
        .target(name: "KlimaCloud"),
        .testTarget(name: "KlimaCloudTests", dependencies: ["KlimaCloud"]),
    ],
    swiftLanguageModes: [.v5]
)
