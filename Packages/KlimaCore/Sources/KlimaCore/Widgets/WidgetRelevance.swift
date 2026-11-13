import Foundation

/// Smart Stack relevance of the widget timeline entries (docs/WIDGETS_SMARTSTACK.md §3). WidgetKit compares the scores of
/// a widget's entries with each other; whether the Smart Stack rotates a widget to the top is the system's decision. The
/// scores come only from what the entries already hold (the app-written caches and the ticket snapshot): no network and
/// no extra reloads. Pure functions, unit-tested on Linux.
public enum WidgetRelevance {
    /// Score of the connection and departure widgets shortly before a departure.
    public static let departurePeak: Double = 100
    /// The peak starts this long before the next departure.
    public static let departureLead: TimeInterval = 45 * 60
    /// After the departure the score falls in a straight line to 0 within this time.
    public static let departureDecay: TimeInterval = 5 * 60

    /// Score of "Ticket-Restzeit" in the last days of the validity.
    public static let ticketEndScore: Double = 30
    /// The last 14 days of the validity count (the last day included).
    public static let ticketEndDays = 14

    /// Score of "Break-even" on the forecast day.
    public static let breakEvenScore: Double = 60

    // MARK: Components

    /// 100 from 45 minutes before `nextDeparture` until it leaves, then down to 0 within five minutes; 0 earlier and
    /// without a departure.
    public static func departure(now: Date, nextDeparture: Date?) -> Double {
        guard let nextDeparture else { return 0 }
        let ahead = nextDeparture.timeIntervalSince(now)
        if ahead > departureLead { return 0 }
        if ahead >= 0 { return departurePeak }
        let past = -ahead
        guard past < departureDecay else { return 0 }
        return departurePeak * (1 - past / departureDecay)
    }

    /// 30 on each of the last 14 Vienna days of the validity (`validUntil` is the ticket's last day), 0 before and after.
    public static func ticketRemaining(now: Date, validUntil: Date?, calendar: Calendar = .vienna) -> Double {
        guard let validUntil, now <= validUntil else { return 0 }
        let daysLeft = days(from: now, to: validUntil, calendar: calendar)
        return (0..<ticketEndDays).contains(daysLeft) ? ticketEndScore : 0
    }

    /// 60 on the Vienna day of the break-even forecast, 0 on every other day and without a forecast.
    public static func breakEven(now: Date, breakEvenDate: Date?, calendar: Calendar = .vienna) -> Double {
        guard let breakEvenDate else { return 0 }
        return calendar.isDate(now, inSameDayAs: breakEvenDate) ? breakEvenScore : 0
    }

    /// The highest of the three: what the debug list shows next to an entry date.
    public static func score(now: Date, nextDeparture: Date?, validUntil: Date?, breakEvenDate: Date?,
                             calendar: Calendar = .vienna) -> Double {
        max(departure(now: now, nextDeparture: nextDeparture),
            ticketRemaining(now: now, validUntil: validUntil, calendar: calendar),
            breakEven(now: now, breakEvenDate: breakEvenDate, calendar: calendar))
    }

    // MARK: Entry dates

    /// The moments the departure score changes for `departures` (sorted or not): 45 minutes before each one and the end
    /// of its decay. Only moments after `now`; at most `limit`, earliest first. The providers add them to the entry
    /// dates of the list itself, so the score rises without a reload.
    public static func departureChangeDates(_ departures: [Date], now: Date, limit: Int = 4) -> [Date] {
        var dates = Set<Date>()
        for departure in departures {
            for date in [departure.addingTimeInterval(-departureLead), departure.addingTimeInterval(departureDecay)]
            where date > now {
                dates.insert(date)
            }
        }
        return Array(dates.sorted().prefix(max(0, limit)))
    }

    /// `base` and `extra` merged, sorted, unique, at most `limit` (the base dates keep their place first: the extra ones
    /// fill the remaining room).
    public static func merged(_ base: [Date], _ extra: [Date], limit: Int) -> [Date] {
        let baseSet = Set(base)
        let room = max(0, limit - baseSet.count)
        let added = extra.filter { !baseSet.contains($0) }.sorted().prefix(room)
        return Array((baseSet.union(added)).sorted().prefix(max(1, limit)))
    }

    // MARK: Helpers

    static func days(from start: Date, to end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }
}
