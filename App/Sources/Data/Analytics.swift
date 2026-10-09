import Foundation
import KlimaCore

/// Everything derived from one ticket period + its trips. Pure value, cheap to recompute.
struct AnalyticsSnapshot {
    var ticket: TicketPeriod
    var trips: [TripRecord]
    var summary: SavingsSummary
    var series: [CumulativePoint]
    var forecast: [CumulativePoint]
    var months: [MonthBucket]
    var modes: [ModeBucket]
    var weekdays: [WeekdayBucket]
    var days: [DayActivity]
    var topRoutes: [RouteStat]
    var records: TravelRecords
    var achievements: [Achievement]

    var unlockedAchievements: [Achievement] { achievements.filter(\.isUnlocked) }
    /// Next achievement closest to completion.
    var nextAchievement: Achievement? {
        achievements.filter { !$0.isUnlocked }.max { $0.progress < $1.progress }
    }

    /// Trips needed (at the average trip value) to reach break-even.
    var tripsToBreakEven: Int? {
        guard !summary.isPaidOff else { return 0 }
        let avg = summary.averageValuePerTrip > 0 ? summary.averageValuePerTrip : 15
        return Int((summary.remainingToBreakEven / avg).rounded(.up))
    }
}

enum Analytics {
    static func make(ticket: TicketEntity, trips: [TripEntity], catalog: TariffCatalog, now: Date = Date()) -> AnalyticsSnapshot {
        // MARK: Diagnostics – count/duration per session (Einstellungen › Diagnose), signpost for the perf tests.
        Diagnostics.measure("Analytics.make") {
            make(period: ticket.period, records: trips.filter { $0.deletedAt == nil }.map(\.record), catalog: catalog, now: now)
        }
    }

    static func make(period: TicketPeriod, records allRecords: [TripRecord], catalog: TariffCatalog, now: Date = Date()) -> AnalyticsSnapshot {
        Diagnostics.measure("Analytics.compute") { compute(period: period, records: allRecords, catalog: catalog, now: now) }
    }

    private static func compute(period: TicketPeriod, records allRecords: [TripRecord], catalog: TariffCatalog, now: Date) -> AnalyticsSnapshot {
        let records = allRecords.filter { period.contains($0.date) }
        let summary = SavingsCalculator.summary(ticket: period, trips: records, now: now,
                                                kilometergeld: catalog.kilometergeldEUR, emissions: catalog.emissions)
        let stats = StatsAggregator.records(records, now: now)
        return AnalyticsSnapshot(
            ticket: period,
            trips: records,
            summary: summary,
            series: SavingsCalculator.cumulativeSeries(ticket: period, trips: records, now: now),
            forecast: SavingsCalculator.forecastSeries(ticket: period, trips: records, now: now),
            months: StatsAggregator.months(records, in: period),
            modes: StatsAggregator.modes(records),
            weekdays: StatsAggregator.weekdays(records),
            days: StatsAggregator.days(records),
            topRoutes: StatsAggregator.topRoutes(records, limit: 5),
            records: stats,
            achievements: AchievementEngine.evaluate(summary: summary, trips: records, records: stats)
        )
    }

    /// The ticket the UI should show: user's selection → the one valid today → the most recent.
    static func activeTicket(in tickets: [TicketEntity], selectedID: UUID?) -> TicketEntity? {
        let live = tickets.filter { $0.deletedAt == nil }
        if let selectedID, let t = live.first(where: { $0.id == selectedID }) { return t }
        if let current = live.first(where: { $0.isActive }) { return current }
        return live.max { $0.startDate < $1.startDate }
    }
}
