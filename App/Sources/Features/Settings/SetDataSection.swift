import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import KlimaCore

/// Daten: CSV export, JSON backup & restore, demo data, delete everything.
struct SetDataSection: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }) private var trips: [TripEntity]
    @Query(filter: #Predicate<FavoriteRouteEntity> { $0.deletedAt == nil }) private var favorites: [FavoriteRouteEntity]
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]

    @State private var csvURL: URL?
    @State private var backupURL: URL?
    @State private var isImporting = false
    @State private var isConfirmingDemo = false
    @State private var isConfirmingDelete = false
    @State private var deleteTrigger = 0
    @State private var successTrigger = 0

    /// Changes whenever rows are added, removed or edited (e.g. by "Jetzt synchronisieren" or a restore),
    /// so the prepared export files never go stale.
    private var exportKey: String {
        let dates: [Date?] = [trips.map(\.updatedAt).max(), favorites.map(\.updatedAt).max(), tickets.map(\.updatedAt).max()]
        let latest: Double = dates.compactMap { $0 }.max()?.timeIntervalSinceReferenceDate ?? 0
        return "\(trips.count)|\(favorites.count)|\(tickets.count)|\(latest)"
    }

    var body: some View {
        Section {
            Group {
                csvRow
                    .onAppear { prepareExports() }
                    .onChange(of: exportKey) { _, _ in prepareExports() }
                backupRow
                    .id(SetScrollAnchor.data)
                importRow
                demoRow
                deleteRow
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Daten")
        } footer: {
            SetFooter(text: "\(SetFormat.count(trips.count, "Fahrt", "Fahrten")) · \(SetFormat.count(favorites.count, "Favorit", "Favoriten")) · \(SetFormat.count(tickets.count, "Ticket", "Tickets")). Das Backup enthält alles und lässt sich jederzeit wieder einspielen.")
        }
    }

    // MARK: Rows

    @ViewBuilder
    private var csvRow: some View {
        if let csvURL {
            ShareLink(item: csvURL) {
                SetRowLabel(title: "Fahrten als CSV exportieren", subtitle: "Für Excel und Numbers",
                            symbol: "tablecells.fill", tint: Theme.pine)
            }
        } else {
            SetRowLabel(title: "Fahrten als CSV exportieren", subtitle: "Wird vorbereitet …",
                        symbol: "tablecells.fill", tint: Theme.pine)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    @ViewBuilder
    private var backupRow: some View {
        if let backupURL {
            ShareLink(item: backupURL) {
                SetRowLabel(title: "Backup sichern", subtitle: "Alle Tickets, Fahrten und Favoriten als Datei",
                            symbol: "arrow.up.doc.fill", tint: Theme.glacier)
            }
        } else {
            SetRowLabel(title: "Backup sichern", subtitle: "Wird vorbereitet …",
                        symbol: "arrow.up.doc.fill", tint: Theme.glacier)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var importRow: some View {
        Button {
            isImporting = true
        } label: {
            SetRowLabel(title: "Backup wiederherstellen", subtitle: "Neuere Einträge gewinnen, nichts wird doppelt",
                        symbol: "arrow.down.doc.fill", tint: Theme.dusk)
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .settingsHaptic(.success, trigger: successTrigger, enabled: app.settings.hapticsEnabled)
    }

    private var demoRow: some View {
        Button {
            isConfirmingDemo = true
        } label: {
            SetRowLabel(title: "Demo-Daten laden", subtitle: "Ein Beispiel-Ticketjahr zum Ausprobieren",
                        symbol: "sparkles", tint: Theme.gold)
        }
        .confirmationDialog("Demo-Daten laden?", isPresented: $isConfirmingDemo, titleVisibility: .visible) {
            Button("Demo-Daten laden") { loadDemo() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Fügt ein Beispiel-Ticket mit rund 90 Fahrten hinzu – ideal zum Ausprobieren, am besten ohne eigene Daten.")
        }
    }

    private var deleteRow: some View {
        Button(role: .destructive) {
            isConfirmingDelete = true
        } label: {
            Label {
                Text("Alle Daten löschen")
            } icon: {
                SetIconTile(symbol: "trash.fill", tint: Theme.negative)
            }
        }
        .confirmationDialog("Alle Daten löschen?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Alles löschen", role: .destructive) { deleteAll() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle Tickets, Fahrten und Favoriten werden von diesem iPhone gelöscht. Das lässt sich nicht rückgängig machen – sichere vorher ein Backup.")
        }
        .settingsHaptic(.warning, trigger: deleteTrigger, enabled: app.settings.hapticsEnabled)
    }

    // MARK: Actions

    private func prepareExports() {
        let stamp = Backup.timestampedName
        if let data = try? Backup.csv(context: context) {
            csvURL = try? Backup.temporaryFile(named: "\(stamp)-Fahrten.csv", data: data)
        }
        if let data = try? Backup.export(context: context) {
            backupURL = try? Backup.temporaryFile(named: "\(stamp)-Backup.json", data: data)
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let imported = try Backup.importBackup(data, context: context)
                let repository = Repository(context: context, app: app)
                repository.commit()
                // Restored tickets need their renewal reminders (no-op when reminders are off).
                for ticket in repository.liveTickets() where !ticket.isExpired {
                    repository.scheduleReminders(for: ticket)
                }
                successTrigger += 1
                app.showToast("checkmark.circle.fill", "Backup wiederhergestellt", imported.summary)
            } catch {
                app.showToast("exclamationmark.triangle.fill", "Import fehlgeschlagen", "Die Datei ist kein gültiges KlimaBilanz-Backup.")
            }
        case .failure:
            app.showToast("exclamationmark.triangle.fill", "Import abgebrochen", "Die Datei konnte nicht geöffnet werden.")
        }
    }

    private func loadDemo() {
        DemoData.seed(into: context)
        Repository(context: context, app: app).commit()
        successTrigger += 1
        app.showToast("sparkles", "Demo-Daten geladen", "Ein Beispiel-Ticketjahr mit rund 90 Fahrten")
    }

    private func deleteAll() {
        deleteTrigger += 1
        // The hard delete leaves no ticket behind to cancel its reminders later – do it first.
        let ticketIDs = tickets.map(\.id)
        let notifications = app.notifications
        Task {
            for id in ticketIDs { await notifications.cancelRenewalReminders(ticketID: id) }
        }
        let repo = Repository(context: context, app: app)
        Task {
            let ok = await repo.deleteAllDataEverywhere()
            app.isShowingSettings = false
            if ok {
                app.showToast("trash.fill", "Alle Daten gelöscht", "Bereit für dein nächstes Ticket")
            } else {
                app.showToast("icloud.slash", "Auf diesem iPhone gelöscht", "Die Cloud wird beim nächsten Sync bereinigt")
            }
        }
    }
}
