import Foundation

// MARK: data – the formats of „Exportieren“ besides the backup (docs/DATA_HUB.md §2): the trips and the ticket deadlines as calendar
// files (RFC 5545, on the code of PlannerExport), the Monatsübersicht as CSV for Excel in Austria, and the Jahresbilanz as text.

// MARK: - Kalenderdatei

/// A ticket date worth a calendar entry: the end of a ticket year, the objection deadline of a renewal letter.
public struct DataHubDeadline: Hashable, Sendable {
    public var id: String
    public var day: Date
    public var title: String
    public var note: String

    public init(id: String, day: Date, title: String, note: String) {
        self.id = id
        self.day = day
        self.title = title
        self.note = note
    }
}

public enum DataHubICS {
    /// The trips as events. A trip with a known duration is an event at its time; without one it is an all-day entry, because a
    /// trip's time alone does not say how long it lasted. `durations` holds the minutes of one direction per trip id.
    public static func trips(_ trips: [TripRecord], durations: [UUID: Int] = [:], stamp: Date,
                             calendar: Calendar = .vienna) -> String {
        var lines = header(name: "KlimaBilanz – Fahrten")
        for trip in trips.sorted(by: { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }) {
            lines.append("BEGIN:VEVENT")
            lines.append("UID:trip-\(trip.id.uuidString.lowercased())@klimabilanz")
            lines.append("DTSTAMP:\(PlannerExport.utcStamp(stamp))")
            if let minutes = durations[trip.id], minutes > 0 {
                lines.append("DTSTART:\(PlannerExport.utcStamp(trip.date))")
                lines.append("DTEND:\(PlannerExport.utcStamp(trip.date.addingTimeInterval(Double(minutes) * 60)))")
            } else {
                lines += allDay(trip.date, calendar: calendar)
                lines.append("TRANSP:TRANSPARENT")
            }
            lines.append("SUMMARY:\(PlannerExport.escape(summary(trip)))")
            lines.append("DESCRIPTION:\(PlannerExport.escape(description(trip)))")
            lines.append("CATEGORIES:KlimaBilanz")
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        return lines.map(PlannerExport.fold).joined(separator: "\r\n") + "\r\n"
    }

    /// The deadlines as all-day entries, each with a reminder at 09:00 the day before.
    public static func deadlines(_ deadlines: [DataHubDeadline], stamp: Date, calendar: Calendar = .vienna) -> String {
        var lines = header(name: "KlimaBilanz – Fristen")
        for deadline in deadlines.sorted(by: { ($0.day, $0.id) < ($1.day, $1.id) }) {
            lines += ["BEGIN:VEVENT", "UID:\(deadline.id)@klimabilanz", "DTSTAMP:\(PlannerExport.utcStamp(stamp))"]
            lines += allDay(deadline.day, calendar: calendar)
            lines += ["TRANSP:TRANSPARENT", "SUMMARY:\(PlannerExport.escape(deadline.title))",
                      "DESCRIPTION:\(PlannerExport.escape(deadline.note))", "CATEGORIES:KlimaBilanz",
                      "BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:\(PlannerExport.escape(deadline.title))",
                      "TRIGGER;RELATED=START:-PT15H", "END:VALARM", "END:VEVENT"]
        }
        lines.append("END:VCALENDAR")
        return lines.map(PlannerExport.fold).joined(separator: "\r\n") + "\r\n"
    }

    /// „Zug: Innsbruck Hbf → St. Anton am Arlberg“, „… (hin und retour)“.
    public static func summary(_ trip: TripRecord) -> String {
        "\(trip.mode.displayName): \(trip.fromName) → \(trip.toName)" + (trip.isRoundTrip ? " (hin und retour)" : "")
    }

    static func description(_ trip: TripRecord) -> String {
        var parts = ["Normalpreis \(LetterFormat.euro(trip.totalValue))",
                     "\(DataHubFormat.decimal(trip.totalDistanceKm, digits: 0)) km"]
        if let category = trip.category { parts.append(category.displayName) }
        if !trip.via.isEmpty { parts.append("über \(TripVia.joinedNames(trip.via))") }
        return parts.joined(separator: " · ") + "\nAus KlimaBilanz exportiert."
    }

    private static func header(name: String) -> [String] {
        ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//KlimaBilanz//Daten//DE", "CALSCALE:GREGORIAN", "METHOD:PUBLISH",
         "X-WR-CALNAME:\(PlannerExport.escape(name))", "X-WR-TIMEZONE:Europe/Vienna"]
    }

