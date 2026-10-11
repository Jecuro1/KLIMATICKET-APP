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

// MARK: - Hero: ring, status, actions

private struct MUHeroCard: View {
    var release: UpdateManifest
    var downloader: ManualUpdateDownloader
    var phase: ManualUpdateDownloader.Phase
    var installed: SemanticVersion
    var installedBuild: Int
    var storeName: String
    @Binding var isExporting: Bool
    var savedToFiles: Bool
    @Binding var tapTrigger: Int

    @State private var readyTrigger = 0

    private var isNewer: Bool {
        release.version > installed || (release.version == installed && release.build > installedBuild)
    }

    private var fraction: Double { downloader.matches(release) ? (downloader.fraction ?? 0) : 0 }

    var body: some View {
        SurfaceCard(padding: Theme.Spacing.l, cornerRadius: Theme.Radius.formGroup) {
            VStack(spacing: Theme.Spacing.m) {
                MUProgressRing(phase: phase, fraction: fraction, readyTrigger: readyTrigger)
                    .padding(.top, Theme.Spacing.xs)
                VStack(spacing: 4) {
                    Kicker(text: isNewer ? "Neue Version" : "Installierte Version", color: isNewer ? Theme.accentText : Theme.textSecondary)
                    Text("KlimaBilanz \(SetFormat.shortVersion(release.version))")
                        .font(Theme.Typography.title)
                        .fontDesign(.rounded)
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(meta)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                status
                actions
            }
            .frame(maxWidth: .infinity)
        }
        .motionAnimation(Motion.smooth, value: phase)
        .onChange(of: phase.isReady) { old, new in
            if !old && new { readyTrigger += 1 }
        }
    }

    private var meta: String {
        var parts = ["Build \(release.build)"]
        if let size = ManualUpdate.expectedSize(release, announced: downloader.matches(release) ? downloader.total : nil) {
            parts.append(ManualUpdateCopy.megabytes(size))
        }
        if let date = SetFormat.isoDateTime(release.publishedAt) { parts.append(Format.date(date)) }
        return parts.joined(separator: " · ")
    }

    // MARK: Status line

    private struct Status {
        var symbol: String
        var text: String
        var color: Color
    }

    private var currentStatus: Status {
        switch phase {
        case .idle:
            return Status(symbol: "arrow.down.circle", text: isNewer ? "Bereit zum Herunterladen" : "Zum erneuten Installieren laden",
                          color: Theme.textSecondary)
        case .downloading:
            var text = "\(ManualUpdateCopy.megabytes(downloader.received)) von \(ManualUpdateCopy.megabytes(downloader.total ?? 0))"
            if let left = downloader.secondsLeft { text += " · \(ManualUpdateCopy.timeLeft(left))" }
            return Status(symbol: "arrow.down.circle.fill", text: text, color: Theme.accentText)
        case .paused:
            let text = downloader.interrupted ? "Verbindung unterbrochen – geladene Daten bleiben" : "Pausiert – geladene Daten bleiben"
            return Status(symbol: downloader.interrupted ? "wifi.exclamationmark" : "pause.circle.fill", text: text, color: Theme.summitText)
        case .verifying:
            return Status(symbol: "checkmark.shield", text: "Prüfsumme wird geprüft …", color: Theme.textSecondary)
        case .ready(let verification):
            return verification == .verified
                ? Status(symbol: "checkmark.seal.fill", text: "Geprüft: SHA-256 stimmt – die Datei ist echt", color: Theme.positiveText)
                : Status(symbol: "checkmark.circle.fill", text: "Geladen – vollständig, ohne Prüfsumme im Update-Manifest", color: Theme.positiveText)
        case .failed(let failure):
            let text: String
            switch failure {
            case .offline: text = "Keine Verbindung – versuch es gleich noch einmal"
            case .server: text = "Der Download-Server hat nicht geantwortet"
            case .storage: text = "Zu wenig Speicherplatz auf dem iPhone"
            case .corrupted: text = "Die Datei war beschädigt und wurde gelöscht – lade sie neu"
            }
            return Status(symbol: "exclamationmark.triangle.fill", text: text, color: Theme.negativeText)
        }
    }

    private var status: some View {
        let status = currentStatus
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: status.symbol)
                .symbolReplaceTransition()
            Text(status.text)
                .contentTransition(.opacity)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline.weight(.medium).monospacedDigit())
        .foregroundStyle(status.color)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: Theme.Spacing.s) {
            switch phase {
            case .idle, .failed:
                Button {
                    tapTrigger += 1
                    downloader.start(release)
                } label: {
                    Label(phase.isFailure ? "Erneut herunterladen" : "Herunterladen", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.primary)
                .motionTransition(.rise)
            case .downloading:
                Button {
                    tapTrigger += 1
                    downloader.pause()
                } label: {
                    Label("Pausieren", systemImage: "pause.fill")
                }
                .buttonStyle(UpdSecondaryButtonStyle())
                .motionTransition(.rise)
                discardButton("Abbrechen")
            case .paused:
                Button {
                    tapTrigger += 1
                    downloader.start(release)
                } label: {
                    Label("Fortsetzen", systemImage: "play.fill")
                }
                .buttonStyle(.primary)
                .motionTransition(.rise)
                discardButton("Verwerfen")
            case .verifying:
                Button {} label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        ProgressView().tint(Theme.onAccent)
                        Text("Wird geprüft …")
                    }
                }
                .buttonStyle(.primary)
                .disabled(true)
            case .ready:
                if let url = downloader.fileURL {
                    ShareLink(item: url, preview: SharePreview(ManualUpdate.fileName(for: release), image: Image(systemName: "app.badge"))) {
                        Label("In \(storeName) öffnen", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.primary)
                    .motionTransition(.rise)
                    .accessibilityHint("Öffnet das Teilen-Menü. Wähle dort \(storeName).")
                    Text("Im Teilen-Menü \(storeName) wählen – es installiert die neue Version über die alte, deine Daten bleiben.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        isExporting = true
                    } label: {
                        Label(savedToFiles ? "In Dateien gesichert" : "In Dateien sichern",
                              systemImage: savedToFiles ? "checkmark.circle.fill" : "folder.fill")
                            .contentTransition(.opacity)
                    }
                    .buttonStyle(UpdSecondaryButtonStyle())
                    discardButton("Datei löschen")
                }
            }
        }
        .padding(.top, Theme.Spacing.xxs)
    }

    private func discardButton(_ title: String) -> some View {
        Button(role: .destructive) {
            tapTrigger += 1
            withMotion(Motion.smooth) { downloader.discard() }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 120, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .foregroundStyle(Theme.textSecondary)
    }
}

