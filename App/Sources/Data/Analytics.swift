import Foundation
import SwiftData
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
    /// Snapshot of `ticket`'s period from `trips` (any superset of the period's live trips works the same).
    /// Only trips inside the period are mapped to records, and the result is memoised on its exact inputs
    /// (AnalyticsMemo): the views and the widget builder that ask for the same period after one change – and every
    /// re-render while scrolling or typing – share one computation.
    @MainActor
    static func make(ticket: TicketEntity, trips: [TripEntity], catalog: TariffCatalog, now: Date = Date()) -> AnalyticsSnapshot {
        // MARK: Diagnostics – count/duration per session (Einstellungen › Diagnose), signpost for the perf tests.
        Diagnostics.measure("Analytics.make") {
            let period = ticket.period
            var inPeriod: [TripEntity] = []
            var stamps: [AnalyticsMemo.TripStamp] = []
            var pastTrips = 0
            for trip in trips where trip.deletedAt == nil {
                let date = trip.date
                guard period.contains(date) else { continue }
                inPeriod.append(trip)
                stamps.append(AnalyticsMemo.TripStamp(id: trip.id, updatedAt: trip.updatedAt, date: date))
                if date <= now { pastTrips += 1 }
            }
            let key = AnalyticsMemo.Key(period: period, kilometergeld: catalog.kilometergeldEUR, emissions: catalog.emissions,
                                        day: AnalyticsMemo.calendar.startOfDay(for: now),
                                        isAfterEnd: now > period.end, isBeforeEnd: now < period.end,
                                        pastTrips: pastTrips, trips: stamps)
            let hash = key.hashValue
            if let cached = AnalyticsMemo.value(for: key, hash: hash) { return cached }
            let snapshot = make(period: period, records: inPeriod.map(\.record), catalog: catalog, now: now)
            AnalyticsMemo.insert(snapshot, for: key, hash: hash)
            return snapshot
        }
    }

    /// Drops all memoised snapshots (after a save).
    @MainActor
    static func invalidateCache() { AnalyticsMemo.removeAll() }

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

/// Memo behind `Analytics.make(ticket:trips:…)`. The key holds every input the pipeline reads:
/// • the period and the two catalog values it uses (Kilometergeld, emission factors),
/// • `now`, reduced to what the calculations compare: the Vienna day, whether it is past/before the period end, and how
///   many of the trips lie in the past (`date <= now`, which picks the same trips for the same count),
/// • per live in-period trip, in order: id, date and `updatedAt`. Every edit stamps `updatedAt` (`touch()` – the
///   invariant the cloud push relies on too); as a second line of defence every save clears the memo (Repository,
///   SyncService and, for anything else, `ModelContext.didSave`).
@MainActor
enum AnalyticsMemo {
    struct TripStamp: Hashable {
        var id: UUID
        var updatedAt: Date
        var date: Date
    }

    struct Key: Hashable {
        var period: TicketPeriod
        var kilometergeld: Double
        var emissions: EmissionFactors
        var day: Date
        var isAfterEnd: Bool
        var isBeforeEnd: Bool
        var pastTrips: Int
        var trips: [TripStamp]
    }

    /// The Vienna calendar of the memo keys (day boundaries).
    static let calendar = Calendar.vienna
    /// Distinct inputs alive at once: the active ticket, older ticket years (Ticket tab), the editor's before/after.
    static let capacity = 8

    private static var entries: [(hash: Int, key: Key, value: AnalyticsSnapshot)] = []
    private static var saveObserver: NSObjectProtocol?

    static func value(for key: Key, hash: Int) -> AnalyticsSnapshot? {
        observeSaves()
        guard let index = entries.firstIndex(where: { $0.hash == hash && $0.key == key }) else { return nil }
        let entry = entries.remove(at: index)
        entries.insert(entry, at: 0)
        return entry.value
    }

    static func insert(_ value: AnalyticsSnapshot, for key: Key, hash: Int) {
        entries.insert((hash, key, value), at: 0)
        if entries.count > capacity { entries.removeLast(entries.count - capacity) }
    }

    static func removeAll() { entries.removeAll() }

    private static func observeSaves() {
        guard saveObserver == nil else { return }
        saveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated { removeAll() }
            } else {
                Task { @MainActor in removeAll() }
            }
        }
    }
}
