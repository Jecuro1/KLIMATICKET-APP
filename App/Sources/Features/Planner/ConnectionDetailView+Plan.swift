import SwiftUI
import SwiftData
import KlimaCore

// The „Planen“ card of the connection detail: reminder, favourite, via stop, earlier/later (split from ConnectionDetailView.swift).

extension ConnectionDetailView {
    // MARK: Plan (docs/PLANNER.md §Planen)

    /// Reminder, favourite, via stop and the connections before and after this one: what to do with the connection next.
    func planCard(_ row: ConnectionRow, model: PlannerModel) -> some View {
        let viasFull = model.vias.count >= JourneyQuery.maxViaStops
        return VStack(spacing: 0) {
            reminderRow(row)
            Divider().overlay(Theme.separator)
            planRow("star", "Als Favorit speichern", "Als Kombi-Vorlage mit allen Etappen") { saveFavorite(row, model: model) }
            Divider().overlay(Theme.separator)
            planRow("plus.circle", "Zwischenhalt hinzufügen", viasFull ? "Höchstens zwei Zwischenhalte" : "Die Suche führt über einen weiteren Halt") {
                addVia(model)
            }
            .disabled(viasFull)
            Divider().overlay(Theme.separator)
            planRow("clock.arrow.circlepath", "Früher suchen", "Verbindungen ab einer Stunde früher") { search(row, model: model, shift: -3600) }
            Divider().overlay(Theme.separator)
            planRow("forward.end", "Später suchen", "Verbindungen ab einer Minute nach dieser Abfahrt") { search(row, model: model, shift: 60) }
        }
        .frostedCard(cornerRadius: Theme.Radius.card)
    }

    private func reminderRow(_ row: ConnectionRow) -> some View {
        Menu {
            ForEach(PlannerReminder.leadMinutes, id: \.self) { lead in
                Button("\(lead) Min vorher") { setReminder(row, lead: lead) }
            }
            if reminderFire != nil {
                Button("Erinnerung entfernen", role: .destructive) { cancelReminder(row) }
            }
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: reminderFire == nil ? "bell" : "bell.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Erinnerung").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(reminderFire.map { "Gesetzt für \(Format.time($0)) Uhr" } ?? "Vor der Abfahrt benachrichtigen")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func planRow(_ symbol: String, _ title: String, _ subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Stores the connection as a Kombi-Vorlage: every ride leg is a leg of the favourite (the whole connection, not the covered part).
    private func saveFavorite(_ row: ConnectionRow, model: PlannerModel) {
        let plan = JourneyLogPlanner.plan(journey: row.journey, quote: price.quote ?? row.price.quote, coverage: nil,
                                          via: model.queriedVias, stations: app.stations)
        let mode = JourneyMetrics.dominantMode(row.journey)
        guard Repository(context: context, app: app).addFavorite(fromPlan: plan, mode: mode) != nil else {
            app.showToast("exclamationmark.triangle.fill", "Nichts zu speichern", "Diese Verbindung hat keine Fahrt mit Zug oder Bus")
            return
        }
        let legs = plan.legs.count
        app.showToast("star.fill", "Als Favorit gespeichert", legs > 1 ? "Kombi-Vorlage mit \(legs) Etappen" : "Lieblingsfahrt", haptic: .success)
    }

    /// Leaves the detail and opens the search for one more via stop (the search starts when the stop is chosen).
    private func addVia(_ model: PlannerModel) {
        model.path = []
        model.addVia()
    }

    /// Another search at the departure of this connection: an hour earlier or a minute later.
    private func search(_ row: ConnectionRow, model: PlannerModel, shift: TimeInterval) {
        guard let departure = row.journey.departure?.effective else { return }
        model.path = [.results]
        model.setWhen(departure.addingTimeInterval(shift), arrival: false)
    }

    private func setReminder(_ row: ConnectionRow, lead: Int) {
        Task {
            let outcome = await PlannerReminders.schedule(row.journey, title: PlannerExport.shareText(row.journey), leadMinutes: lead)
            switch outcome {
            case .scheduled(let fire):
                reminderFire = fire
                app.showToast("bell.fill", "Erinnerung gesetzt", "\(lead) Min vor der Abfahrt, \(Format.time(fire)) Uhr")
            case .tooLate:
                app.showToast("exclamationmark.triangle.fill", "Zu spät für eine Erinnerung", "Die Abfahrt liegt zu nah")
            case .denied:
                app.showToast("bell.slash.fill", "Keine Mitteilungen erlaubt", "Erlaube Mitteilungen für KlimaBilanz in den iPhone-Einstellungen")
            }
        }
    }

    private func cancelReminder(_ row: ConnectionRow) {
        PlannerReminders.cancel(journeyID: row.journey.id)
        reminderFire = nil
        app.showToast("bell.slash", "Erinnerung entfernt")
    }
}
