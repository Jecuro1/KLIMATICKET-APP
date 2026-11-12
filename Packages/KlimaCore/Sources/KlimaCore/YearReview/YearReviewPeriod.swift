import Foundation

// "Dein Jahr" (docs/YEAR_REVIEW.md): the span a year story covers – one ticket period or one calendar year. Pure value
// logic in Europe/Vienna; nothing here is persisted.

/// What the story is about: a ticket period ("Ticket-Jahr 2026/27") or a calendar year ("Kalenderjahr 2026").
public struct YearReviewPeriod: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable {
        case ticket
        case calendarYear
    }

    public var kind: Kind
    /// First instant of the span (Vienna midnight).
    public var start: Date
    /// Last instant of the span (the last second of its last day) – inclusive, like `TicketPeriod.end`.
    public var end: Date
    /// The ticket of a `.ticket` period.
    public var ticket: TicketPeriod?
    /// The year of a `.calendarYear` period.
    public var year: Int?

    public init(kind: Kind, start: Date, end: Date, ticket: TicketPeriod? = nil, year: Int? = nil) {
        self.kind = kind
        self.start = start
        self.end = end
        self.ticket = ticket
        self.year = year
    }

    public var id: String {
        switch kind {
        case .ticket: "ticket:\(ticket?.productID ?? "-"):\(Int(start.timeIntervalSince1970))"
        case .calendarYear: "year:\(year ?? 0)"
        }
    }

    public func contains(_ date: Date) -> Bool { date >= start && date <= end }

    /// "2026/27", or "2026" when the span lies within one calendar year (same rule as the Statistik header).
    public func yearLabel(calendar: Calendar = .vienna) -> String {
        let first = calendar.component(.year, from: start)
        let last = calendar.component(.year, from: end)
        guard first != last else { return String(first) }
        return "\(first)/\(String(format: "%02d", last % 100))"
    }

    /// "Ticket-Jahr 2026/27" · "Kalenderjahr 2026".
    public func title(calendar: Calendar = .vienna) -> String {
        switch kind {
        case .ticket: "Ticket-Jahr \(yearLabel(calendar: calendar))"
        case .calendarYear: "Kalenderjahr \(yearLabel(calendar: calendar))"
        }
    }
}

public enum YearReviewPeriods {
    /// The story of `year` (1 Jan – 31 Dec, Vienna).
    public static func calendarYear(_ year: Int, calendar: Calendar = .vienna) -> YearReviewPeriod {
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date(timeIntervalSince1970: 0)
        let next = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? start
        let end = calendar.date(byAdding: .second, value: -1, to: next) ?? next
        return YearReviewPeriod(kind: .calendarYear, start: start, end: end, year: year)
    }

    public static func ticketPeriod(_ ticket: TicketPeriod) -> YearReviewPeriod {
        YearReviewPeriod(kind: .ticket, start: ticket.start, end: ticket.end, ticket: ticket)
    }

    /// The year the seasonal card and the default period are about: 1–31 Dec the year that is ending, 1–31 Jan the year
    /// that just ended; nil during the rest of the year.
    public static func seasonalYear(now: Date, calendar: Calendar = .vienna) -> Int? {
        let parts = calendar.dateComponents([.year, .month], from: now)
        guard let year = parts.year, let month = parts.month else { return nil }
        switch month {
        case 12: return year
        case 1: return year - 1
        default: return nil
        }
    }

    /// Calendar years that have at least one trip, newest first.
    public static func yearsWithTrips(_ trips: [TripRecord], calendar: Calendar = .vienna) -> [Int] {
        var years = Set<Int>()
        for trip in trips { years.insert(calendar.component(.year, from: trip.date)) }
        return years.sorted(by: >)
    }

    /// The ticket the "Ticket-Jahr" choice shows: `preferred` (what the app treats as the active ticket), else the one
    /// running now, else the last one that ended, else the earliest upcoming one.
    public static func currentTicket(in tickets: [TicketPeriod], preferred: TicketPeriod? = nil, now: Date) -> TicketPeriod? {
        if let preferred { return preferred }
        if let running = tickets.filter({ $0.contains(now) }).max(by: { $0.start < $1.start }) { return running }
        if let last = tickets.filter({ $0.end < now }).max(by: { $0.end < $1.end }) { return last }
        return tickets.min { $0.start < $1.start }
    }

