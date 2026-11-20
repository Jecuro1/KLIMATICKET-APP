import SwiftUI
import SwiftData
import KlimaCore

// MARK: data – the two ways into Daten & Sicherung from outside: the row in Einstellungen, and „Aus Sicherung wiederherstellen“ on
// the screen shown when the data store cannot be opened (StoreRecoveryView, `// MARK: data`), which starts with an empty store
// (the unreadable one is kept as a copy, as with „Neu beginnen“) and restores the newest readable backup into it.

/// Einstellungen › Daten: the one row that leads to the hub.
struct DataHubSettingsRow: View {
    private var service: AutoBackupService { .shared }

    var body: some View {
        NavigationLink {
            DataHubView()
        } label: {
            SetRowLabel(title: "Daten & Sicherung", subtitle: subtitle, symbol: "externaldrive.fill.badge.checkmark", tint: Theme.glacier)
        }
        .task { await service.refresh() }
    }

    private var subtitle: String {
        let last = service.isEnabled ? DataHubText.lastBackup(service.files.first(where: { !$0.isForeign })) : "Tägliche Sicherung ist aus"
        return last + " · Exportieren, Wiederherstellen"
    }
}

/// The newest backup in Documents/Sicherungen that passes its check – offered when the store does not open.
struct DataHubRecoveryButton: View {
    let store: StoreLoader

    @State private var newest: (file: DataHubBackupFile, details: DataHubBackupDetails)?
    @State private var confirms = false
    @State private var failure: String?

    var body: some View {
        VStack(spacing: Theme.Spacing.xxs) {
            if let newest {
                Button { confirms = true } label: {
                    Label("Aus Sicherung wiederherstellen", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                Text(DataHubText.keep("Sicherung von \(DataHubText.whenInline(newest.file.date)) · \(newest.details.counts.line)"))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .motionTransition(.opacity)
            }
        }
        .motionAnimation(Motion.smooth, value: newest?.file.name)
        .task { newest = await Self.findNewest() }
        .confirmationDialog("Mit der Sicherung neu beginnen?", isPresented: $confirms, titleVisibility: .visible) {
            Button("Wiederherstellen") { restore() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die bisherigen Daten werden nicht gelöscht, sondern als Kopie auf diesem iPhone aufbewahrt. Dann kommt alles aus der Sicherung von \(newest.map { DataHubText.whenInline($0.file.date) } ?? "") zurück.")
        }
        .alert("Wiederherstellen fehlgeschlagen", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    /// Newest first; the first file whose check passes. In the CI scene a fixed example.
    static func findNewest() async -> (file: DataHubBackupFile, details: DataHubBackupDetails)? {
        if LaunchMode.screenshotScreen == "storeRecoveryBackup" {
            let date = Date().addingTimeInterval(-5 * 3600)
            return (DataHubBackupFile(url: FileManager.default.temporaryDirectory.appending(path: "demo.json"), name: "demo.json", date: date,
                                      kind: .daily, size: 184_000, isForeign: false),
                    DataHubBackupDetails(counts: DataHubCounts(trips: 154, tickets: 1, favorites: 6, benefits: 3), version: 3,
                                         exportedAt: date, appVersion: "1.3.0", settingsCount: 4, verdict: .intact("00000000"), problem: nil))
        }
        guard !LaunchMode.isSandboxed else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> (file: DataHubBackupFile, details: DataHubBackupDetails)? in
            for file in DataHubFolder.list() {
                if let details = DataHubFolder.details(of: file.url), details.canRestore, !details.counts.isEmpty { return (file, details) }
            }
            return nil
        }.value
    }

    private func restore() {
        guard let newest else { return }
        guard !LaunchMode.isSandboxed else { return }
        guard let data = try? Data(contentsOf: newest.file.url) else {
            failure = "Die Sicherung konnte nicht gelesen werden. Deine bisherigen Daten sind unverändert."
            return
        }
        guard BackupInspection.inspect(data).canRestore else {
            failure = BackupInspection.inspect(data).problem?.message ?? "Die Sicherung ist beschädigt."
            return
        }
        do {
            try store.startFresh()
        } catch {
            failure = "Ein neuer, leerer Datenspeicher konnte nicht angelegt werden (\(StoreFiles.describe(error))). Deine bisherigen Daten bleiben erhalten."
            return
        }
        guard let container = store.container else { return }
        do {
            _ = try Backup.restoreChecked(data, context: container.mainContext)
            if let app = AppDelegate.appState {
                let repository = Repository(context: container.mainContext, app: app)
                repository.commit()
                for ticket in repository.liveTickets() where !ticket.isExpired { repository.scheduleReminders(for: ticket) }
                Task { await DataHubRestore.refreshRouteReminders(before: [:], context: container.mainContext) }   // MARK: review-daten
                // MARK: review-daten – what the store holds now, counted like the line above the button (not every row of the file)
                app.showToast("checkmark.circle.fill", "Aus Sicherung wiederhergestellt", Backup.counts(context: container.mainContext).line)
            }
        } catch {
            // The empty store is open; the unreadable one is kept as a copy. The person can try again from Daten & Sicherung.
            AppDelegate.appState?.showToast("exclamationmark.triangle.fill", "Sicherung nicht eingespielt",
                                           "Versuch es unter Einstellungen › Daten & Sicherung erneut", haptic: .warning)
        }
    }
}