    /// `DTSTART;VALUE=DATE:20261119` and the next day as the (exclusive) end, in Vienna's calendar.
    private static func allDay(_ date: Date, calendar: Calendar) -> [String] {
        let day = calendar.startOfDay(for: date)
        let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        return ["DTSTART;VALUE=DATE:\(dateValue(day, calendar: calendar))", "DTEND;VALUE=DATE:\(dateValue(next, calendar: calendar))"]
    }

    static func dateValue(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(c.year ?? 0).leftPadded(4) + String(c.month ?? 0).leftPadded(2) + String(c.day ?? 0).leftPadded(2)
    }
}

// MARK: - Monatsübersicht

public struct DataHubMonthRow: Hashable, Sendable, Identifiable {
    public var monthStart: Date
    /// „Oktober 2026“ (Austrian month names: „Jänner“).
    public var label: String
    /// Fahrten as the app counts them: a journey of several legs counts once.
    public var trips: Int
    public var value: Double
    public var distanceKm: Double
    public var co2SavedKg: Double

    public var id: Date { monthStart }
}

public enum DataHubMonthlyCSV {
    public static let header = ["Monat", "Fahrten", "Wert (€)", "Distanz (km)", "CO₂ gespart (kg)"]

    /// One row per month from the first to the last month of the range (or of the trips, for „Alles“), months without a trip
    /// included, so a chart in Excel shows the gaps.
    public static func rows(_ trips: [TripRecord], interval: DateInterval?, emissions: EmissionFactors = .fallback,
                            calendar: Calendar = .vienna) -> [DataHubMonthRow] {
        let inRange = DataHubRange.filter(trips, interval: interval)
        guard let first = interval?.start ?? inRange.map(\.date).min(),
              let last = interval?.end ?? inRange.map(\.date).max(),
              let startMonth = calendar.dateInterval(of: .month, for: first)?.start else { return [] }
        var byMonth: [Date: [TripRecord]] = [:]
        var memo = DayMemo(calendar)
        for trip in inRange { byMonth[memo.startOfMonth(trip.date) ?? trip.date, default: []].append(trip) }
        var rows: [DataHubMonthRow] = []
        var month = startMonth
        while month <= last && rows.count < 1200 {
            let monthTrips = byMonth[month] ?? []
            let c = calendar.dateComponents([.year, .month], from: month)
            rows.append(DataHubMonthRow(
                monthStart: month,
                label: "\(LetterFormat.monthNames[max(0, min(11, (c.month ?? 1) - 1))]) \(c.year ?? 0)",
                trips: JourneySummary.tripCount(monthTrips),
                value: monthTrips.reduce(0) { $0 + $1.totalValue },
                distanceKm: monthTrips.reduce(0) { $0 + $1.totalDistanceKm },
                co2SavedKg: monthTrips.reduce(0) { $0 + emissions.savedKg(km: $1.totalDistanceKm, mode: $1.mode) }))
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
        }
        return rows
    }

