import Foundation

// Pendel-Modus (docs/COMMUTE.md §5): when the next connection is cancelled or at least 10 minutes late, the card says so in one
// line and names the better connection from the same search. It never invents one: without a better connection the line says so.

public struct CommuteAdvice: Hashable, Sendable {
    public enum Reason: Hashable, Sendable {
        case cancelled
        case delayed(minutes: Int)
    }

    public var reason: Reason
    /// The connection that is affected (the next one on the card).
    public var affected: CommuteRow
    /// The better connection of the same search, if there is one.
    public var alternative: CommuteRow?

    /// „Dein Zug fällt aus – nächste Verbindung 07:58, Gleis 3“ · „Dein Zug ist 12 Minuten verspätet – schneller: 07:50, Gleis 3“.
    public var headline: String {
        let lead: String
        switch reason {
        case .cancelled: lead = "\(CommuteAdvisor.yourVehicle(affected.mode)) fällt aus"
        case .delayed(let minutes): lead = "\(CommuteAdvisor.yourVehicle(affected.mode)) ist \(CommuteSpeech.minutes(minutes)) verspätet"
        }
        guard let alternative else {
            switch reason {
            case .cancelled: return lead + " – keine weitere Verbindung in dieser Suche"
            case .delayed: return lead + " – keine schnellere Verbindung"
            }
        }
        let label = reason == .cancelled ? "nächste Verbindung" : "schneller"
        let sep = reason == .cancelled ? " " : ": "
        return lead + " – " + label + sep + CommuteAdvisor.departureText(alternative)
    }
}

public enum CommuteAdvisor {
    /// Advice for the first row (the next connection), or nil when it runs (less than 10 minutes late).
    /// - cancelled: the alternative is the connection that arrives first among the others that still run;
    /// - at least 10 minutes late: the alternative must arrive earlier than the late one (else there is none).
    public static func advice(rows: [CommuteRow], now: Date) -> CommuteAdvice? {
        guard let first = rows.first else { return nil }
        let reason: CommuteAdvice.Reason
        if first.isCancelled {
            reason = .cancelled
        } else if let delay = first.delayMinutes, delay >= CommuteStatus.redFrom {
            reason = .delayed(minutes: delay)
        } else {
            return nil
        }
        let others = rows.dropFirst().filter { !$0.isCancelled && $0.effectiveDeparture >= now.addingTimeInterval(-CommuteStatus.graceSeconds) }
        func arrival(_ row: CommuteRow) -> Date { row.effectiveArrival ?? row.effectiveDeparture }
        var candidates = Array(others)
        if case .delayed = reason {
            let late = arrival(first)
            candidates = candidates.filter { arrival($0) < late }
        }
        let best = candidates.min { a, b in
            arrival(a) != arrival(b) ? arrival(a) < arrival(b) : a.effectiveDeparture < b.effectiveDeparture
        }
        return CommuteAdvice(reason: reason, affected: first, alternative: best)
    }

    /// „07:58, Gleis 3“ · „07:58 (+2), Steig B“ · „07:58“.
    public static func departureText(_ row: CommuteRow) -> String {
        var text = row.timeText
        if let delay = row.delayMinutes, delay > 0 { text += " (+\(delay))" }
        if let platform = row.platform { text += ", " + platform.spoken }
        return text
    }

    /// „Dein Zug“, „Dein Bus“, „Deine Bim“ … (the possessive that fits the noun).
    static func yourVehicle(_ mode: TransportMode) -> String {
        switch mode {
        case .bus: "Dein Bus"
        case .tram: "Deine Bim"
        case .ferry: "Dein Schiff"
        case .cableCar: "Deine Gondel"
        default: "Dein Zug"
        }
    }
}
