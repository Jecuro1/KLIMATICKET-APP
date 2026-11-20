import SwiftUI
import SwiftData
import KlimaCore

// MARK: data – „Das ändert sich“ (docs/DATA_HUB.md §5): before a restore merges anything, the sheet shows per table what is new,
// changed, removed and what stays, what the file is (date, app version, checksum) and whether its settings come along. Nothing is
// written until „Wiederherstellen“; then a safety backup comes first.

struct DataHubRestoreSheet: View {
    let preview: DataHubRestorePreview
    /// CI scene backupPreviewAX5Mid: opens scrolled to the change bars (`// MARK: review-daten`).
    var screenshotScrollsToChanges = false

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var includeSettings = false
    @State private var isRestoring = false
    @State private var failure: String?

    private var hasWork: Bool { preview.diff.changes > 0 || (includeSettings && !preview.settingsChanges.isEmpty) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                        header
                        changesCard
                            .id(ChangesAnchor.changes)
                        if !preview.settingsChanges.isEmpty { settingsCard }
                        fileCard
                        Text(BackupDiff.rule + " Vorher legt KlimaBilanz eine Sicherung in Dateien an.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Theme.Spacing.screen)
                    .padding(.top, Theme.Spacing.s)
                    .padding(.bottom, Theme.Spacing.xxl)
                    .revealScope()
                }
                .task {
                    guard screenshotScrollsToChanges else { return }
                    try? await Task.sleep(for: .milliseconds(450))
                    proxy.scrollTo(ChangesAnchor.changes, anchor: .top)
                }
            }
            .safeAreaInset(edge: .bottom) { actionBar }
            .background { SetBackdrop() }
            .navigationTitle("Wiederherstellen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .disabled(isRestoring)
                }
            }
            .interactiveDismissDisabled(isRestoring)
            .alert("Wiederherstellen fehlgeschlagen", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
        }
        .tint(Theme.accent)
    }

    private enum ChangesAnchor: Hashable { case changes }

    // MARK: Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Kicker(text: "Sicherung")
            // MARK: review-daten – at AX5 a file name in the title font filled the screen in three broken lines and pushed
            // „Das ändert sich“ under the button: the name stops at AX1, the sentences at AX3.
            Text(preview.title)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .accessibilityAddTraits(.isHeader)
            Text(DataHubText.keep(preview.diff.headline))
                .font(.headline)
                .foregroundStyle(preview.diff.changes > 0 ? Theme.textPrimary : Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            if let keeps = preview.diff.keepsLine {
                Text(DataHubText.keep(keeps))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            }
        }
        .reveal(order: 0)
    }

    private var changesCard: some View {
        GlassCard(padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                ForEach(preview.diff.tables.filter { $0.changes + $0.unchanged + $0.newerHere > 0 }) { table in
                    DataHubDiffBar(diff: table)
                }
                if preview.diff.tables.allSatisfy({ $0.changes + $0.unchanged + $0.newerHere == 0 }) {
                    Text("Die Datei enthält keine Einträge.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                DataHubDiffLegend()
            }
        }
        .reveal(order: 1)
    }

    private var settingsCard: some View {
        GlassCard(padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Toggle(isOn: $includeSettings) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auch Einstellungen übernehmen")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(DataHubRestore.settingsLine(preview.settingsChanges))
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Gilt ab dem nächsten Start der App. Anmeldung und Live-Daten-Zustimmung bleiben, wie sie auf diesem iPhone sind.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .reveal(order: 2)
    }

    private var fileCard: some View {
        let details = preview.details
        return GlassCard(padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Label(details.verdict.title, systemImage: details.verdict.isDamaged ? "xmark.seal.fill"
                      : (details.verdict == .missing ? "seal" : "checkmark.seal.fill"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(details.verdict == .missing ? Theme.summitText : Theme.positiveText)
                Text(details.verdict.line)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(fileLine(details))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if preview.isFromNewerApp {
                    Text("Diese Sicherung stammt aus einer neueren App-Version. Was diese Version nicht kennt, bleibt weg – aktualisiere KlimaBilanz, um alles zu übernehmen.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.summitText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .reveal(order: 3)
    }

    private func fileLine(_ details: DataHubBackupDetails) -> String {
        var parts = ["Format \(details.version)"]
        if let app = details.appVersion, !app.isEmpty { parts.append("KlimaBilanz \(app)") }
        if let date = details.exportedAt { parts.append("erstellt \(DataHubText.whenInline(date))") }
        parts.append(details.counts.line)
        return DataHubText.keep(parts.joined(separator: " · "))
    }

    private var actionBar: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Button {
                restore()
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    if isRestoring { ProgressView().tint(Theme.onAccent) }
                    Text(isRestoring ? "Wird wiederhergestellt …" : (hasWork ? "Wiederherstellen" : "Nichts zu übernehmen"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)   // MARK: review-daten – a button never hyphenates („Wiederherstel-len“ at AX5)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary)
            .disabled(!hasWork || isRestoring)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)   // MARK: review-daten – the bar keeps room for the preview
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.vertical, Theme.Spacing.s)
        .background(.bar)
        .motionAnimation(Motion.snappy, value: isRestoring)
    }

    private func restore() {
        guard !isRestoring else { return }
        isRestoring = true
        Task {
            let outcome = await DataHubRestore.run(preview, includeSettings: includeSettings, app: app, context: context)
            isRestoring = false
            switch outcome {
            case .restored(let summary):
                dismiss()
                app.showToast("checkmark.circle.fill", "Sicherung wiederhergestellt", summary)   // MARK: review-daten – the hub's word
            case .failed(let message):
                failure = message
            }
        }
    }
}