/// The ring fills with the download. Idle and done it frames the app icon; while loading it shows the percentage.
private struct MUProgressRing: View {
    var phase: ManualUpdateDownloader.Phase
    var fraction: Double
    var readyTrigger: Int

    @ScaledMetric(relativeTo: .title) private var side: CGFloat = 150
    private let lineWidth: CGFloat = 10

    /// Half-percent steps: the spring re-targets ~200 times per download instead of on every network packet.
    private var shown: Double { (min(max(fraction, 0), 1) * 200).rounded() / 200 }

    private var ringColors: [Color] {
        switch phase {
        case .ready: [Theme.pine, Theme.positive]
        case .paused: [Theme.dawn, Theme.summit]
        case .failed: [Theme.negative, Theme.negative]
        default: [Theme.glacier2, Theme.glacier, Theme.dusk]
        }
    }

    var body: some View {
        let size = min(side, 210)
        ZStack {
            Circle()
                .stroke(Theme.separator, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: phase.isReady ? 1 : shown)
                .stroke(LinearGradient(colors: ringColors, startPoint: .topTrailing, endPoint: .bottomLeading),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: (ringColors.last ?? Theme.accent).opacity(0.35), radius: 8)
                .motionAnimation(Motion.smooth, value: shown)
            center
                .frame(width: size - lineWidth * 2 - 18, height: size - lineWidth * 2 - 18)
        }
        .frame(width: size, height: size)
        .celebrationRing(trigger: readyTrigger, color: Theme.pine)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Download")
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var center: some View {
        switch phase {
        case .downloading, .paused:
            VStack(spacing: 0) {
                Text(Format.percent(shown))
                    .font(Theme.Typography.numberLarge)
                    .foregroundStyle(Theme.textPrimary)
                    .numericValue(shown)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(phase == .paused ? "pausiert" : "geladen")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.opacity)
            }
            .motionTransition(.pop)
        case .verifying:
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .motionTransition(.pop)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Theme.negative)
                .motionTransition(.pop)
        case .idle, .ready:
            SetAppIconView(size: 74)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: phase.isReady ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 26, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, phase.isReady ? Theme.pine : Theme.accent)
                        .background(Circle().fill(Theme.sheetBackground).padding(2))
                        .symbolReplaceTransition()
                        .symbolBounce(on: readyTrigger)
                        .offset(x: 8, y: 8)
                }
                .motionTransition(.pop)
        }
    }

    private var accessibilityValue: String {
        switch phase {
        case .idle: "Noch nicht geladen"
        case .downloading: "\(Format.percent(shown)) geladen"
        case .paused: "Pausiert bei \(Format.percent(shown))"
        case .verifying: "Wird geprüft"
        case .ready: "Fertig geladen und geprüft"
        case .failed: "Fehlgeschlagen"
        }
    }
}

