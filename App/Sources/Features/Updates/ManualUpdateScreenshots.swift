import SwiftUI
import KlimaCore

// MARK: settings – Manuell aktualisieren: CI screenshot host (split from ManualUpdateView.swift).

// MARK: - Screenshots

/// CI routes `manualUpdate` (nothing loaded yet), `manualUpdateProgress` (62 %, paused mid-way would look the same)
/// and `manualUpdateReady` (verified file, share + Files) – a frozen downloader, no network.
struct ManualUpdateScreenshotHost: View {
    static let screens: Set<String> = ["manualUpdate", "manualUpdateProgress", "manualUpdateReady"]

    var screen: String
    @Environment(AppState.self) private var app
    @State private var downloader: ManualUpdateDownloader?
    @State private var release: UpdateManifest?

    var body: some View {
        NavigationStack {
            if let downloader, let release {
                ManualUpdateView(downloader: downloader, release: release)
            }
        }
        .onAppear {
            guard downloader == nil else { return }
            let installed = app.updates.installedVersion
            let sample = UpdateManifest(
                version: SemanticVersion(major: installed.major, minor: installed.minor, patch: installed.patch + 1),
                build: app.updates.installedBuild + 1,
                publishedAt: ISO8601DateFormatter().string(from: Date()),
                downloadURL: "https://example.com/KlimaBilanz.ipa",
                releaseNotes: ["Manuell aktualisieren: .ipa in der App laden"],
                size: 23_692_125, sha256: String(repeating: "5e", count: 32))
            release = sample
            switch screen {
            case "manualUpdateProgress": downloader = .demo(.downloading, manifest: sample, fraction: 0.62)
            case "manualUpdateReady": downloader = .demo(.ready(.verified), manifest: sample, fraction: 1)
            default: downloader = .demo(.idle, manifest: sample)
            }
        }
    }
}
