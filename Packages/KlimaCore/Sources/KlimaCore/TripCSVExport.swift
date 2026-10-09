import Foundation

/// CSV export v2 (Einstellungen › Daten): semicolon-separated for Austrian Excel, UTF-8 BOM, CRLF, de-AT decimals.
/// Adds category, "ohne Ticket nicht gefahren" and notes to the v1 columns and labels the distance unambiguously,
/// so `CSVImport` can read the file back without losing anything (round trip). "Über" holds the via stations in travel
/// order ("Feldkirch · Bludenz", docs/VIA.md); files without the column still import.
public enum TripCSVExport {
    public static let header = ["Datum", "Uhrzeit", "Von", "Nach", "Über", "Verkehrsmittel", "Hin & Retour", "Kategorie", "Ohne Ticket nicht gefahren",
                                "Distanz gesamt (km)", "Normalpreis (€)", "Wert gesamt (€)", "Notiz"]

    /// - Parameter notes: optional note per trip id (TripRecord carries no note).
    public static func trips(_ trips: [TripRecord], notes: [UUID: String] = [:], calendar: Calendar = .vienna) -> String {
        var lines = [header.map(escape).joined(separator: ";")]
        for t in trips.sorted(by: { $0.date < $1.date }) {
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: t.date)
            let date = String(format: "%02d.%02d.%04d", c.day ?? 0, c.month ?? 0, c.year ?? 0)
            let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            let row = [date, time, guardFormula(t.fromName), guardFormula(t.toName), guardFormula(TripVia.joinedNames(t.via)),
                       t.mode.displayName, t.isRoundTrip ? "ja" : "nein",
                       t.category?.displayName ?? "", t.isInduced ? "ja" : "nein",
                       decimal(t.totalDistanceKm, 1), decimal(t.fareEUR, 2), decimal(t.totalValue, 2), guardFormula(notes[t.id] ?? "")]
            lines.append(row.map(escape).joined(separator: ";"))
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    /// A ready-to-fill template (header + two example rows) for people who prepare their trips in Excel or Numbers.
    public static func template() -> String {
        let rows = [
            header,
            ["09.10.2026", "07:12", "St. Anton am Arlberg", "Innsbruck Hbf", "", "Zug", "ja", "Arbeitsweg", "nein", "", "", "", "Pendeln"],
            ["11.10.2026", "10:30", "Wien Hbf", "Salzburg Hbf", "Linz Hbf", "Zug", "nein", "Freizeit", "ja", "", "65,90", "",
             "Preis optional – sonst wird geschätzt; „Über“ optional (bis zu 2, z. B. „Linz Hbf · Wels Hbf“)"],
        ]
        return "\u{FEFF}" + rows.map { $0.map(escape).joined(separator: ";") }.joined(separator: "\r\n") + "\r\n"
    }

    static func escape(_ field: String) -> String {
        if field.contains(";") || field.contains("\"") || field.contains("\n") || field.contains("\r") || field.hasPrefix(" ") || field.hasSuffix(" ") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    /// Spreadsheet formula injection guard ("=HYPERLINK(…)" → "'=HYPERLINK(…)"); `CSVImport.unguard` reverses it.
    static func guardFormula(_ text: String) -> String {
        guard let first = text.first, "=+-@".contains(first) else { return text }
        return "'" + text
    }

    static func decimal(_ v: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", v).replacingOccurrences(of: ".", with: ",")
    }
}

/// Splits the trip table of the PDF annual report ("Dein KlimaTicket-Jahr") into pages: month header lines with subtotals,
/// one line per trip, a month header never stranded at the bottom of a page, and a continued header ("Oktober 2026 (Forts.)").
public enum ReportPagination {
    public enum Line: Hashable, Sendable {
        case month(start: Date, trips: Int, value: Double, distanceKm: Double, continued: Bool)
        case trip(TripRecord)
    }

    /// - Parameters:
    ///   - firstPageCapacity / pageCapacity: available height in points.
    ///   - monthHeight / tripHeight: line heights in points.
    public static func pages(trips: [TripRecord], firstPageCapacity: Double, pageCapacity: Double,
                             monthHeight: Double, tripHeight: Double, calendar: Calendar = .vienna) -> [[Line]] {
        let sorted = trips.sorted { $0.date < $1.date }
        guard !sorted.isEmpty else { return [] }
        // Group by calendar month.
        var groups: [(start: Date, trips: [TripRecord])] = []
        var memo = DayMemo(calendar)
        for t in sorted {
            let start = memo.startOfMonth(t.date) ?? t.date
            if let last = groups.last, last.start == start {
                groups[groups.count - 1].trips.append(t)
            } else {
                groups.append((start, [t]))
            }
        }
        var pages: [[Line]] = []
        var current: [Line] = []
        var used = 0.0
        var capacity = firstPageCapacity
        func newPage() {
            pages.append(current)
            current = []
            used = 0
            capacity = pageCapacity
        }
        for group in groups {
            let value = group.trips.reduce(0) { $0 + $1.totalValue }
            let km = group.trips.reduce(0) { $0 + $1.totalDistanceKm }
            func header(continued: Bool) -> Line {
                .month(start: group.start, trips: group.trips.count, value: value, distanceKm: km, continued: continued)
            }
            // Header + at least one trip must fit, otherwise start on a fresh page.
            if used + monthHeight + tripHeight > capacity && !current.isEmpty { newPage() }
            current.append(header(continued: false))
            used += monthHeight
            for trip in group.trips {
                if used + tripHeight > capacity {
                    newPage()
                    current.append(header(continued: true))
                    used += monthHeight
                }
                current.append(.trip(trip))
                used += tripHeight
            }
        }
        if !current.isEmpty { pages.append(current) }
        return pages
    }
}