// MARK: - Cards

/// The honest part: iOS itself installs no .ipa.
private struct MUHonestNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: "info.circle.fill")
                .font(.headline)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("iOS installiert .ipa-Dateien nicht selbst. KlimaBilanz lädt die Datei und prüft, ob sie echt ist – installieren kann sie SideStore oder AltStore.")
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.10), in: .rect(cornerRadius: Theme.Radius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Without the in-app download: the store fetches the .ipa itself (`sidestore://install?url=`).
private struct MUOneTapCard: View {
    var links: [ManualUpdateLinks.Link]
    @Binding var missing: ManualUpdateLinks.Store?
    @Environment(\.openURL) private var openURL

    var body: some View {
        if !links.isEmpty {
            SurfaceCard(padding: Theme.Spacing.l, cornerRadius: Theme.Radius.formGroup) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Kicker(text: "Schneller: ohne Umweg")
                        .accessibilityAddTraits(.isHeader)
                    ForEach(links) { link in
                        Button {
                            openURL(link.url) { accepted in
                                withMotion(Motion.smooth) { missing = accepted ? nil : link.store }
                            }
                        } label: {
                            HStack(spacing: Theme.Spacing.s) {
                                SetIconTile(symbol: link.store == .sideStore ? "square.stack.3d.up.fill" : "plus.square.on.square",
                                            tint: link.store == .sideStore ? Theme.modeColor(.tram) : Theme.modeColor(.sBahn), size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Direkt in \(link.store.name) installieren")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("\(link.store.name) lädt die Datei selbst – ein Tipp")
                                        .font(.footnote)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                .multilineTextAlignment(.leading)
                                Spacer(minLength: Theme.Spacing.xs)
                                Image(systemName: "arrow.up.forward")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.pressableCard)
                        if missing == link.store {
                            Text("\(link.store.name) ist auf diesem iPhone nicht installiert.")
                                .font(.footnote)
                                .foregroundStyle(Theme.negativeText)
                                .motionTransition(.rise)
                        }
                    }
                }
            }
            .haptic(.error, trigger: missing, when: { _, new in new != nil })
        }
    }
}

/// Three illustrated steps: Dateien → Teilen → SideStore.
private struct MUGuideCard: View {
    var fileName: String
    var storeName: String
    var isReady: Bool

    var body: some View {
        SurfaceCard(padding: Theme.Spacing.l, cornerRadius: Theme.Radius.formGroup) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Kicker(text: "Später installieren – in 3 Schritten")
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 0) {
                    MUStepRow(number: 1, art: .files, title: "In Dateien öffnen",
                              text: "Sichere die Datei mit „In Dateien sichern“ und öffne in der Dateien-App „\(fileName)“.",
                              isLast: false)
                    MUStepRow(number: 2, art: .share, title: "Teilen tippen",
                              text: "Halte die Datei gedrückt und tippe auf „Teilen“.", isLast: false)
                    MUStepRow(number: 3, art: .store(storeName), title: "\(storeName) wählen",
                              text: "Tippe in der App-Reihe auf \(storeName). Es installiert die neue Version über die alte – deine Fahrten bleiben.",
                              isLast: true)
                }
            }
        }
    }
}

private struct MUStepRow: View {
    enum Art: Equatable {
        case files, share, store(String)
    }

    var number: Int
    var art: Art
    var title: String
    var text: String
    var isLast: Bool

    @ScaledMetric(relativeTo: .body) private var artSide: CGFloat = 52

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            VStack(spacing: 0) {
                MUStepArt(art: art, number: number)
                    .frame(width: min(artSide, 72), height: min(artSide, 72))
                if !isLast {
                    Rectangle()
                        .fill(Theme.separator)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, 6)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
            .padding(.bottom, isLast ? 0 : Theme.Spacing.m)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Schritt \(number): \(title). \(text)")
    }
}

