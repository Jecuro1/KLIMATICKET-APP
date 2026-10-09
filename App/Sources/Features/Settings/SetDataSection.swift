import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import KlimaCore

/// Daten: CSV export, JSON backup & restore, removing the demo year, delete everything.
/// The exports are lazy share items (`TripsCSVExport`, `BackupShareItem`): nothing is prepared while Settings opens or scrolls.
struct SetDataSection: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }) private var trips: [TripEntity]
    @Query(filter: #Predicate<FavoriteRouteEntity> { $0.deletedAt == nil }) private var favorites: [FavoriteRouteEntity]
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]

    @State private var isImporting = false
    @State private var isRestoring = false
    @State private var isConfirmingDemoRemoval = false
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false

    /// Rows of the sample year ("Demo ansehen") are still there. Tickets and favourites are few and decide almost
    /// always; the trips are only scanned once both are gone.
    private var hasDemoData: Bool {
        let ids = DemoDataStore.ids
        guard !ids.isEmpty else { return false }
        return tickets.contains { ids.contains($0.id) } || favorites.contains { ids.contains($0.id) }
            || trips.contains { ids.contains($0.id) }
    }

    var body: some View {
        Section {
            Group {
                csvRow
                // MARK: reports
                RepImportSettingsRow()
                RepReportSettingsRow()
                backupRow
                    .id(SetScrollAnchor.data)
                importRow
                if hasDemoData {
                    demoRow
                }
                deleteRow
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Daten")
        } footer: {
            // The counts roll when a restore or a removal changes them.
            SetFooter(text: "\(SetFormat.count(trips.count, "Fahrt", "Fahrten")) · \(SetFormat.count(favorites.count, "Favorit", "Favoriten")) · \(SetFormat.count(tickets.count, "Ticket", "Tickets")). Das Backup enthält alles und lässt sich jederzeit wieder einspielen.")
                .contentTransition(.numericText())
                .motionAnimation(Motion.number, value: [trips.count, favorites.count, tickets.count])
        }
    }

    // MARK: Rows

    private var csvRow: some View {
        ShareLink(item: TripsCSVExport(container: context.container),
                  subject: Text("KlimaBilanz – Fahrten"),
                  preview: SharePreview("KlimaBilanz – Fahrten (CSV)")) {
            SetRowLabel(title: "Fahrten als CSV exportieren",
                        subtitle: trips.isEmpty ? "Noch keine Fahrten erfasst" : "Für Excel und Numbers",
                        symbol: "tablecells.fill", tint: Theme.pine)
        }
        .disabled(trips.isEmpty)
    }

    private var backupRow: some View {
        ShareLink(item: BackupShareItem(container: context.container),
                  subject: Text("KlimaBilanz – Backup"),
                  preview: SharePreview("KlimaBilanz – Backup")) {
            SetRowLabel(title: "Backup sichern", subtitle: "Alle Tickets, Fahrten und Favoriten als Datei",
                        symbol: "arrow.up.doc.fill", tint: Theme.glacier)
        }
    }

    private var importRow: some View {
        Button {
            isImporting = true
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                SetRowLabel(title: "Backup wiederherstellen",
                            subtitle: isRestoring ? "Wird wiederhergestellt …" : "Neuere Einträge gewinnen, nichts wird doppelt",
                            symbol: "arrow.down.doc.fill", tint: Theme.dusk, isBusy: isRestoring, busyStyle: .pulse)
                Spacer(minLength: Theme.Spacing.xs)
                SetBusyIndicator(isBusy: isRestoring)
            }
            .motionAnimation(Motion.snappy, value: isRestoring)
        }
        .disabled(isRestoring)
        // The result toast carries the one haptic of the restore (success or error).
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
    }

    /// Only while rows of the sample year exist – "Demo ansehen" lives in the onboarding, where the store is still empty.
    /// Loading it here would mix fictitious trips into the user's real ticket year.
    private var demoRow: some View {
        Button {
            isConfirmingDemoRemoval = true
        } label: {
            SetRowLabel(title: "Demo-Daten entfernen", subtitle: "Beispiel-Ticket mit seinen Fahrten und Favoriten",
                        symbol: "sparkles", tint: Theme.gold)
        }
        .confirmationDialog("Demo-Daten entfernen?", isPresented: $isConfirmingDemoRemoval, titleVisibility: .visible) {
            Button("Demo-Daten entfernen", role: .destructive) { removeDemo() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Das Beispiel-Ticket mit seinen Fahrten, Favoriten und Vorteilen wird gelöscht. Was du selbst erfasst hast, bleibt erhalten.")
        }
    }

    private var deleteRow: some View {
        Button(role: .destructive) {
            isConfirmingDelete = true
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                Label {
                    // Text-safe red like "Abmelden" (the system red is below 4.5 : 1 on the light row surface).
                    Text("Alle Daten löschen")
                        .foregroundStyle(Theme.negativeText)
                } icon: {
                    SetIconTile(symbol: "trash.fill", tint: Theme.negative)
                        .setSymbolOnEnable(isDeleting, .wiggle)
                }
                Spacer(minLength: Theme.Spacing.xs)
                if isDeleting {
                    ProgressView()
                        .motionTransition(.pop)
                }
            }
            .motionAnimation(Motion.snappy, value: isDeleting)
        }
        .disabled(isDeleting)
        .confirmationDialog("Alle Daten löschen?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Alles löschen", role: .destructive) { deleteAll() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle Tickets, Fahrten und Favoriten werden von diesem iPhone gelöscht. Das lässt sich nicht rückgängig machen – sichere vorher ein Backup.")
        }
    }

    // MARK: Actions

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            isRestoring = true
            Task {
                // The picked file may live in iCloud Drive or another provider: read it off the main thread.
                let data = await Task.detached(priority: .userInitiated) { () -> Data? in
                    let isScoped = url.startAccessingSecurityScopedResource()
                    defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
                    return try? Data(contentsOf: url)
                }.value
                restore(data)
                isRestoring = false
            }
        case .failure:
            app.showToast("exclamationmark.triangle.fill", "Import abgebrochen", "Die Datei konnte nicht geöffnet werden.")
        }
    }

    private func restore(_ data: Data?) {
        guard let data else {
            app.showToast("exclamationmark.triangle.fill", "Import abgebrochen", "Die Datei konnte nicht geöffnet werden.")
            return
        }
        do {
            let imported = try Backup.importBackup(data, context: context)
            let repository = Repository(context: context, app: app)
            repository.commit()
            // Restored tickets need their renewal reminders (no-op when reminders are off).
            for ticket in repository.liveTickets() where !ticket.isExpired {
                repository.scheduleReminders(for: ticket)
            }
            app.showToast("checkmark.circle.fill", "Backup wiederhergestellt", imported.summary)
        } catch {
            app.showToast("exclamationmark.triangle.fill", "Import fehlgeschlagen", "Die Datei ist kein gültiges KlimaBilanz-Backup.")
        }
    }

    private func removeDemo() {
        let repository = Repository(context: context, app: app)
        let removed = withMotion(Motion.smooth) { repository.deleteDemoData(ids: DemoDataStore.ids) }
        withMotion(Motion.smooth) { DemoDataStore.forget() }
        guard removed > 0 else { return }
        // The toast plays the removal's one haptic (warning – something was deleted).
        if repository.liveTickets().isEmpty {
            // No own ticket left: the app starts over with the setup (RootView shows the onboarding).
            app.isShowingSettings = false
            app.showToast("sparkles", "Demo-Daten entfernt", "Leg jetzt dein eigenes Ticket an", haptic: .warning)
        } else {
            app.showToast("sparkles", "Demo-Daten entfernt", "Deine eigenen Einträge bleiben erhalten", haptic: .warning)
        }
    }

    private func deleteAll() {
        guard !isDeleting else { return }
        isDeleting = true
        // The hard delete leaves no ticket behind to cancel its reminders later – do it first.
        let ticketIDs = tickets.map(\.id)
        let notifications = app.notifications
        Task {
            for id in ticketIDs { await notifications.cancelRenewalReminders(ticketID: id) }
        }
        DemoDataStore.forget()
        let repo = Repository(context: context, app: app)
        Task {
            let ok = await repo.deleteAllDataEverywhere()
            isDeleting = false
            app.isShowingSettings = false
            if ok {
                app.showToast("trash.fill", "Alle Daten gelöscht", "Bereit für dein nächstes Ticket")
            } else {
                app.showToast("icloud.slash", "Auf diesem iPhone gelöscht", "Die Cloud wird beim nächsten Sync bereinigt",
                              haptic: .warning)
            }
        }
    }
}
