import Foundation

/// The ticket balance as the Übersicht shows it, for the "Warum lohnt sich mein Ticket?" text. It copies numbers from
/// `SavingsSummary` and formats them; it computes nothing new, so the model never sees a figure the app did not compute
/// (docs/LOCAL_AI.md §4).
public struct BalanceFacts: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case paidOff
        case onTrack
        case behind
        case expired
    }

    public var ticketName: String
    public var phase: Phase
    public var ticketPrice: Double
    public var valueSoFar: Double
    public var net: Double
    public var remainingToBreakEven: Double
    public var tripCount: Int
    public var distanceKm: Double
    public var co2SavedKg: Double
    public var daysRemaining: Int
    public var forecastBreakEven: Date?
    public var forecastEndValue: Double
    public var averageValuePerTrip: Double
    /// Display lines, one fact each. The model prompt and `AssistantNumberGuard` both use exactly these.
    public var lines: [String]

    public static func make(ticketName: String, summary: SavingsSummary, isExpired: Bool, calendar: Calendar = .vienna) -> BalanceFacts {
        let phase: Phase
        if summary.isPaidOff {
            phase = .paidOff
        } else if isExpired {
            phase = .expired
        } else if summary.forecastBreakEvenDate != nil, summary.forecastReachesBreakEven {
            phase = .onTrack
        } else {
            phase = .behind
        }
        let f = AssistantFormat.self
        let remaining = summary.remainingToBreakEven
        var lines = [
            "Ticket: \(ticketName)",
            "Ticketpreis: \(f.euro(summary.ticketPrice))",
            "Wert bisher: \(f.euro(summary.totalValue))",
            "Fahrten: \(f.integer(summary.tripCount))",
            "Kilometer: \(f.kilometres(summary.distanceKm))",
            "CO₂ gespart: \(f.integer(Int(summary.co2SavedKg.rounded()))) kg",
        ]
        if summary.tripCount > 0 {
            lines.append("Durchschnitt pro Fahrt: \(f.euro(summary.averageValuePerTrip))")
        }
        if phase == .paidOff {
            lines.append("Gewinn bisher: \(f.euro(summary.net))")
        } else {
            lines.append("Fehlt bis zum Preis: \(f.euro(remaining))")
        }
        if phase != .expired, phase != .paidOff {
            lines.append("Tage bis Ticketende: \(f.integer(summary.daysRemaining))")
        }
        if let date = summary.forecastBreakEvenDate, phase == .onTrack || phase == .behind {
            lines.append("Break-even-Prognose: \(f.dayMonth(date, calendar: calendar))")
        }
        if phase == .behind {
            lines.append("Prognose Wert am Ticketende: \(f.euro(summary.forecastEndValue))")
        }
        return BalanceFacts(ticketName: ticketName, phase: phase, ticketPrice: summary.ticketPrice,
                            valueSoFar: summary.totalValue, net: summary.net, remainingToBreakEven: remaining,
                            tripCount: summary.tripCount, distanceKm: summary.distanceKm, co2SavedKg: summary.co2SavedKg,
                            daysRemaining: summary.daysRemaining, forecastBreakEven: summary.forecastBreakEvenDate,
                            forecastEndValue: summary.forecastEndValue, averageValuePerTrip: summary.averageValuePerTrip,
                            lines: lines)
    }

    /// The deterministic explanation. Used whenever the model is off, unavailable, or its text fails the number check.
    public var ruleText: String {
        let f = AssistantFormat.self
        let trips = tripCount == 1 ? "eine Fahrt" : "\(f.integer(tripCount)) Fahrten"
        switch phase {
        case .paidOff:
            return "Dein Ticket hat sich schon rentiert. Bisher stehen \(f.euro(valueSoFar)) Fahrtwert bei einem Preis von "
                + "\(f.euro(ticketPrice)) zu Buche, das ist ein Gewinn von \(f.euro(net)). Jede weitere Fahrt ist reiner Vorteil."
        case .onTrack:
            let date = forecastBreakEven.map { f.dayMonth($0) } ?? ""
            return "Dein Ticket rentiert sich voraussichtlich am \(date), also vor dem Ablauf. Bisher hast du \(trips) erfasst, "
                + "Wert \(f.euro(valueSoFar)) bei einem Preis von \(f.euro(ticketPrice)). Bis zum Break-even fehlen noch "
                + "\(f.euro(remainingToBreakEven))."
        case .behind:
            if tripCount == 0 {
                return "Du hast noch keine Fahrt erfasst. Sobald du eine erfasst, rechnet KlimaBilanz den Wert aus. "
                    + "Bis der Preis von \(f.euro(ticketPrice)) erreicht ist, fehlen dann noch \(f.euro(remainingToBreakEven))."
            }
            let reach = forecastEndValue < ticketPrice ? "Das reicht im bisherigen Tempo noch nicht ganz."
                : "Im bisherigen Tempo wird es knapp."
            return "Bisher hast du \(trips) im Wert von \(f.euro(valueSoFar)) erfasst. Bis der Preis von \(f.euro(ticketPrice)) "
                + "erreicht ist, fehlen noch \(f.euro(remainingToBreakEven)). Bis Ticketende kommst du im bisherigen Tempo auf "
                + "\(f.euro(forecastEndValue)). \(reach)"
        case .expired:
            return "Das Ticket ist abgelaufen. Am Ende standen \(f.euro(valueSoFar)) Fahrtwert bei einem Preis von "
                + "\(f.euro(ticketPrice)) zu Buche. Es fehlten \(f.euro(remainingToBreakEven))."
        }
    }
}