/// Small illustration per step: the Files folder with an .ipa, the share sheet, the store's install arrow.
private struct MUStepArt: View {
    var art: MUStepRow.Art
    var number: Int

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.26, style: .continuous)
                    .fill(LinearGradient(colors: [tint, tint.mix(with: .black, by: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: tint.opacity(0.3), radius: 6, y: 3)
                content(side: side)
                    .foregroundStyle(.white)
            }
            .overlay(alignment: .topLeading) {
                Text(verbatim: "\(number)")
                    .font(.system(size: max(11, side * 0.22), weight: .bold, design: .rounded))
                    .foregroundStyle(tint.mix(with: .black, by: 0.25))
                    .frame(width: side * 0.38, height: side * 0.38)
                    .background(Circle().fill(.white))
                    .offset(x: -side * 0.12, y: -side * 0.12)
            }
            .environment(\.colorScheme, .light)
        }
        .accessibilityHidden(true)
    }

    private var tint: Color {
        switch art {
        case .files: Theme.glacier
        case .share: Theme.dusk
        case .store: Theme.pine
        }
    }

    @ViewBuilder
    private func content(side: CGFloat) -> some View {
        switch art {
        case .files:
            Image(systemName: "folder.fill")
                .font(.system(size: side * 0.44, weight: .semibold))
                .overlay(alignment: .bottomTrailing) {
                    Text(verbatim: ".ipa")
                        .font(.system(size: side * 0.15, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.glacier)
                        .padding(.horizontal, 3)
                        .background(Capsule().fill(.white))
                        .offset(x: side * 0.12, y: side * 0.06)
                }
        case .share:
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: side * 0.42, weight: .semibold))
                .offset(y: -side * 0.03)
        case .store:
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: side * 0.44, weight: .semibold))
        }
    }
}

private struct MUNoReleaseCard: View {
    var isLoading: Bool
    var retry: () -> Void

    var body: some View {
        SurfaceCard(padding: Theme.Spacing.l, cornerRadius: Theme.Radius.formGroup) {
            VStack(spacing: Theme.Spacing.s) {
                Image(systemName: isLoading ? "arrow.triangle.2.circlepath" : "icloud.slash")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .symbolReplaceTransition()
                    .setBusySymbol(isLoading)
                Text(isLoading ? "Suche die neueste Version …" : "Keine Version gefunden")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.opacity)
                if !isLoading {
                    Text("Die Update-Quelle war nicht erreichbar. Prüf deine Verbindung und versuch es noch einmal.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Erneut suchen", action: retry)
                        .buttonStyle(UpdSecondaryButtonStyle())
                        .padding(.top, Theme.Spacing.xs)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct MUNoSideloadCard: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        MUInfoCard(symbol: "questionmark.app.fill", tint: Theme.dawn, kicker: "Keine Sideload-App?",
                   text: "Ohne SideStore oder AltStore kann iOS die Datei nicht öffnen. SideStore ist kostenlos und braucht nur deine Apple-ID – dafür musst du die App alle 7 Tage in SideStore auffrischen.",
                   linkTitle: "Anleitung öffnen") {
            openURL(ManualUpdateCopy.guideURL)
        }
    }
}

private struct MUDeveloperCard: View {
    var isActive: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        MUInfoCard(symbol: "checkmark.seal.fill", tint: Theme.dusk, kicker: "Mit Apple-Entwicklerkonto",
                   text: isActive
                       ? "Auf diesem iPhone aktiv: Updates kommen mit „Jetzt installieren“ direkt über iOS – ganz ohne Zusatz-App."
                       : "Mit einem bezahlten Apple-Entwicklerkonto bekommt dein registriertes iPhone einen direkten Installationslink. Dann installiert iOS Updates selbst – ganz ohne Zusatz-App.",
                   linkTitle: "Direkt installieren einrichten") {
            openURL(Copy.Updates.directInstallGuideURL)
        }
    }
}

private struct MUInfoCard: View {
    var symbol: String
    var tint: Color
    var kicker: String
    var text: String
    var linkTitle: String
    var action: () -> Void

    var body: some View {
        SurfaceCard(padding: Theme.Spacing.l, cornerRadius: Theme.Radius.formGroup) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.s) {
                    SetIconTile(symbol: symbol, tint: tint, size: 30)
                    Kicker(text: kicker)
                        .accessibilityAddTraits(.isHeader)
                }
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: action) {
                    HStack(spacing: 4) {
                        Text(linkTitle)
                        Image(systemName: "arrow.up.forward")
                            .font(.footnote.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.pressable)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

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