    /// Semicolons, decimal comma, CRLF, UTF-8 with BOM (Excel in Austria opens it in columns); a last row „Gesamt“.
    /// `totalTrips` is the range's own count (a journey across a month's end counts once in the total).
    public static func csv(_ rows: [DataHubMonthRow], totalTrips: Int? = nil) -> String {
        var lines = [header.map(TripCSVExport.escape).joined(separator: ";")]
        for row in rows {
            lines.append([row.label, String(row.trips), TripCSVExport.decimal(row.value, 2),
                          TripCSVExport.decimal(row.distanceKm, 1), TripCSVExport.decimal(row.co2SavedKg, 1)]
                .map(TripCSVExport.escape).joined(separator: ";"))
        }
        if !rows.isEmpty {
            lines.append(["Gesamt", String(totalTrips ?? rows.reduce(0) { $0 + $1.trips }),
                          TripCSVExport.decimal(rows.reduce(0) { $0 + $1.value }, 2),
                          TripCSVExport.decimal(rows.reduce(0) { $0 + $1.distanceKm }, 1),
                          TripCSVExport.decimal(rows.reduce(0) { $0 + $1.co2SavedKg }, 1)]
                .map(TripCSVExport.escape).joined(separator: ";"))
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }
}

// MARK: - Jahresbilanz als Text

public enum DataHubYearText {
    /// Markdown for mail or notes: headline, the figures, months, frequent routes and where the numbers come from. With a ticket
    /// (range „Ticketjahr“) it compares the value with the price; otherwise it only adds up.
    public static func markdown(trips allTrips: [TripRecord], range: DataHubRange, ticket: TicketPeriod?, now: Date,
                                emissions: EmissionFactors = .fallback, calendar: Calendar = .vienna) -> String {
        let interval = range.interval(ticket: ticket, now: now, calendar: calendar)
        let trips = DataHubRange.filter(allTrips, interval: interval).sorted { $0.date < $1.date }
        let label = range.label(ticket: ticket, now: now, calendar: calendar)
        var out = ["# Meine KlimaBilanz – \(label)", ""]
        if range == .ticketYear, let ticket {
            out.append("\(ticket.name) · \(DataHubFormat.day(ticket.start, calendar: calendar)) bis \(DataHubFormat.day(ticket.end, calendar: calendar))")
            out.append("")
        }
        guard !trips.isEmpty else {
            out += ["Noch keine Fahrten in diesem Zeitraum.", "", footer(now: now, calendar: calendar)]
            return out.joined(separator: "\n") + "\n"
        }
        let value = trips.reduce(0) { $0 + $1.totalValue }
        let km = trips.reduce(0) { $0 + $1.totalDistanceKm }
        let co2 = trips.reduce(0) { $0 + emissions.savedKg(km: $1.totalDistanceKm, mode: $1.mode) }
        var memo = DayMemo(calendar)
        let days = Set(trips.map { memo.startOfDay($0.date) }).count
        let count = JourneySummary.tripCount(trips)
        if range == .ticketYear, let ticket {
            if ticket.price <= 0 {
                out.append("**\(LetterFormat.euro(value)) Wert** – das Ticket hat dich nichts gekostet.")
            } else if value >= ticket.price {
                out.append("**\(LetterFormat.euro(value)) Wert** bei \(LetterFormat.euro(ticket.price)) Ticketpreis – rentiert, \(LetterFormat.euro(value - ticket.price)) im Plus.")
            } else {
                out.append("**\(LetterFormat.euro(value)) Wert** bei \(LetterFormat.euro(ticket.price)) Ticketpreis – noch \(LetterFormat.euro(ticket.price - value)), bis es sich rentiert.")
            }
        } else {
            out.append("**\(LetterFormat.euro(value)) Wert** zu Normalpreisen.")
        }
        out += ["",
                "- Fahrten: \(DataHubFormat.integer(count)) an \(DataHubFormat.count(days, "Tag", "Tagen"))",
                "- Strecke: \(DataHubFormat.integer(Int(km.rounded()))) km",
                "- CO₂ gespart: \(DataHubFormat.integer(Int(co2.rounded()))) kg gegenüber dem Auto allein",
                "", "## Monate", "", "| Monat | Fahrten | Wert | km |", "|---|---:|---:|---:|"]
        for row in DataHubMonthlyCSV.rows(trips, interval: nil, emissions: emissions, calendar: calendar) where row.trips > 0 {
            out.append("| \(row.label) | \(row.trips) | \(LetterFormat.euro(row.value)) | \(DataHubFormat.integer(Int(row.distanceKm.rounded()))) |")
        }
        let routes = topRoutes(trips, limit: 3)
        if !routes.isEmpty {
            out += ["", "## Häufigste Strecken", ""]
            for (index, route) in routes.enumerated() {
                out.append("\(index + 1). \(route.name) – \(DataHubFormat.count(route.count, "Fahrt", "Fahrten"))")
            }
        }
        out += ["", footer(now: now, calendar: calendar)]
        return out.joined(separator: "\n") + "\n"
    }

    /// The most frequent routes, direction-independent, as „Innsbruck Hbf ↔ St. Anton am Arlberg“ (the first spelling seen).
    static func topRoutes(_ trips: [TripRecord], limit: Int) -> [(name: String, count: Int)] {
        var counts: [String: (name: String, count: Int, first: Date)] = [:]
        for trip in trips {
            let key = trip.routeKey
            if let entry = counts[key] {
                counts[key] = (entry.name, entry.count + 1, entry.first)
            } else {
                counts[key] = ("\(trip.fromName) ↔ \(trip.toName)", 1, trip.date)
            }
        }
        return counts.values.filter { $0.count >= 2 }
            .sorted { ($0.count, $1.first) > ($1.count, $0.first) }
            .prefix(limit).map { ($0.name, $0.count) }
    }

    static func footer(now: Date, calendar: Calendar) -> String {
        "_Erstellt mit KlimaBilanz am \(DataHubFormat.day(now, calendar: calendar)). Werte sind Normalpreise laut Tarif-Tabellen ohne KlimaTicket, keine Rechnung; CO₂ nach Umweltbundesamt (Auto allein gegenüber Öffi)._"
    }
}
