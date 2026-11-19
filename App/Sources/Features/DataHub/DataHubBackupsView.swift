import SwiftUI
import SwiftData
import KlimaCore

// MARK: data – Daten & Sicherung › Sicherungen (docs/DATA_HUB.md §4): the honest banner, every backup in Documents/Sicherungen with
// date, size and counts and Prüfen · Teilen · Wiederherstellen, and the database copies the app keeps itself (read-only, Teilen).

struct DataHubBackupsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @State private var details: [String: DataHubBackupDetails] = [:]
    @State private var checked: Set<String> = []
    @State private var storeCopies: [DataHubStoreCopy] = []
    @State private var preview: DataHubRestorePreview?
    @State private var preparing: String?

    /// CI scenes: rows already checked, the demo's database copy.
    var screenshotChecked: Set<String> = []
    var demoStoreCopies: [DataHubStoreCopy]? = nil

    private var service: AutoBackupService { .shared }

    var body: some View {
        List {
            Section {
                DataHubBanner()
                    .listRowBackground(Theme.summitText.opacity(0.08))
            }
            Section {
                if service.files.isEmpty {
                    emptyRow
                        .listRowBackground(Theme.surface)
                } else {
                    ForEach(service.files) { file in
                        DataHubBackupRow(file: file, details: details[file.name], isChecked: checked.contains(file.name),
                                         onCheck: { check(file) }, onRestore: { restore(file) })
                            .overlay(alignment: .topTrailing) {
                                if preparing == file.name { ProgressView().motionTransition(.pop) }
                            }
                            .listRowBackground(Theme.surface)
                            .motionTransition(.rise)
                    }
                }
            } header: {
                SetSectionHeader(title: service.files.isEmpty ? "Auf diesem iPhone" : "Auf diesem iPhone · \(service.files.count)")
            } footer: {
                SetFooter(text: DataHubText.retention + " " + BackupChecksum.honestyNote)
            }
            if !storeCopies.isEmpty {
                Section {
                    ForEach(storeCopies) { copy in
                        storeCopyRow(copy)
                            .listRowBackground(Theme.surface)
                    }
                } header: {
                    SetSectionHeader(title: "Datenbank-Kopien")
                } footer: {
                    SetFooter(text: "Kopien der Datenbank, die KlimaBilanz vor einem Update oder bei einem Fehler selbst anlegt. Nur zum Teilen, etwa für den Support – wiederherstellen lassen sie sich hier nicht.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Theme.Spacing.l)
        .listSectionMargins(.horizontal, Theme.Spacing.cardGutter)
        .scrollContentBackground(.hidden)
        .background { SetBackdrop() }
        .tint(Theme.accent)
        .navigationTitle("Sicherungen")
        .navigationBarTitleDisplayMode(.inline)
        .motionAnimation(Motion.smooth, value: service.files.map(\.name))
        .sheet(item: $preview) { DataHubRestoreSheet(preview: $0) }
        .task {
            await service.refresh()
            checked = screenshotChecked
            await loadDetails()
            if let demoStoreCopies { storeCopies = demoStoreCopies }
            else { storeCopies = await Task.detached(priority: .utility) { DataHubFolder.storeCopies() }.value }
        }
    }

    private var emptyRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Label("Noch keine Sicherung", systemImage: "tray")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Die erste entsteht, sobald du die App verlässt – oder jetzt mit „Jetzt sichern“.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Theme.Spacing.xxs)
        .accessibilityElement(children: .combine)
    }

    private func storeCopyRow(_ copy: DataHubStoreCopy) -> some View {
        ShareLink(items: copy.files) {
            HStack(spacing: Theme.Spacing.s) {
                SetRowLabel(title: copy.title,
                            subtitle: [copy.date.map(DataHubText.when), DataHubFormat.bytes(copy.size)].compactMap { $0 }.joined(separator: " · "),
                            symbol: "cylinder.split.1x2.fill", tint: Theme.textTertiary)
                Spacer(minLength: Theme.Spacing.xs)
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(Theme.accentText)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityHint("Teilen")
    }

    // MARK: Actions

    private func loadDetails() async {
        let files = service.files
        let loaded = await Task.detached(priority: .utility) { () -> [String: DataHubBackupDetails] in
            var result: [String: DataHubBackupDetails] = [:]
            for file in files { result[file.name] = DataHubFolder.details(of: file.url) }
            return result
        }.value
        withMotion(Motion.smooth) { details = loaded }
    }

    /// „Prüfen“: reads the file again and recomputes the checksum.
    private func check(_ file: DataHubBackupFile) {
        Task {
            let fresh = await Task.detached(priority: .userInitiated) { DataHubFolder.details(of: file.url) }.value
            withMotion(Motion.snappy) {
                if let fresh { details[file.name] = fresh }
                checked.insert(file.name)
            }
            guard let fresh else {
                app.showToast("exclamationmark.triangle.fill", "Datei nicht lesbar", file.name, haptic: .warning)
                return
            }
            app.showToast(fresh.verdict.isDamaged ? "xmark.seal.fill" : "checkmark.seal.fill", fresh.verdict.title,
                          fresh.verdict.isDamaged ? "Nicht wiederherstellbar" : fresh.counts.line,
                          haptic: fresh.verdict.isDamaged ? .warning : .success)
        }
    }

    private func restore(_ file: DataHubBackupFile) {
        preparing = file.name
        Task {
            let result = await DataHubRestore.preview(url: file.url, title: DataHubText.when(file.date), container: context.container)
            withMotion(Motion.snappy) { preparing = nil }
            switch result {
            case .success(let made): preview = made
            case .failure(let failure):
                app.showToast("exclamationmark.triangle.fill", "Nicht wiederherstellbar", failure.message, haptic: .warning)
            }
        }
    }
}