    /// The period the story opens with: from 1 Dec to 31 Jan the calendar year that is ending or just ended (when it has
    /// trips), otherwise the active ticket period; without any ticket the newest year with trips.
    public static func defaultPeriod(tickets: [TicketPeriod], trips: [TripRecord], now: Date, preferredTicket: TicketPeriod? = nil,
                                     calendar: Calendar = .vienna) -> YearReviewPeriod {
        let years = yearsWithTrips(trips, calendar: calendar)
        if let seasonal = seasonalYear(now: now, calendar: calendar), years.contains(seasonal) {
            return calendarYear(seasonal, calendar: calendar)
        }
        if let ticket = currentTicket(in: tickets, preferred: preferredTicket, now: now) {
            return ticketPeriod(ticket)
        }
        if let newest = years.first { return calendarYear(newest, calendar: calendar) }
        return calendarYear(calendar.component(.year, from: now), calendar: calendar)
    }

    /// What the first page offers: the "Ticket-Jahr" (running or last ticket period) first, then every calendar year with
    /// trips, newest first. The default period is always among them.
    public static func choices(tickets: [TicketPeriod], trips: [TripRecord], now: Date, preferredTicket: TicketPeriod? = nil,
                               calendar: Calendar = .vienna) -> [YearReviewPeriod] {
        var result: [YearReviewPeriod] = []
        if let ticket = currentTicket(in: tickets, preferred: preferredTicket, now: now) {
            result.append(ticketPeriod(ticket))
        }
        for year in yearsWithTrips(trips, calendar: calendar) {
            result.append(calendarYear(year, calendar: calendar))
        }
        let fallback = defaultPeriod(tickets: tickets, trips: trips, now: now, preferredTicket: preferredTicket, calendar: calendar)
        if !result.contains(where: { $0.id == fallback.id }) { result.insert(fallback, at: 0) }
        return result
    }

    // MARK: Accounting

    /// The period as one `TicketPeriod`, so that every figure comes out of the same calculators as Statistik
    /// (`SavingsCalculator`, `CategoryStats.honestBalance`, `CarComparison`).
    ///
    /// A ticket period is the ticket itself. A calendar year gets the own ticket costs **pro rata**: each ticket that
    /// overlaps the year contributes its price × (days of the ticket inside the year, up to today) ÷ (days of the ticket).
    /// A year without any ticket has price 0 – the story then shows the value of the trips but claims no saving.
    public static func accountingPeriod(for period: YearReviewPeriod, tickets: [TicketPeriod], now: Date,
                                        calendar: Calendar = .vienna) -> TicketPeriod {
        if period.kind == .ticket, let ticket = period.ticket { return ticket }
        let year = period.year ?? calendar.component(.year, from: period.start)
        let accrualEnd = calendar.startOfDay(for: min(period.end, now))
        let periodStart = calendar.startOfDay(for: period.start)
        var cost = 0.0
        var daysByName: [String: Int] = [:]
        for ticket in tickets {
            let ticketStart = calendar.startOfDay(for: ticket.start)
            let ticketEnd = calendar.startOfDay(for: ticket.end)
            let from = max(ticketStart, periodStart)
            let to = min(ticketEnd, accrualEnd)
            guard from <= to else { continue }
            let ticketDays = max(1, (calendar.dateComponents([.day], from: ticketStart, to: ticketEnd).day ?? 364) + 1)
            let overlap = (calendar.dateComponents([.day], from: from, to: to).day ?? 0) + 1
            cost += ticket.price * Double(overlap) / Double(ticketDays)
            daysByName[ticket.name, default: 0] += overlap
        }
        let name = daysByName.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? "KlimaTicket"
        return TicketPeriod(productID: "year-\(year)", name: name, price: cost, start: period.start, end: period.end)
    }
}