/// A short recap for the Sunday notification: this week's trips, value and kilometres, with the date the figures are from.
/// The notification is scheduled in the foreground, so "Stand" tells the user when the numbers were taken.
public struct WeeklyRecapFacts: Equatable, Sendable {
    public var tripsThisWeek: Int
    public var valueThisWeek: Double
    public var kmThisWeek: Double
    public var asOf: Date
    public var lines: [String]

    public static func make(trips: [TripRecord], now: Date, calendar: Calendar = .vienna) -> WeeklyRecapFacts {
        let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let week = trips.filter { $0.date >= start && $0.date <= now }
        let value = week.reduce(0) { $0 + $1.totalValue }
        let km = week.reduce(0) { $0 + $1.totalDistanceKm }
        let f = AssistantFormat.self
        let lines = [
            "Fahrten diese Woche: \(f.integer(week.count))",
            "Wert diese Woche: \(f.euro(value))",
            "Kilometer diese Woche: \(f.kilometres(km))",
            "Stand: \(f.dayMonth(now, calendar: calendar))",
        ]
        return WeeklyRecapFacts(tripsThisWeek: week.count, valueThisWeek: value, kmThisWeek: km, asOf: now, lines: lines)
    }

    /// One short sentence for the notification body.
    public var ruleText: String {
        let f = AssistantFormat.self
        let stand = f.dayMonth(asOf)
        if tripsThisWeek == 0 {
            return "Diese Woche ist noch keine Fahrt erfasst. Stand \(stand)"
        }
        let trips = tripsThisWeek == 1 ? "eine Fahrt" : "\(f.integer(tripsThisWeek)) Fahrten"
        return "Diese Woche: \(trips), Wert \(f.euro(valueThisWeek)), \(f.kilometres(kmThisWeek)). Stand \(stand)"
    }
}

/// A saved relation with the start times of its recent trips, for "du fährst meist um diese Zeit".
public struct RouteStarts: Equatable, Sendable {
    public var fromID: String
    public var toID: String
    public var starts: [Date]

    public init(fromID: String, toID: String, starts: [Date]) {
        self.fromID = fromID
        self.toID = toID
        self.starts = starts
    }

    /// Groups trips (from, to, start) by relation. Trips without both station IDs or with the same station twice are skipped.
    public static func group(_ trips: [(from: String?, to: String?, start: Date)]) -> [RouteStarts] {
        var order: [String] = []
        var map: [String: RouteStarts] = [:]
        for trip in trips {
            guard let from = trip.from, let to = trip.to, from != to else { continue }
            let key = from + ">" + to
            if map[key] == nil {
                map[key] = RouteStarts(fromID: from, toID: to, starts: [])
                order.append(key)
            }
            map[key]?.starts.append(trip.start)
        }
        return order.compactMap { map[$0] }
    }
}

public struct RouteTimeSuggestion: Equatable, Sendable {
    public var fromID: String
    public var toID: String
    /// Trips of this relation that started within the window around the current hour.
    public var matching: Int
    public var total: Int
}

/// Rule-based suggestion: a saved relation that is usually driven around this time of day. Needs enough trips and a clear
/// share, so a single trip never makes a "usual" time.
public enum RouteTimeSuggestions {
    public static func suggest(_ routes: [RouteStarts], now: Date, calendar: Calendar = .vienna, window: Int = 1,
                               minMatching: Int = 3, minShare: Double = 0.4, limit: Int = 1) -> [RouteTimeSuggestion] {
        let hour = calendar.component(.hour, from: now)
        let near = Set((-window...window).map { ($0 + hour + 24) % 24 })
        var out: [RouteTimeSuggestion] = []
        for route in routes where !route.starts.isEmpty {
            let matching = route.starts.filter { near.contains(calendar.component(.hour, from: $0)) }.count
            let share = Double(matching) / Double(route.starts.count)
            if matching >= minMatching, share >= minShare {
                out.append(RouteTimeSuggestion(fromID: route.fromID, toID: route.toID, matching: matching, total: route.starts.count))
            }
        }
        out.sort { $0.matching != $1.matching ? $0.matching > $1.matching : ($0.fromID + $0.toID) < ($1.fromID + $1.toID) }
        return Array(out.prefix(limit))
    }
}

/// Instructions and prompts for the on-device model. The prompts carry only the user's sentence or the facts lines.
public enum AssistantPrompts {
    public static func tripQueryInstructions(today: String) -> String {
        "Du liest einen deutschen Satz über eine Zugfahrt in Österreich und trägst die Felder ein. Orte nur so ein, wie sie im "
            + "Satz stehen. Datum als JJJJ-MM-TT, Uhrzeit als HH:MM. Lass ein Feld leer, wenn der Satz es nicht nennt. "
            + "Erfinde nichts. Heute ist \(today)."
    }

    public static let balanceInstructions =
        "Du erklärst einer Pendlerin oder einem Pendler in Österreich, ob sich das KlimaTicket rentiert. Schreibe auf Deutsch, "
        + "in der Du-Form, warm und klar, höchstens vier kurze Sätze, ohne Überschrift und ohne Aufzählung. Verwende nur die "
        + "Angaben in der Liste und übernimm jede Zahl genau so, wie sie dort steht. Erfinde keine Zahlen, Preise, Strecken "
        + "oder Termine."

    public static let recapInstructions =
        "Du schreibst einen Wochenrückblick für ein Ticket in Österreich in einem kurzen Satz auf Deutsch, Du-Form. Verwende nur "
        + "die Angaben in der Liste und übernimm jede Zahl genau so, wie sie dort steht. Erfinde nichts."

    public static func facts(_ lines: [String]) -> String {
        "Angaben:\n" + lines.map { "- " + $0 }.joined(separator: "\n")
    }
}
