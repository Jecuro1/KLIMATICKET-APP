import Foundation
import KlimaCore

/// Ticketjahr or one month of it – the period picker of the Zeitbilanz (like the Statistik's ticket year).
enum TimeBalancePeriodKind: String, CaseIterable, Hashable {
    case ticketYear
    case month

    var title: String {
        switch self {
        case .ticketYear: "Ticketjahr"
        case .month: "Monat"
        }
    }
}

/// The months a ticket year offers, and the range of each (both ends inclusive, like `TicketPeriod.contains`).
enum TimeBalancePeriods {
    static let calendar = Calendar.vienna

    /// First day of every month that overlaps the ticket and has begun by `now` (the first month when it has not).
    static func months(of ticket: TicketPeriod, now: Date) -> [Date] {
        guard let first = calendar.dateInterval(of: .month, for: ticket.start)?.start else { return [] }
        let last = min(ticket.end, max(now, ticket.start))
        var result: [Date] = []
        var cursor = first
        while cursor <= last, result.count < 24 {
            result.append(cursor)
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// The month that opens: today's, or the last one of an ended ticket year.
    static func defaultMonth(of ticket: TicketPeriod, now: Date) -> Date? {
        let all = months(of: ticket, now: now)
        let current = calendar.dateInterval(of: .month, for: now)?.start
        return all.first { $0 == current } ?? all.last
    }

    static func range(of ticket: TicketPeriod, kind: TimeBalancePeriodKind, month: Date?) -> ClosedRange<Date> {
        guard kind == .month, let month, let interval = calendar.dateInterval(of: .month, for: month) else {
            return ticket.start...max(ticket.start, ticket.end)
        }
        let start = max(interval.start, ticket.start)
        let end = min(interval.end.addingTimeInterval(-1), ticket.end)
        return start...max(start, end)
    }

    /// "November 2026"
    static func monthTitle(_ month: Date) -> String { Format.monthYear(month) }
}

/// The balance of one period, memoised on its inputs: the screen re-renders while a number rolls or the picker slides,
/// the Statistik card while the list scrolls – the trips are mapped and resolved once per change of the stored data.
@MainActor
enum TimeBalanceMemo {
    struct Key: Hashable {
        var tripsStamp: Int
        var range: ClosedRange<Date>
        /// `now` in quarter hours: the totals only count trips up to now.
        var quarter: Int
        var profile: CarProfile
    }

    private static var inputsStamp: Int?
    private static var cachedInputs: [TimeTripInput] = []
    private static var entries: [(key: Key, value: TimeBalance)] = []
    private static let capacity = 6

    /// A cheap fingerprint of the trips: count, every id and change stamp (every edit `touch()`es `updatedAt`).
    static func stamp(_ trips: [TripEntity]) -> Int {
        var hasher = Hasher()
        hasher.combine(trips.count)
        for trip in trips {
            hasher.combine(trip.id)
            hasher.combine(trip.updatedAt)
        }
        return hasher.finalize()
    }

    static func inputs(_ trips: [TripEntity], stamp: Int) -> [TimeTripInput] {
        if inputsStamp == stamp { return cachedInputs }
        let mapped = trips.filter { $0.deletedAt == nil }.map(\.timeInput)
        inputsStamp = stamp
        cachedInputs = mapped
        return mapped
    }

    static func balance(trips: [TripEntity], range: ClosedRange<Date>, now: Date, profile: CarProfile) -> TimeBalance {
        let stamp = stamp(trips)
        let key = Key(tripsStamp: stamp, range: range, quarter: Int(now.timeIntervalSinceReferenceDate / 900), profile: profile)
        if let hit = entries.first(where: { $0.key == key }) { return hit.value }
        let value = TimeBalanceCalculator.compute(trips: inputs(trips, stamp: stamp), range: range, now: now, carProfile: profile)
        entries.insert((key, value), at: 0)
        if entries.count > capacity { entries.removeLast() }
        return value
    }

    /// For a fixed list of inputs (screenshot fixtures): not memoised.
    static func balance(inputs: [TimeTripInput], range: ClosedRange<Date>, now: Date, profile: CarProfile) -> TimeBalance {
        TimeBalanceCalculator.compute(trips: inputs, range: range, now: now, carProfile: profile)
    }
}
