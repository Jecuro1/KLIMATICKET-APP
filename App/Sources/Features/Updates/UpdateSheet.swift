import SwiftUI
import KlimaCore

/// "Update verfügbar" (DESIGN.md §5.7): app icon on a summit glow, "Version 1.1 ist da" + "Du hast 1.0", release notes
/// with feature tiles, the channel CTA ("Update herunterladen" …), optional "AltStore-Quelle hinzufügen" (tinted) and "Später".
/// Presented by RootView (`app.updates.isPresentingSheet`) or from Einstellungen › Updates.
///
/// Motion (docs/MOTION.md): one entrance in reading order – the icon pops onto its glow and sends out one ring, the
/// title focuses in, the notes rise one by one, the buttons last. The CTA shows the hand-off: its arrow turns into a
/// spinner while the store opens and into a check ("Weiter in AltStore") once it took over – or says that it could not.
struct UpdateSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// The install button's hand-off to the store / TestFlight / Safari.
    private enum Handoff: Equatable {
        case idle, opening, handedOver, failed
    }

    @State private var handoff: Handoff = .idle
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

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                UpdHero(manifest: manifest, installed: app.updates.installedVersion, installedBuild: app.updates.installedBuild,
                        isRequired: isRequired)
                if let manifest {
                    UpdNotesCard(notes: manifest.releaseNotes)
                    if let tariffs = manifest.tariffsVersion, tariffs > app.catalog.version {
                        tariffsHint(tariffs)
                            .reveal(order: 8)
                    }
                } else {
                    upToDateCard
                        .reveal(order: 3)
                }
                if isRequired {
                    requiredNotice
                        .reveal(order: 8)
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
                .reveal(order: 5)
        }
        .revealScope()
        .background { SetBackdrop(skyOpacity: 0.6, fadeEnd: 0.6) }
        .tint(Theme.accent)
        .presentationDetents([.large])
        .presentationDragIndicator(isRequired ? .hidden : .visible)
        .interactiveDismissDisabled(isRequired)
        // One haptic per step of the install: a tap when it starts, an error if nothing could be opened.
        .haptic(.tap, trigger: installTrigger)
        .haptic(.error, trigger: handoff, when: { _, new in new == .failed })
        .onAppear {
            if pinnedManifest == nil, let current = app.updates.availableManifest {
                pinnedManifest = current
                pinnedRequired = app.updates.isRequired
            }
        }
        .onDisappear {
            // Swiped away counts like "Später" – otherwise the same release pops up again after every 6-hour check.
            // A required update cannot be swiped away and keeps presenting itself.
            guard !isRequired, let manifest else { return }
            app.updates.rememberDismissal(of: manifest)
        }
    }

    // MARK: Cards

    private var upToDateCard: some View {
        SurfaceCard(padding: Theme.Spacing.l, cornerRadius: Theme.Radius.formGroup) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.positive)
                    .modifier(UpdAttentionSymbol(effect: .bounce))
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
                .modifier(UpdAttentionSymbol(effect: .wiggle))
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
                Button(action: install) {
                    installLabel
                }
                .buttonStyle(.primary)
                .accessibilityLabel(app.updates.installActionTitle)
                .accessibilityValue(handoffAccessibilityValue)

                if handoff == .failed {
                    Text("Das hat nicht geklappt – versuch es gleich noch einmal.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .motionTransition(.rise)
                }

                if let source = sourceURL {
                    Button {
                        openURL(source) { accepted in
                            withMotion(Motion.smooth) { altStoreMissing = !accepted }
                            if !accepted { AccessibilityNotification.Announcement(storeMissingText).post() }
                        }
                    } label: {
                        Label(isSideStore ? "SideStore-Quelle hinzufügen" : "AltStore-Quelle hinzufügen", systemImage: "plus.square.on.square")
                    }
                    .buttonStyle(UpdSecondaryButtonStyle())

                    if altStoreMissing {
                        Text(storeMissingText)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .motionTransition(.rise)
                    }
                }
            }
            if !isRequired {
                Button {
                    later()
                } label: {
                    Text(laterTitle)
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 160, minHeight: 44)   // HIG hit target, not just the word
                        .contentShape(.rect)
                }
                .buttonStyle(.pressable)
                .foregroundStyle(Theme.accentText)
            }
        }
        .motionAnimation(Motion.snappy, value: handoff)
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.top, Theme.Spacing.m)
        .padding(.bottom, isRequired ? Theme.Spacing.xs : 0)
        .background {
            LinearGradient(stops: [.init(color: Theme.sheetBackground.opacity(0), location: 0),
                                   .init(color: Theme.sheetBackground.opacity(0.94), location: 0.28),
                                   .init(color: Theme.sheetBackground, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    private var laterTitle: String { manifest == nil ? "Schließen" : "Später" }

    /// "In AltStore aktualisieren" ⟶ spinner "Wird geöffnet …" ⟶ check "Weiter in AltStore": the symbol morphs in
    /// place, the text cross-fades, the capsule keeps its size.
    private var installLabel: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ZStack {
                if handoff == .opening {
                    ProgressView()
                        .tint(Theme.onAccent)
                        .motionTransition(.pop)
                } else {
                    Image(systemName: handoff == .handedOver ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                        .symbolReplaceTransition()
                        .motionTransition(.pop)
                }
            }
            .frame(minWidth: 24)
            Text(installTitle)
                .contentTransition(.opacity)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var installTitle: String {
        switch handoff {
        case .idle, .failed: app.updates.installActionTitle
        case .opening: "Wird geöffnet …"
        case .handedOver: app.updates.installHandoffTitle
        }
    }

    private var handoffAccessibilityValue: String {
        switch handoff {
        case .idle: ""
        case .opening: "Wird geöffnet"
        case .handedOver: app.updates.installHandoffTitle
        case .failed: "Konnte nicht geöffnet werden"
        }
    }

    /// Opens the channel's install route and shows the hand-off. Back in the app a few seconds later, the button is
    /// ready for another try.
    private func install() {
        guard handoff != .opening else { return }
        installTrigger += 1
        withMotion(Motion.snappy) { handoff = .opening }
        Task {
            let opened: Bool
            if app.updates.availableManifest == nil, let url = pinnedInstallURL {
                // The service is mid re-check (or offline) – fall back to the pinned release.
                opened = await withCheckedContinuation { continuation in
                    openURL(url) { continuation.resume(returning: $0) }
                }
            } else {
                opened = await app.updates.install()
            }
            withMotion(Motion.snappy) { handoff = opened ? .handedOver : .failed }
            guard opened else { return }
            try? await Task.sleep(for: .seconds(3))
            if handoff == .handedOver { withMotion(Motion.smooth) { handoff = .idle } }
        }
    }

    private var storeMissingText: String {
        isSideStore ? "SideStore ist auf diesem iPhone nicht installiert."
            : "AltStore ist auf diesem iPhone nicht installiert. Mit SideStore fügst du die Quelle unter Einstellungen › Updates hinzu."
    }

    /// Where the CTA goes when the service has no current release (re-check in flight, offline): the channel's own
    /// store first – a TestFlight copy must never be sent to the raw .ipa – then the pinned release's download.
    private var pinnedInstallURL: URL? {
        switch app.updates.channel {
        case .testFlight: return app.updates.testFlightURL
        case .appStore: return app.updates.appStoreURL ?? manifest.flatMap { URL(string: $0.downloadURL) }
        case .sideloaded, .development: return manifest.flatMap { URL(string: $0.downloadURL) }
        }
    }

    private func later() {
        if let manifest { app.updates.rememberDismissal(of: manifest) }
        app.updates.isPresentingSheet = false
        dismiss()
    }
}

// MARK: - Hero

private struct UpdHero: View {
    var manifest: UpdateManifest?
    var installed: SemanticVersion
    var installedBuild: Int
    var isRequired: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// One ring leaves the icon once it has landed – "something new arrived". Not for "Alles aktuell".
    @State private var ringTrigger = 0

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            iconScene
            // The version is named once (title) – an eyebrow only when it carries news of its own.
            if isRequired {
                Kicker(text: "Update erforderlich", color: Theme.summitText)
                    .padding(.top, Theme.Spacing.xs)
                    .reveal(order: 1)
            }
            Text(title)
                .font(Theme.Typography.heroTitle)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, isRequired ? 0 : Theme.Spacing.xs)
                .reveal(.focus, order: 1)
            VStack(spacing: Theme.Spacing.xs) {
                installedPill
                if let manifest, let date = SetFormat.isoDateTime(manifest.publishedAt) {
                    Text("Veröffentlicht am \(Format.date(date, .long))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.top, Theme.Spacing.xxs)
            .reveal(order: 2)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Same version, newer build (TestFlight / re-signed hotfix): the build is the only thing that differs.
    private var isBuildOnly: Bool {
        guard let manifest else { return false }
        return manifest.version == installed && manifest.build > installedBuild
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
                .reveal(.fade)
            SetAppIconView(size: 100)
                .shadow(color: Theme.dusk.opacity(0.35), radius: 26, y: 14)
                .celebrationRing(trigger: ringTrigger, color: Theme.dawn)
                .reveal(.pop)
        }
        .frame(height: 172)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, -Theme.Spacing.screen)
        .accessibilityHidden(true)
        .task {
            guard manifest != nil, !reduceMotion, !MotionPolicy.isStatic else { return }
            try? await Task.sleep(for: .milliseconds(380))   // the icon has popped into place
            ringTrigger += 1
        }
    }

    /// "Du hast 1.0" – the installed version in the same short form as the title. A build-only update has no new
    /// version to name, so there the pill carries the step itself: "Build 7 → 8".
    private var installedPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "iphone")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
            if let manifest, isBuildOnly {
                Text(verbatim: "Build \(installedBuild)")
                    .foregroundStyle(Theme.textSecondary)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
                Text(verbatim: "\(manifest.build)")
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
            } else {
                Text(manifest == nil ? "Version" : "Du hast")
                    .foregroundStyle(Theme.textSecondary)
                Text(SetFormat.shortVersion(installed))
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .font(.subheadline.monospacedDigit())
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pillAccessibilityLabel)
    }

    private var pillAccessibilityLabel: String {
        if let manifest, isBuildOnly { return "Von Build \(installedBuild) auf Build \(manifest.build)" }
        return "Installierte Version \(SetFormat.shortVersion(installed))"
    }
}

// MARK: - Release notes

/// The card rises in after the title; its notes follow one by one inside it (the sheet's one staggered block).
private struct UpdNotesCard: View {
    var notes: [String]

    private var lines: [String] { notes.isEmpty ? ["Fehlerbehebungen und Verbesserungen"] : notes }

    var body: some View {
        SurfaceCard(padding: Theme.Spacing.l, cornerRadius: Theme.Radius.formGroup) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Kicker(text: "Was ist neu")
                    .accessibilityLabel("Was ist neu")
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(lines.enumerated()), id: \.offset) { index, note in
                    UpdNoteRow(text: note)
                        .reveal(order: 4 + index)
                }
            }
        }
        .reveal(order: 3)
        .accessibilityElement(children: .contain)
    }
}

