import SwiftUI
import KlimaCore

// MARK: settings – Manuell aktualisieren: the cards below the hero (split from ManualUpdateView.swift).

// MARK: - Cards

/// The honest part: iOS itself installs no .ipa.
struct MUHonestNote: View {
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
struct MUOneTapCard: View {
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
struct MUGuideCard: View {
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

struct MUStepRow: View {
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
struct MUStepArt: View {
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

struct MUNoReleaseCard: View {
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

struct MUNoSideloadCard: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        MUInfoCard(symbol: "questionmark.app.fill", tint: Theme.dawn, kicker: "Keine Sideload-App?",
                   text: "Ohne SideStore oder AltStore kann iOS die Datei nicht öffnen. SideStore ist kostenlos und braucht nur deine Apple-ID – dafür musst du die App alle 7 Tage in SideStore auffrischen.",
                   linkTitle: "Anleitung öffnen") {
            openURL(ManualUpdateCopy.guideURL)
        }
    }
}

struct MUDeveloperCard: View {
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

struct MUInfoCard: View {
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
