import Foundation
import KlimaCore

/// Durations and sentences of the „Zeitbilanz“ (de-AT, du-Form). Every number goes through `Format.number`.
enum TimeBalanceText {
    // MARK: Durations

    /// The hero's number and unit: "45" "Min." · "4,5" "Std." · "128" "Std."
    struct Parts: Equatable {
        var value: Double
        var decimals: Int
        var unit: String
    }

    static func parts(_ minutes: Double) -> Parts {
        let rounded = max(0, minutes.isFinite ? minutes.rounded() : 0)
        if rounded < 60 { return Parts(value: rounded, decimals: 0, unit: "Min.") }
        let hours = rounded / 60
        if hours < 10 {
            let tenths = (hours * 10).rounded() / 10
            return Parts(value: tenths, decimals: tenths == tenths.rounded() ? 0 : 1, unit: "Std.")
        }
        return Parts(value: hours.rounded(), decimals: 0, unit: "Std.")
    }

    /// "45 Min." · "4,5 Std." · "128 Std." – sums.
    static func short(_ minutes: Double) -> String {
        let p = parts(minutes)
        return "\(Format.number(p.value, decimals: p.decimals)) \(p.unit)"
    }

    /// "1 Std. 15 Min." · "45 Min." · "3 Std." – one trip.
    static func clock(_ minutes: Double) -> String {
        let total = Int(max(0, minutes.isFinite ? minutes : 0).rounded())
        let hours = total / 60, rest = total % 60
        if hours == 0 { return "\(rest) Min." }
        if rest == 0 { return "\(Format.number(Double(hours))) Std." }
        return "\(Format.number(Double(hours))) Std. \(rest) Min."
    }

    /// What VoiceOver says: "4,5 Stunden", "1 Stunde 15 Minuten", "45 Minuten".
    static func spoken(_ minutes: Double, exact: Bool = false) -> String {
        if exact {
            let total = Int(max(0, minutes.isFinite ? minutes : 0).rounded())
            let hours = total / 60, rest = total % 60
            let h = hours == 1 ? "1 Stunde" : "\(Format.number(Double(hours))) Stunden"
            let m = rest == 1 ? "1 Minute" : "\(rest) Minuten"
            if hours == 0 { return m }
            return rest == 0 ? h : "\(h) \(m)"
        }
        let p = parts(minutes)
        if p.unit == "Min." { return p.value == 1 ? "1 Minute" : "\(Format.number(p.value)) Minuten" }
        return p.value == 1 ? "1 Stunde" : "\(Format.number(p.value, decimals: p.decimals)) Stunden"
    }

    static func trips(_ count: Int) -> String { count == 1 ? "1 Fahrt" : "\(Format.number(Double(count))) Fahrten" }

    // MARK: Car

    struct Verdict {
        var title: String
        var detail: String
        var symbol: String
        /// Positive: the trains were faster. Never used to say „gespart“ for a longer ride.
        var isGain: Bool
    }

    /// The line under „Im Auto wärst du … selbst gefahren“. Longer rides are „Mehrzeit“, never „Zeit gespart“.
    static func verdict(_ verdict: TimeBalanceCarVerdict) -> Verdict? {
        switch verdict {
        case .unavailable:
            return nil
        case .transitLonger(let extra):
            return Verdict(title: "Mehrzeit im Öffi: +\(short(extra))",
                           detail: "Dafür Zeit zum Lesen, Arbeiten oder Entspannen – statt selbst am Steuer.",
                           symbol: "book.pages", isGain: false)
        case .aboutEqual:
            return Verdict(title: "Etwa so lang wie mit dem Auto",
                           detail: "Nur ohne selbst zu fahren: die Zeit gehört dir.", symbol: "equal.circle", isGain: false)
        case .transitShorter(let gained):
            return Verdict(title: "Zeit gewonnen: \(short(gained))",
                           detail: "Schneller als mit dem Auto – und du musstest nicht selbst fahren.", symbol: "hare", isGain: true)
        }
    }

    static func carSentence(_ minutes: Double) -> String { "Im Auto wärst du \(short(minutes)) selbst gefahren" }

    // MARK: Delays

    static func delayTitle(_ delays: TimeBalanceDelays) -> String {
        delays.totalMinutes > 0 ? "Verspätungen: \(short(delays.totalMinutes)) verloren" : "Keine Verspätung erfasst"
    }

    static func delayDetail(_ delays: TimeBalanceDelays, tripCount: Int) -> String {
        var text = "Nur Fahrten mit erfasster Verspätung: \(Format.number(Double(delays.recordedTrips))) von \(trips(tripCount))"
        if delays.delayedTrips > 0 {
            text += ", davon \(Format.number(Double(delays.delayedTrips))) verspätet"
            if delays.longestMinutes > 0 { text += " (höchstens \(clock(Double(delays.longestMinutes))))" }
        } else {
            text += ", alle pünktlich"
        }
        return text + "."
    }

    // MARK: Sources

    static func sourceName(_ source: TravelTimeSource) -> String {
        switch source {
        case .entered: "Eingetragen"
        case .timetable: "Abfahrt & Ankunft"
        case .estimated: "Geschätzt"
        }
    }

    // MARK: Whole screen

    /// One spoken sentence for the hero.
    static func heroSpoken(_ balance: TimeBalance) -> String {
        var text = "\(spoken(balance.totalMinutes)) in Bahn und Bus unterwegs, \(trips(balance.tripCount))"
        if balance.recordedMinutes > 0 {
            text += ". Davon \(spoken(balance.recordedMinutes)) erfasst, \(spoken(balance.estimatedMinutes)) geschätzt"
        } else {
            text += ". Alles geschätzt, weil keine Fahrt eine Dauer hat"
        }
        return text + "."
    }
}
