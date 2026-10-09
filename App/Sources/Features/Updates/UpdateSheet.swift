import SwiftUI
import KlimaCore

/// "Update verfügbar" (DESIGN.md §5.7): app icon on a summit glow, "Version 1.1 ist da" + "Du hast 1.0", release notes
/// with feature tiles, "Jetzt aktualisieren" (CTA), optional "AltStore-Quelle hinzufügen" (tinted secondary) and "Später".
/// Presented by RootView (`app.updates.isPresentingSheet`) or from Einstellungen › Updates.
struct UpdateSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appeared = false
    @State private var installTrigger = 0
    /// The update shown when the sheet opened. A background re-check (scene becoming active) briefly sets the
    /// service state to `.checking` – or `.failed` offline – which must not flip the open sheet to "Alles aktuell".
    @State private var pinnedManifest: UpdateManifest? = nil
    @State private var pinnedRequired = false
    /// "AltStore-Quelle hinzufügen" was not handled (AltStore not installed). Shown inline – the global toast
    /// is hidden behind this sheet.
    @State private var altStoreMissing = false

    private var manifest: UpdateManifest? { app.updates.availableManifest ?? pinnedManifest }
    private var isRequired: Bool {
        app.updates.availableManifest == nil ? pinnedRequired : app.updates.isRequired
    }
    private var animates: Bool { !(reduceMotion || LaunchMode.isScreenshot) }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                UpdHero(manifest: manifest, installed: app.updates.installedVersion, installedBuild: app.updates.installedBuild,
                        isRequired: isRequired, appeared: appeared, animates: animates)
                if let manifest {
                    UpdNotesCard(notes: manifest.releaseNotes, appeared: appeared, animates: animates)
                    if let tariffs = manifest.tariffsVersion, tariffs > app.catalog.version {
                        tariffsHint(tariffs)
                    }
                } else {
                    upToDateCard
                }
                if isRequired {
                    requiredNotice
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.l)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actions
        }
        .background { SetBackdrop(skyOpacity: 0.6, fadeEnd: 0.6) }
        .tint(Theme.accent)
        .presentationDetents([.large])
        .presentationDragIndicator(isRequired ? .hidden : .visible)
        .interactiveDismissDisabled(isRequired)
        .settingsHaptic(.success, trigger: installTrigger, enabled: app.settings.hapticsEnabled)
        .onAppear {
            if pinnedManifest == nil, let current = app.updates.availableManifest {
                pinnedManifest = current
                pinnedRequired = app.updates.isRequired
            }
            guard !appeared else { return }
            if animates {
                withAnimation(.spring(duration: 0.7, bounce: 0.28)) { appeared = true }
            } else {
                appeared = true
            }
        }
    }

    // MARK: Cards

    private var upToDateCard: some View {
        SurfaceCard(padding: Theme.Spacing.l, cornerRadius: Theme.Radius.formGroup) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.positive)
                Text("Du hast bereits die neueste Version von KlimaBilanz.")
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tariffsHint(_ version: Int) -> some View {
        Label {
            Text("Inklusive aktueller Ticketpreise (Tarif-Version \(version))")
        } icon: {
            Image(systemName: "tag.fill").foregroundStyle(Theme.summit)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.xs)
        .glassEffect(.regular, in: .capsule)
    }

    private var requiredNotice: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(Theme.summit)
                .accessibilityHidden(true)
            Text("Diese Version wird nicht mehr unterstützt. Bitte aktualisiere, damit Preise, Prognosen und Sync weiter stimmen.")
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.summit.opacity(0.13), in: .rect(cornerRadius: Theme.Radius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private var isSideStore: Bool { app.updates.sideloadStore == .sideStore }

    /// The source matching the store this copy was installed with (none for App Store / TestFlight builds).
    private var sourceURL: URL? {
        guard app.updates.showsSideloadOptions else { return nil }
        return isSideStore ? app.updates.sideStoreSourceURL : app.updates.altStoreSourceURL
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.s) {
            if manifest != nil {
                Button {
                    installTrigger += 1
                    if app.updates.availableManifest == nil, let url = manifest.flatMap({ URL(string: $0.downloadURL) }) {
                        openURL(url)   // service is mid re-check – fall back to the pinned release's download
                    } else {
                        app.updates.install()
                    }
                } label: {
                    Label(app.updates.installActionTitle, systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.primary)

                if let source = sourceURL {
                    Button {
                        openURL(source) { accepted in
                            withAnimation(.snappy) { altStoreMissing = !accepted }
                        }
                    } label: {
                        Label(isSideStore ? "SideStore-Quelle hinzufügen" : "AltStore-Quelle hinzufügen", systemImage: "plus.square.on.square")
                    }
                    .buttonStyle(UpdSecondaryButtonStyle())

                    if altStoreMissing {
                        Text(isSideStore ? "SideStore ist auf diesem iPhone nicht installiert." : "AltStore ist auf diesem iPhone nicht installiert. Mit SideStore fügst du die Quelle unter Einstellungen › Updates hinzu.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                }
            }
            if !isRequired {
                Button(laterTitle) {
                    later()
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .padding(.vertical, Theme.Spacing.xxs)
            }
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.top, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.xs)
        .background {
            LinearGradient(stops: [.init(color: Theme.sheetBackground.opacity(0), location: 0),
                                   .init(color: Theme.sheetBackground.opacity(0.94), location: 0.28),
                                   .init(color: Theme.sheetBackground, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    private var laterTitle: String { manifest == nil ? "Schließen" : "Später" }

    private func later() {
        if manifest != nil { app.updates.dismissCurrent() }
        dismiss()
    }
}

// MARK: - Hero

private struct UpdHero: View {
    var manifest: UpdateManifest?
    var installed: SemanticVersion
    var installedBuild: Int
    var isRequired: Bool
    var appeared: Bool
    var animates: Bool

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            iconScene
            // The version is named once (title) – an eyebrow only when it carries news of its own.
            if isRequired {
                Kicker(text: "Update erforderlich", color: Theme.summitText)
                    .padding(.top, Theme.Spacing.xs)
            }
            Text(title)
                .font(Theme.Typography.heroTitle)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, isRequired ? 0 : Theme.Spacing.xs)
            VStack(spacing: Theme.Spacing.xs) {
                installedPill
                if let manifest, let date = SetFormat.isoDateTime(manifest.publishedAt) {
                    Text("Veröffentlicht am \(Format.date(date, .long))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.top, Theme.Spacing.xxs)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// Same version, newer build (re-signed / hotfix build): the build is the only thing that differs.
    private var isBuildOnly: Bool {
        guard let manifest else { return false }
        return manifest.version <= installed
    }

    private var title: String {
        guard let manifest else { return "Alles aktuell" }
        let version = SetFormat.shortVersion(manifest.version)
        return isBuildOnly ? "Update für Version \(version)" : "Version \(version) ist da"
    }

    /// Icon on a dawn glow in front of two faint ridges – the summit motif.
    private var iconScene: some View {
        ZStack {
            RidgeShape(peakX: 0.72, peakY: 0.34, seed: 11, roughness: 1)
                .fill(LinearGradient(colors: [Theme.dusk.opacity(0.18), Theme.dusk.opacity(0)], startPoint: .top, endPoint: .bottom))
            RidgeShape(peakX: 0.3, peakY: 0.5, seed: 4, roughness: 0.9)
                .fill(LinearGradient(colors: [Theme.glacier.opacity(0.16), Theme.glacier.opacity(0)], startPoint: .top, endPoint: .bottom))
            Circle()
                .fill(RadialGradient(colors: [Theme.dawn.opacity(0.5), Theme.alpenglow.opacity(0.18), Theme.dawn.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: 110))
                .frame(width: 220, height: 220)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
            SetAppIconView(size: 100)
                .shadow(color: Theme.dusk.opacity(0.35), radius: 26, y: 14)
                .scaleEffect(appeared ? 1 : 0.8)
                .opacity(appeared ? 1 : 0)
        }
        .frame(height: 172)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, -Theme.Spacing.screen)
        .accessibilityHidden(true)
    }

    /// "Du hast 1.0" – the installed version in the same short form as the title ("Build 7" for build-only updates).
    private var installedPill: some View {
        let value = isBuildOnly ? "Build \(installedBuild)" : SetFormat.shortVersion(installed)
        let lead = manifest == nil ? "Version" : "Du hast"
        return HStack(spacing: 6) {
            Image(systemName: "iphone")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
            Text(lead)
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textPrimary)
        }
        .font(.subheadline.monospacedDigit())
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isBuildOnly ? "Installiert ist \(value)" : "Installierte Version \(value)")
    }
}

// MARK: - Release notes

private struct UpdNotesCard: View {
    var notes: [String]
    var appeared: Bool
    var animates: Bool

    private var lines: [String] { notes.isEmpty ? ["Fehlerbehebungen und Verbesserungen"] : notes }

    /// Staggered entrance (≤ ~1.1 s in total); nil = no animation (Reduce Motion, screenshots).
    private func entrance(_ index: Int) -> Animation? {
        guard animates else { return nil }
        let delay: Double = 0.16 + Double(min(index, 6)) * 0.07
        return Animation.spring(duration: 0.55, bounce: 0.2).delay(delay)
    }

    var body: some View {
        SurfaceCard(padding: Theme.Spacing.l, cornerRadius: Theme.Radius.formGroup) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Kicker(text: "Was ist neu")
                ForEach(Array(lines.enumerated()), id: \.offset) { index, note in
                    UpdNoteRow(text: note)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 12)
                        .animation(entrance(index), value: appeared)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Was ist neu")
    }
}

/// One release note: a feature tile (Settings-style, so "new" never reads as "done") + the line.
private struct UpdNoteRow: View {
    var text: String

    var body: some View {
        let feature = UpdFeature(note: text)
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            SetIconTile(symbol: feature.symbol, tint: feature.tint, size: 30)
            Text(text)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// Picks a symbol + colour for a free-form release note by keyword; falls back to a glacier sparkle.
private struct UpdFeature {
    var symbol: String
    var tint: Color

    init(note: String) {
        let match = Self.match(note.lowercased(with: Locale(identifier: "de_AT")))
        symbol = match.symbol
        tint = match.tint
    }

    private static func match(_ s: String) -> (symbol: String, tint: Color) {
        func has(_ words: String...) -> Bool { words.contains { s.contains($0) } }
        if has("widget") { return ("rectangle.stack.fill", Theme.dusk) }
        if has("such", "search", "finde") { return ("magnifyingglass", Theme.glacier) }
        if has("preis", "tarif", "€", "kosten") { return ("eurosign", Theme.dawn) }
        if has("sync", "icloud", "konto", "anmeld") { return ("arrow.triangle.2.circlepath", Theme.glacier) }
        if has("co₂", "co2", "umwelt", "emission") { return ("leaf.fill", Theme.pine) }
        if has("statistik", "diagramm", "auswertung") { return ("chart.bar.fill", Theme.dusk) }
        if has("erinner", "mitteilung", "benachrichtig") { return ("bell.fill", Theme.alpenglow) }
        if has("karte", "route", "strecke", "haltestelle", "bahnhof") { return ("map.fill", Theme.pine) }
        if has("ticket") { return ("ticket.fill", Theme.dawn) }
        if has("fehler", "stabil", "absturz", "bug") { return ("wrench.and.screwdriver.fill", Theme.pine) }
        if has("design", "darstellung", "dunkel") { return ("paintbrush.fill", Theme.alpenglow) }
        return ("sparkle", Theme.glacier)
    }
}

// MARK: - Secondary button

/// Calm tinted capsule for the secondary action ("AltStore-Quelle hinzufügen"): one step below the CTA, and – unlike
/// Liquid Glass over the opaque action bar – never a dark slab in dark mode.
private struct UpdSecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let dark = colorScheme == .dark
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.accentText)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                Capsule().fill(Theme.accent.opacity(configuration.isPressed ? (dark ? 0.24 : 0.18) : (dark ? 0.15 : 0.11)))
            }
            .overlay {
                Capsule().strokeBorder(
                    LinearGradient(colors: [Theme.glacier2.opacity(dark ? 0.32 : 0.55), Theme.accent.opacity(dark ? 0.08 : 0.10)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            }
            .contentShape(.capsule)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}