/// A status symbol that plays `effect` once shortly after it appears (the seal of "Alles aktuell", the warning of a
/// required update) – attention, not decoration. Still under Reduce Motion and in screenshots.
private struct UpdAttentionSymbol: ViewModifier {
    enum Effect { case bounce, wiggle }

    let effect: Effect
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trigger = 0

    func body(content: Content) -> some View {
        Group {
            switch effect {
            case .bounce: content.symbolEffect(.bounce, value: trigger)
            case .wiggle: content.symbolEffect(.wiggle, value: trigger)
            }
        }
        .task {
            guard !reduceMotion, !MotionPolicy.isStatic else { return }
            try? await Task.sleep(for: .milliseconds(650))
            trigger += 1
        }
    }
}

/// One release note: a feature tile (Settings-style, so "new" never reads as "done") + the line.
private struct UpdNoteRow: View {
    var text: String

    /// Half the cap height of `.body`: centres the tile on the first line instead of on the symbol's own baseline,
    /// which differs per glyph (the magnifying glass sits lower than the euro sign) and would make the tiles step.
    @ScaledMetric(relativeTo: .body) private var capHalf: CGFloat = 6

    var body: some View {
        let feature = UpdFeature(note: text)
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            SetIconTile(symbol: feature.symbol, tint: feature.tint, size: 30)
                .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + capHalf }
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
        // "Besuch"/"versuchen" contain "such" but are no search feature.
        let text = note.lowercased(with: Locale(identifier: "de_AT"))
            .replacingOccurrences(of: "besuch", with: "")
            .replacingOccurrences(of: "versuch", with: "")
        let match = Self.match(text)
        symbol = match.symbol
        tint = match.tint
    }

    private static func match(_ s: String) -> (symbol: String, tint: Color) {
        func has(_ words: String...) -> Bool { words.contains { s.contains($0) } }
        if has("widget") { return ("rectangle.stack.fill", Theme.dusk) }
        if has("such", "search", "finde") { return ("magnifyingglass", Theme.glacier) }
        if has("preis", "tarif", "€", "kosten") { return ("eurosign", Theme.dawn) }
        if has("sync", "cloud", "konto", "anmeld") { return ("arrow.triangle.2.circlepath", Theme.glacier) }
        if has("co₂", "co2", "umwelt", "emission") { return ("leaf.fill", Theme.pine) }
        if has("statistik", "diagramm", "auswertung") { return ("chart.bar.fill", Theme.dusk) }
        if has("erinner", "mitteilung", "benachrichtig") { return ("bell.fill", Theme.alpenglow) }
        // Austrian "…karte" is usually a ticket card, not a map.
        if has("fahrkarte", "jahreskarte", "vorteilskarte", "vorteilscard") { return ("ticket.fill", Theme.dawn) }
        if has("karte", "route", "strecke", "haltestelle", "bahnhof") { return ("map.fill", Theme.pine) }
        if has("ticket") { return ("ticket.fill", Theme.dawn) }
        if has("fehler", "stabil", "absturz", "bug") { return ("wrench.and.screwdriver.fill", Theme.pine) }
        if has("design", "darstellung", "dunkel") { return ("paintbrush.fill", Theme.alpenglow) }
        if has("fahrt") { return ("tram.fill", Theme.glacier) }
        return ("sparkle", Theme.glacier)
    }
}

// MARK: - Secondary button

/// Calm tinted capsule for the secondary action ("AltStore-Quelle hinzufügen"): one step below the CTA, and – unlike
/// Liquid Glass over the opaque action bar – never a dark slab in dark mode.
private struct UpdSecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(MotionPolicy.isStatic ? nil : (configuration.isPressed ? Motion.press : Motion.release),
                       value: configuration.isPressed)
    }
}
