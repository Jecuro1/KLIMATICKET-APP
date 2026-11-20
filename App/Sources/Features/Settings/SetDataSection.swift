import SwiftUI
import SwiftData
import KlimaCore

/// Daten: the way into Daten & Sicherung (exports, backups, restore, CSV import, Jahresbericht – docs/DATA_HUB.md), removing the
/// demo year, delete everything (after a safety backup).
struct SetDataSection: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }) private var trips: [TripEntity]
    @Query(filter: #Predicate<FavoriteRouteEntity> { $0.deletedAt == nil }) private var favorites: [FavoriteRouteEntity]
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]

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
                // MARK: data – CSV, Backup, Wiederherstellen, CSV-Import and the Jahresbericht live in Daten & Sicherung (docs/DATA_HUB.md)
                DataHubSettingsRow()
                    .id(SetScrollAnchor.data)
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
            SetFooter(text: "\(SetFormat.count(tripCount, "Fahrt", "Fahrten")) · \(SetFormat.count(favorites.count, "Favorit", "Favoriten")) · \(SetFormat.count(tickets.count, "Ticket", "Tickets")). \(AutoBackupService.shared.isEnabled ? "KlimaBilanz sichert einmal am Tag in Dateien, wenn sich etwas geändert hat. " : "")Export und Wiederherstellen unter Daten & Sicherung.")   // MARK: data, review-daten – only after a change
                .contentTransition(.numericText())
                .motionAnimation(Motion.number, value: [tripCount, favorites.count, tickets.count])
        }
    }

    /// Fahrten as the Übersicht and Daten & Sicherung count them: the legs of a journey are one Fahrt.   // MARK: data
    private var tripCount: Int { DataHubCounts.tripCount(journeys: trips.map(\.journeyID)) }

    // MARK: Rows

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
            Text("Alle Tickets, Fahrten und Favoriten werden von diesem iPhone gelöscht. Vorher legt KlimaBilanz eine Sicherung in Dateien an (Auf meinem iPhone › KlimaBilanz › Sicherungen).")   // MARK: data
        }
    }

    // MARK: Actions

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
        // MARK: data – a „vor dem Löschen“ backup in Dateien first (docs/DATA_HUB.md §4); when it cannot be written, nothing is deleted.
        Task {
            let safety = await AutoBackupService.shared.safetyBackup(.beforeDelete, container: context.container)
            guard safety.allowsDestructiveStep else {
                isDeleting = false
                app.showToast("exclamationmark.triangle.fill", "Nichts gelöscht", "Die Sicherung davor ging nicht – ist der Speicher voll?",
                              haptic: .warning)
                return
            }
            deleteAllAfterSafetyBackup()
        }
    }

    private func deleteAllAfterSafetyBackup() {   // MARK: data
        // The hard delete leaves no ticket behind to cancel its reminders later – do it first.
        let ticketIDs = tickets.map(\.id)
        let notifications = app.notifications
        Task {
            for id in ticketIDs { await notifications.cancelRenewalReminders(ticketID: id) }
            await LetterStore.forget(ticketIDs: ticketIDs)   // MARK: ticketletters – deadlines and their reminders
        }
        LetterStore.eraseAll()   // MARK: ticketletters – name and address in the Keychain, the switch
        DemoDataStore.forget()
        WhatIfStore.clear()   // MARK: whatif – saved scenarios hold the user's routes
        NoticeHistoryStore.clear()   // MARK: exitalarm – the Alarme history keeps the texts of delivered notices, an alarm's stop and time too
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
