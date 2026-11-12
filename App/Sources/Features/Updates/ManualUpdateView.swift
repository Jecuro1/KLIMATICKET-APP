import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable
import KlimaCore

// MARK: settings – Manuell aktualisieren (docs/MANUAL_UPDATE.md)

/// "Manuell aktualisieren": the newest .ipa is downloaded inside the app (progress ring, resumable, size + SHA-256
/// checked), then handed to SideStore/AltStore through the share sheet or saved to the Files app. Honest about iOS: it
/// installs no .ipa by itself – a sideload app (or, with a paid developer account, a direct install link) has to.
///
/// Pushed from Einstellungen › Updates; presented as a sheet from the update sheet (`ManualUpdateSheet`).
///
/// Motion (docs/MOTION.md): the cards rise in once in reading order; the ring fills with the download, the percentage
/// rolls; a verified file turns the ring green, the check pops and one ring leaves the icon (with `.success`).
struct ManualUpdateView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var openURL

    var downloader: ManualUpdateDownloader = .shared
    /// The release to offer (the update sheet's pinned one) – otherwise the newest one the update service knows.
    var release: UpdateManifest? = nil

    @State private var isLoadingRelease = false
    @State private var isExporting = false
    @State private var savedToFiles = false
    @State private var storeMissing: ManualUpdateLinks.Store? = nil
    @State private var tapTrigger = 0

    private var target: UpdateManifest? {
        release ?? app.updates.availableManifest ?? app.updates.manifest ?? downloader.manifest
    }

    /// The downloader's state for the shown release; a kept download of another release counts as nothing yet.
    private var phase: ManualUpdateDownloader.Phase {
        downloader.matches(target) ? downloader.phase : .idle
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                if let target {
                    MUHeroCard(release: target, downloader: downloader, phase: phase,
                               installed: app.updates.installedVersion, installedBuild: app.updates.installedBuild,
                               storeName: storeName, isExporting: $isExporting, savedToFiles: savedToFiles,
                               tapTrigger: $tapTrigger)
                        .reveal(.focus)
                    MUHonestNote()
                        .reveal(order: 1)
                    MUOneTapCard(links: links(for: target), missing: $storeMissing)
                        .reveal(order: 2)
                    MUGuideCard(fileName: ManualUpdate.fileName(for: target), storeName: storeName,
                                isReady: phase.isReady)
                        .reveal(order: 3)
                } else {
                    MUNoReleaseCard(isLoading: isLoadingRelease) { Task { await loadRelease(force: true) } }
                        .reveal(.focus)
                }
                MUNoSideloadCard()
                    .reveal(order: 4)
                MUDeveloperCard(isActive: UpdateService.isDirectInstallCopy)
                    .reveal(order: 5)
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xxl)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .revealScope()
        .background { SetBackdrop(skyOpacity: 0.45, fadeEnd: 0.42) }
        .tint(Theme.accent)
        .navigationTitle(ManualUpdateCopy.title)
        .navigationBarTitleDisplayMode(.large)
        .fileExporter(isPresented: $isExporting, item: downloader.fileURL.map(IPAFile.init), contentTypes: [.ipaFile],
                      defaultFilename: target.map { ManualUpdate.fileName(for: $0) }) { result in
            if case .success = result {
                withMotion(Motion.bouncy) { savedToFiles = true }
            }
        }
        // One haptic per step: tap on start/pause, success when the file is verified, error when it failed.
        .haptic(.tap, trigger: tapTrigger)
        .haptic(.success, trigger: phase.isReady, when: { old, new in !old && new })
        .haptic(.error, trigger: phase.isFailure, when: { old, new in !old && new })
        .haptic(.success, trigger: savedToFiles, when: { old, new in !old && new })
        .task {
            if target == nil { await loadRelease(force: false) }
        }
    }

    private var storeName: String {
        app.updates.sideloadStore == .altStore ? "AltStore" : "SideStore"
    }

    /// The store that installed this copy first.
    private func links(for release: UpdateManifest) -> [ManualUpdateLinks.Link] {
        var links: [ManualUpdateLinks.Link] = []
        if let url = app.updates.sideStoreInstallURL(for: release) { links.append(.init(store: .sideStore, url: url)) }
        if let url = app.updates.altStoreInstallURL(for: release) { links.append(.init(store: .altStore, url: url)) }
        if app.updates.sideloadStore == .altStore { links.reverse() }
        return links
    }

    /// The manifest is not kept across launches: fetch it without raising the update sheet.
    private func loadRelease(force: Bool) async {
        guard !isLoadingRelease, !LaunchMode.isScreenshot else { return }
        withMotion(Motion.smooth) { isLoadingRelease = true }
        await app.updates.checkIfDue(force: true, presents: false)
        withMotion(Motion.smooth) { isLoadingRelease = false }
    }
}

/// The update sheet's way in: its own navigation bar with "Fertig" above the sheet.
struct ManualUpdateSheet: View {
    var release: UpdateManifest?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ManualUpdateView(release: release)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Copy

enum ManualUpdateCopy {
    static let title = "Manuell aktualisieren"
    static let rowSubtitle = ".ipa laden, prüfen und mit SideStore installieren"
    static let guideURL = URL(string: "https://github.com/Jecuro1/KLIMATICKET-APP/blob/main/docs/MANUAL_UPDATE.md")!
    static let sideStoreURL = URL(string: "https://sidestore.io")!

    static func megabytes(_ bytes: Int64) -> String {
        "\(Format.number(Double(bytes) / 1_000_000, decimals: 1)) MB"
    }

    static func timeLeft(_ seconds: Int) -> String {
        seconds < 60 ? "noch ca. \(seconds) s" : "noch ca. \(Int((Double(seconds) / 60).rounded(.up))) min"
    }

    /// Settings row subtitle: what the download is doing right now.
    @MainActor
    static func rowStatus(_ downloader: ManualUpdateDownloader) -> String {
        guard let manifest = downloader.manifest else { return rowSubtitle }
        let version = SetFormat.shortVersion(manifest.version)
        switch downloader.phase {
        case .idle: return rowSubtitle
        case .downloading: return "Version \(version) wird geladen · \(Format.percent(downloader.fraction ?? 0))"
        case .paused: return "Version \(version) · \(downloader.interrupted ? "unterbrochen" : "pausiert") bei \(Format.percent(downloader.fraction ?? 0))"
        case .verifying: return "Version \(version) wird geprüft …"
        case .ready: return "Version \(version) ist geladen und geprüft"
        case .failed: return "Download fehlgeschlagen – noch einmal versuchen"
        }
    }
}

extension ManualUpdateDownloader.Phase {
    var isReady: Bool { if case .ready = self { true } else { false } }
    var isFailure: Bool { if case .failed = self { true } else { false } }
}

enum ManualUpdateLinks {
    enum Store: Equatable {
        case sideStore, altStore
        var name: String { self == .sideStore ? "SideStore" : "AltStore" }
    }

    struct Link: Identifiable {
        var store: Store
        var url: URL
        var id: String { store.name }
    }
}

// MARK: - Export

extension UTType {
    /// iOS app archive. Declared by the system as `com.apple.itunes.ipa`; resolved by extension, so an unknown
    /// declaration still exports as a plain file.
    static let ipaFile: UTType = UTType("com.apple.itunes.ipa") ?? UTType(filenameExtension: "ipa", conformingTo: .data) ?? .data
}

/// The verified .ipa for the file exporter (streamed from disk, never loaded into memory).
struct IPAFile: Transferable {
    var url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .ipaFile) { file in
            SentTransferredFile(file.url)
        }
    }
}
