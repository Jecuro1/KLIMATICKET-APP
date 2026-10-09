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
        VStack(spacing: Theme.Spacing.m) {
            ProgressView()
                .controlSize(.large)
            Text("Deine Daten werden geladen …")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(minHeight: 320)
        .accessibilityElement(children: .combine)
    }

    private var locked: some View {
        header(symbol: "lock.fill",
               title: "iPhone entsperren",
               message: "Nach einem Neustart bleiben deine Tickets und Fahrten verschlüsselt, bis du dein iPhone einmal entsperrst. Danach geht es automatisch weiter.")
    }

    private func failed(_ failure: StoreLoader.Failure) -> some View {
        VStack(spacing: Theme.Spacing.l) {
            header(symbol: failure.kind == .diskFull ? "externaldrive.fill.badge.xmark" : "externaldrive.badge.exclamationmark",
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

    private func header(symbol: String, title: String, message: String) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.accent.gradient)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
            Text(title)
                .font(Theme.Typography.title)
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
