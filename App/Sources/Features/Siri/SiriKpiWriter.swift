import Foundation
import SwiftData
import KlimaCore

// MARK: siri – writes the table Siri and the Kurzbefehle-App answer from (docs/SIRI_QUESTIONS.md §2). It runs with the widget refresh
// (`Repository.refreshWidgets()`): after every save, at launch, after a sync, when the day changed and when the ticket changed. The
// ticket year is the Analytics snapshot Statistik and the widgets use (memoised – the widget refresh just computed it); the days
// come from the same trips through KpiTableBuilder.

@MainActor
enum SiriKpiWriter {
    /// A table with the same figures is written again only after this long (its time stamp drives „Stand …“).
    static let rewriteAfter: TimeInterval = 60 * 60

    static func refresh(_ repo: Repository, now: Date = Date()) {
        // Screenshot and performance runs keep their in-memory demo data to themselves.
        guard !LaunchMode.isSandboxed else { return }
        Diagnostics.measure("SiriKpi.write") {
            let table = makeTable(repo, now: now)
            if let stored = SiriKpiFile.load(), stored.hasSameFigures(as: table),
               now.timeIntervalSince(stored.generatedAt) >= 0, now.timeIntervalSince(stored.generatedAt) < rewriteAfter {
                return
            }
            SiriKpiFile.save(table)
        }
    }

    /// The table for the data in `repo` at `now` – also what „Probier es aus“ in Einstellungen answers from.
    static func makeTable(_ repo: Repository, now: Date = Date()) -> KpiDailyTable {
        let app = repo.app
        let ticket = Analytics.activeTicket(in: repo.liveTickets(), selectedID: app.settings.selectedTicketID).map { ticket in
            let analytics = Analytics.make(ticket: ticket, trips: repo.periodTrips(ticket), catalog: app.catalog, now: now)
            return (period: analytics.ticket, summary: analytics.summary)
        }
        return KpiTableBuilder.make(ticket: ticket, trips: recentTrips(repo, now: now).map(\.record), now: now,
                                    emissions: app.catalog.emissions, format: AppearanceRuntime.format)
    }

    /// Live trips of the table's window (a day of margin for the time zone; the builder cuts exactly).
    private static func recentTrips(_ repo: Repository, now: Date) -> [TripEntity] {
        let since = now.addingTimeInterval(-Double(KpiDailyTable.dayWindow + 1) * 86_400)
        let predicate = #Predicate<TripEntity> { $0.deletedAt == nil && $0.date >= since }
        return (try? repo.context.fetch(FetchDescriptor<TripEntity>(predicate: predicate))) ?? []
    }
}
