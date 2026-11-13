import Foundation
import SwiftData
import KlimaCore

// MARK: automation – the read-only snapshot the rules see (docs/AUTOMATION.md §4). This is the only file of the automation
// that touches the store, and it only fetches: no insert, no delete, no save. Rules never write trip data.

@MainActor
enum AutoSnapshot {
    /// More new trips than this in one save are an import or demo data, not „eine Fahrt erfasst“: no rule fires for them.
    static let bulkLimit = 3
    /// A trip counts as newly logged for this long after it was saved (a trip synced from another device later does not).
    static let freshWindow: TimeInterval = 10 * 60

    /// The facts for one check. `includeNewTrips`: after a save (the trips saved since the ledger's watermark).
    static func state(context: ModelContext, catalog: TariffCatalog, selectedTicketID: UUID?, ledger: AutoLedger,
                      quietWeekend: Bool, follow: AutoFollowFact?, now: Date, includeNewTrips: Bool = false,
                      calendar: Calendar = .vienna) -> AutoState {
        AutoState(ticket: ticket(context: context, catalog: catalog, selectedTicketID: selectedTicketID, now: now),
                  tripDays: tripDays(context: context, now: now, calendar: calendar),
                  newTrips: includeNewTrips ? newTrips(context: context, since: ledger.tripWatermark, now: now) : [],
                  lastTrip: lastTrip(context: context),
                  follow: follow, ledger: ledger, quietWeekend: quietWeekend)
    }

    /// The ticket the app shows (the selected one, else the one valid today, else the newest) with its amortisation.
    static func ticket(context: ModelContext, catalog: TariffCatalog, selectedTicketID: UUID?, now: Date) -> AutoTicketFact? {
        let tickets = (try? context.fetch(FetchDescriptor<TicketEntity>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        guard let ticket = Analytics.activeTicket(in: tickets, selectedID: selectedTicketID) else { return nil }
        let start = ticket.startDate, end = ticket.endDate
        let trips = (try? context.fetch(FetchDescriptor<TripEntity>(
            predicate: #Predicate { $0.deletedAt == nil && $0.date >= start && $0.date <= end }))) ?? []
        let summary = Analytics.make(ticket: ticket, trips: trips, catalog: catalog, now: now).summary
        return AutoTicketFact(id: ticket.id.uuidString, name: ticket.name, start: ticket.period.start, end: ticket.period.end,
                              amortizedFraction: summary.amortizedFraction, price: summary.ticketPrice, value: summary.totalValue)
    }

    /// The days from today to the end of the planning horizon that have a trip.
    static func tripDays(context: ModelContext, now: Date, calendar: Calendar) -> Set<String> {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: AutoRuleScheduler.horizonDays + 1, to: start) ?? start
        let trips = (try? context.fetch(FetchDescriptor<TripEntity>(
            predicate: #Predicate { $0.deletedAt == nil && $0.date >= start && $0.date < end }))) ?? []
        return Set(trips.map { AutoClock.dayKey($0.date, calendar: calendar) })
    }

    /// Trips saved after `since` and within the fresh window, one fact per journey. Empty for an import (more than `bulkLimit`).
    static func newTrips(context: ModelContext, since: Date?, now: Date) -> [AutoTripFact] {
        let floor = max(since ?? now, now.addingTimeInterval(-freshWindow))
        let rows = (try? context.fetch(FetchDescriptor<TripEntity>(
            predicate: #Predicate { $0.deletedAt == nil && $0.createdAt > floor }))) ?? []
        let facts = facts(from: rows)
        return facts.count > bulkLimit ? [] : facts
    }

    /// The newest saved trip (with its journey), for the Testlauf of „Fahrt erfasst“.
    static func lastTrip(context: ModelContext) -> AutoTripFact? {
        var descriptor = FetchDescriptor<TripEntity>(predicate: #Predicate { $0.deletedAt == nil },
                                                     sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        guard let newest = (try? context.fetch(descriptor))?.first else { return nil }
        guard newest.journeyID != nil else { return facts(from: [newest]).first }
        let journey: UUID? = newest.journeyID
        let legs = (try? context.fetch(FetchDescriptor<TripEntity>(
            predicate: #Predicate { $0.deletedAt == nil && $0.journeyID == journey }))) ?? [newest]
        return facts(from: legs).first
    }

    /// One fact per journey (first start, last destination, summed value, every mode) and per single trip.
    static func facts(from rows: [TripEntity]) -> [AutoTripFact] {
        let groups = Dictionary(grouping: rows) { $0.journeyID ?? $0.id }
        return groups.values.compactMap { legs -> AutoTripFact? in
            let ordered = legs.sorted { $0.legIndex < $1.legIndex }
            guard let first = ordered.first, let last = ordered.last else { return nil }
            return AutoTripFact(id: first.journeyID ?? first.id, date: first.date,
                                createdAt: ordered.map(\.createdAt).max() ?? first.createdAt,
                                fromName: first.fromName, toName: last.toName,
                                fromStationID: first.fromStationID, toStationID: last.toStationID,
                                modes: Set(ordered.map(\.mode)), value: ordered.reduce(0) { $0 + $1.record.totalValue })
        }
        .sorted { $0.createdAt < $1.createdAt }
    }
}
