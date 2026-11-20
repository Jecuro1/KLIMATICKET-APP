import Foundation

// MARK: siri – what Siri and the Kurzbefehle-App can be asked (docs/SIRI_QUESTIONS.md §3). The titles are the Übersicht's KPI titles
// (KpiKind), so a question is called what the tile is called. „Lieblingsstrecke“ is not offered: station names stay out of voice
// answers.

public enum KpiQuestion: String, CaseIterable, Codable, Sendable, Identifiable {
    case trips, value, distance, co2, net, daysLeft, breakEven, costPerDay

    public var id: String { rawValue }

    /// The Übersicht's figure this question reads out; nil for „Fehlt bis Break-even“ (no tile of its own).
    public var kpi: KpiKind? {
        switch self {
        case .trips: .tripCount
        case .value: .totalValue
        case .distance: .distance
        case .co2: .co2
        case .net: .net
        case .daysLeft: .daysRemaining
        case .breakEven: nil
        case .costPerDay: .costPerDay
        }
    }

    public var title: String { kpi?.title ?? "Fehlt bis Break-even" }

    public var symbol: String { kpi?.symbol ?? "flag.checkered" }

    /// Answered for the ticket year only (the period is ignored, and named when another one was asked).
    public var isTicketOnly: Bool {
        switch self {
        case .trips, .value, .distance, .co2: false
        case .net, .daysLeft, .breakEven, .costPerDay: true
        }
    }

    /// The asked period does not matter at all (no „nur fürs Ticketjahr“ note): a date and a price per day.
    public var ignoresPeriod: Bool { self == .daysLeft || self == .costPerDay }

    /// What one says to Siri („… in KlimaBilanz“) – shown in Einstellungen as an example.
    public var example: String {
        switch self {
        case .trips: "Wie viele Fahrten diesen Monat"
        case .value: "Wert meiner Fahrten"
        case .distance: "Wie viele Kilometer"
        case .co2: "Wie viel CO₂ habe ich gespart"
        case .net: "Bin ich im Plus"
        case .daysLeft: "Wann läuft mein Ticket ab"
        case .breakEven: "Wie viel fehlt bis zum Break-even"
        case .costPerDay: "Was kostet mein Ticket pro Tag"
        }
    }
}

public enum KpiPeriod: String, CaseIterable, Codable, Sendable, Identifiable {
    case thisWeek, thisMonth, lastMonth, ticketYear, calendarYear

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .thisWeek: "Diese Woche"
        case .thisMonth: "Dieser Monat"
        case .lastMonth: "Letzter Monat"
        case .ticketYear: "Ticketjahr"
        case .calendarYear: "Kalenderjahr"
        }
    }

    /// The days of a calendar period around `now` as day keys (inclusive) and how the answer names it. nil for the ticket year,
    /// which is answered from the ticket's own figures.
    public func range(now: Date, weekStart: FormatPrefs.WeekStart = .monday, calendar: Calendar = .vienna) -> KpiPeriodRange? {
        let c = calendar.dateComponents([.year, .month], from: now)
        let year = c.year ?? 2026, month = c.month ?? 1
        switch self {
        case .ticketYear:
            return nil
        case .thisWeek:
            let start = weekStart.startOfWeek(containing: now, in: calendar)
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            return KpiPeriodRange(first: KpiDailyTable.dayKey(start, calendar: calendar), last: KpiDailyTable.dayKey(end, calendar: calendar),
                                  name: "diese Woche", label: "Diese Woche")
        case .thisMonth:
            return Self.month(year: year, month: month, nowYear: year)
        case .lastMonth:
            return month == 1 ? Self.month(year: year - 1, month: 12, nowYear: year) : Self.month(year: year, month: month - 1, nowYear: year)
        case .calendarYear:
            return KpiPeriodRange(first: KpiDailyTable.dayKey(year: year, month: 1, day: 1), last: KpiDailyTable.dayKey(year: year, month: 12, day: 31),
                                  name: "im Jahr \(year)", label: "\(year)")
        }
    }

    private static func month(year: Int, month: Int, nowYear: Int) -> KpiPeriodRange {
        let name = KpiSpoken.monthNames[month - 1]
        let named = year == nowYear ? name : "\(name) \(year)"
        // Day 31 bounds every month: the keys compare as text and no month has a later day.
        return KpiPeriodRange(first: KpiDailyTable.dayKey(year: year, month: month, day: 1), last: KpiDailyTable.dayKey(year: year, month: month, day: 31),
                              name: "im \(named)", label: "\(name) \(year)")
    }
}

/// Days of a calendar period and its names.
public struct KpiPeriodRange: Equatable, Sendable {
    /// First and last day key, inclusive.
    public var first: String
    public var last: String
    /// In a sentence: „im Oktober“, „diese Woche“, „im Jahr 2026“, „im Dezember 2025“.
    public var name: String
    /// Under the figure: „Oktober 2026“, „Diese Woche“, „2026“.
    public var label: String
}
