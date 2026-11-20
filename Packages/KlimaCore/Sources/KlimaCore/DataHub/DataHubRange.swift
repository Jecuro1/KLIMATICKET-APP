import Foundation

// MARK: data – the range every export of „Exportieren“ follows (docs/DATA_HUB.md §2), and the small formats of its preview line.

public enum DataHubRange: String, CaseIterable, Codable, Sendable, Identifiable {
    case ticketYear, calendarYear, all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ticketYear: "Ticketjahr"
        case .calendarYear: "Kalenderjahr"
        case .all: "Alles"
        }
    }

    /// The days the range covers; nil = no limit. A ticket year without a ticket covers nothing (an empty interval at `now`).
    public func interval(ticket: TicketPeriod?, now: Date, calendar: Calendar = .vienna) -> DateInterval? {
        switch self {
        case .all:
            return nil
        case .ticketYear:
            guard let ticket else { return DateInterval(start: now, duration: 0) }
            return DateInterval(start: ticket.start, end: max(ticket.start, ticket.end))
        case .calendarYear:
            let year = calendar.component(.year, from: now)
            guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
                  let next = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else { return nil }
            return DateInterval(start: start, end: next.addingTimeInterval(-1))
        }
    }

    /// „Ticketjahr 2026/27“, „Kalenderjahr 2026“, „Alle Fahrten“ – the name inside a file and its title.
    public func label(ticket: TicketPeriod?, now: Date, calendar: Calendar = .vienna) -> String {
        switch self {
        case .all:
            return "Alle Fahrten"
        case .calendarYear:
            return "Kalenderjahr \(calendar.component(.year, from: now))"
        case .ticketYear:
            guard let ticket else { return "Ticketjahr" }
            let first = calendar.component(.year, from: ticket.start)
            let last = calendar.component(.year, from: ticket.end)
            return first == last ? "Ticketjahr \(first)" : "Ticketjahr \(first)/\(String(last % 100).leftPadded(2))"
        }
    }

    /// File-name part: „Ticketjahr-2026-27“, „Kalenderjahr-2026“, „Alles“.
    public func fileTag(ticket: TicketPeriod?, now: Date, calendar: Calendar = .vienna) -> String {
        label(ticket: ticket, now: now, calendar: calendar)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "Alle-Fahrten", with: "Alles")
    }

    public static func filter(_ trips: [TripRecord], interval: DateInterval?) -> [TripRecord] {
        guard let interval else { return trips }
        return trips.filter { $0.date >= interval.start && $0.date <= interval.end }
    }
}

/// German number and size texts of the hub, the same on every device (no locale involved).
public enum DataHubFormat {
    /// „1.234“.
    public static func integer(_ value: Int) -> String {
        let digits = String(abs(value))
        var grouped = ""
        for (index, digit) in digits.reversed().enumerated() {
            if index > 0 && index % 3 == 0 { grouped.append(".") }
            grouped.append(digit)
        }
        return (value < 0 ? "−" : "") + String(grouped.reversed())
    }

    /// „1.234,5“ with `digits` decimals.
    public static func decimal(_ value: Double, digits: Int) -> String {
        guard value.isFinite else { return "–" }
        let factor = pow(10, Double(digits))
        let scaled = Int((abs(value) * factor).rounded())
        let whole = integer(scaled / Int(factor))
        guard digits > 0 else { return (value < 0 && scaled > 0 ? "−" : "") + whole }
        let fraction = String(scaled % Int(factor)).leftPadded(digits)
        return (value < 0 && scaled > 0 ? "−" : "") + whole + "," + fraction
    }

    /// „840 Byte“, „18 KB“, „1,2 MB“ (1 KB = 1000 Byte, like the Files app).
    public static func bytes(_ count: Int) -> String {
        switch count {
        case ..<1000: return "\(max(0, count)) Byte"
        case ..<999_500: return "\(Int((Double(count) / 1000).rounded())) KB"   // 999.500 Byte rounds to „1,0 MB“, not „1000 KB“
        default: return decimal(Double(count) / 1_000_000, digits: 1) + " MB"
        }
    }

    /// „123 Fahrten“.
    public static func count(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(integer(n)) \(n == 1 ? singular : plural)"
    }

    /// „19. November 2026“ (Vienna, Austrian month names).
    public static func day(_ date: Date, calendar: Calendar = .vienna) -> String {
        LetterFormat.date(date, calendar: calendar)
    }

    /// „19.11.2026, 18:03“.
    public static func dayTime(_ date: Date, calendar: Calendar = .vienna) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return "\(String(c.day ?? 0).leftPadded(2)).\(String(c.month ?? 0).leftPadded(2)).\(c.year ?? 0), "
            + "\(String(c.hour ?? 0).leftPadded(2)):\(String(c.minute ?? 0).leftPadded(2))"
    }
}

extension String {
    func leftPadded(_ width: Int) -> String {
        String(repeating: "0", count: max(0, width - count)) + self
    }
}
