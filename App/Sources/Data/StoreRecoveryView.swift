import SwiftUI

/// Shown instead of the app while the data store is not open (see StoreLoader). Nothing can be entered here, so
/// nothing can end up anywhere but in the user's real store.
struct StoreRecoveryView: View {
    let store: StoreLoader
    @State private var confirmsStartFresh = false
    @State private var startFreshError: String?
    @State private var showsDetail = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                switch store.phase {
                case .opening, .ready:
                    loading
                case .waitingForUnlock:
                    locked
                case .failed(let failure):
                    failed(failure)
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, Theme.Spacing.xxl)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.center)
        .ambientBackground()
        .tint(Theme.accent)
        .task { store.retryIfNeeded() }
        .confirmationDialog("Mit leeren Daten neu beginnen?", isPresented: $confirmsStartFresh, titleVisibility: .visible) {
            Button("Neu beginnen", role: .destructive) { startFresh() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die bisherigen Daten werden nicht gelöscht, sondern als Kopie auf diesem iPhone aufbewahrt. "
                 + "Mit einem KlimaBilanz-Konto werden deine Tickets und Fahrten danach neu aus der Cloud geladen.")
        }
        .alert("Neu beginnen fehlgeschlagen", isPresented: Binding(get: { startFreshError != nil }, set: { if !$0 { startFreshError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(startFreshError ?? "")
        }
    }

    // MARK: Phases

    private var loading: some View {
        StatusCapsule(text: "Deine Daten werden geladen …")
            .frame(minHeight: 320)
    }

    private var locked: some View {
        VStack(spacing: Theme.Spacing.l) {
            header(symbol: "lock.fill", tint: Theme.accent, symbolColor: Theme.accent,
                   title: "iPhone entsperren",
                   message: "Nach einem Neustart bleiben deine Tickets und Fahrten verschlüsselt, bis du dein iPhone einmal entsperrst. Danach geht es automatisch weiter.")
            StatusCapsule(text: "Wartet auf das Entsperren …")
        }
    }

    private func failed(_ failure: StoreLoader.Failure) -> some View {
        VStack(spacing: Theme.Spacing.l) {
            // Warm, not alarm red: nothing is lost, the screen explains what to do.
            header(symbol: failure.kind == .diskFull ? "externaldrive.fill.badge.xmark" : "externaldrive.badge.exclamationmark",
                   tint: Theme.summit, symbolColor: Theme.summitText,
                   title: failure.kind == .diskFull ? "Kein Speicherplatz frei" : "Daten konnten nicht geöffnet werden",
                   message: message(for: failure))

            GlassCard(padding: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Label(failure.backup == nil ? "Keine Sicherungskopie angelegt" : "Sicherungskopie angelegt",
                          systemImage: failure.backup == nil ? "exclamationmark.circle" : "checkmark.shield.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(failure.backup == nil ? Theme.negativeText : Theme.positiveText)
                    Text(failure.backup == nil
                         ? "Die Datei konnte nicht kopiert werden. Wähle nicht „Neu beginnen“, bevor das Problem gelöst ist."
                         : "Eine Kopie deiner Daten liegt sicher auf diesem iPhone. KlimaBilanz speichert nichts, solange die Daten nicht geöffnet sind.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    DisclosureGroup("Technische Details", isExpanded: $showsDetail) {
                        Text(failure.detail)
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Theme.Spacing.xxs)
                    }
                    .font(.footnote)
                }
            }

            VStack(spacing: Theme.Spacing.s) {
                Button("Erneut versuchen") { store.retry() }
                    .buttonStyle(.primary)
                if !failure.backupFiles.isEmpty {
                    ShareLink(items: failure.backupFiles) {
                        Label("Sicherungskopie teilen", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
                Button("Mit leeren Daten neu beginnen …", role: .destructive) { confirmsStartFresh = true }
                    .font(.subheadline)
                    .padding(.top, Theme.Spacing.xs)
            }
        }
    }

    private func header(symbol: String, tint: Color, symbolColor: Color, title: String, message: String) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            StatusMedallion(symbol: symbol, tint: tint, symbolColor: symbolColor)
                .padding(.bottom, Theme.Spacing.xs)
            Kicker(text: "KlimaBilanz")
            Text(title)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func message(for failure: StoreLoader.Failure) -> String {
        switch failure.kind {
        case .diskFull:
            "Deine Tickets und Fahrten sind nicht verloren, aber ohne freien Speicher kann KlimaBilanz sie nicht öffnen. Gib in den iPhone-Einstellungen Speicher frei und versuch es dann erneut."
        case .unreadable:
            "Deine Tickets und Fahrten wurden nicht gelöscht. Wahrscheinlich hilft ein App-Update – oder ein neuer Versuch nach einem Neustart des iPhones."
        }
    }

    private func startFresh() {
        do {
            try store.startFresh()
        } catch {
            startFreshError = "Ein neuer, leerer Datenspeicher konnte nicht angelegt werden (\(StoreFiles.describe(error))). Deine bisherigen Daten bleiben erhalten."
        }
    }
}

/// The frosted disc with the state's symbol at the top of the store screens.
private struct StatusMedallion: View {
    var symbol: String
    /// The disc's wash.
    var tint: Color
    /// The symbol – one solid colour, so the drive's outline stays legible on the light disc.
    var symbolColor: Color
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 92

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.4, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(symbolColor)
            .frame(width: size, height: size)
            .frostedCard(cornerRadius: size / 2, tint: tint)
            .accessibilityHidden(true)
    }
}

/// A calm "something is happening" line: spinner + text in a glass capsule (store loading, waiting for the unlock,
/// the moment local data is replaced).
struct StatusCapsule: View {
    var text: String

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ProgressView()
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

/// Shown for the moment every local row is replaced (account data, "Alles löschen" – see RootView): a still sky and a
/// status line instead of screens that could still hold one of the rows.
struct DataReplacementView: View {
    var body: some View {
        StatusCapsule(text: "Daten werden aktualisiert …")
            .padding(.horizontal, Theme.Spacing.screen)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { AmbientBackground(animated: false) }
    }
}
