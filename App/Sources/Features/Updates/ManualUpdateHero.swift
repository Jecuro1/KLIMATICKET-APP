import SwiftUI
import KlimaCore

// MARK: settings – Manuell aktualisieren: the hero card with the progress ring (split from ManualUpdateView.swift).

// MARK: - Hero: ring, status, actions

struct MUHeroCard: View {
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
struct MUProgressRing: View {
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
