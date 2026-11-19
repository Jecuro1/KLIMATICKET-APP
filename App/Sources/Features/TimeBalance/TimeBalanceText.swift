import Foundation
import KlimaCore

/// Durations and sentences of the „Zeitbilanz“ (de-AT, du-Form). Every number goes through `Format.number`.
enum TimeBalanceText {
    // MARK: Durations

    /// Between a number and its unit, so the two never part at a line break („79 Fahrten“, „2,3 Std.“ at AX5).
    static let nb = "\u{00A0}"

    /// The hero's number and unit: "45" "Min." · "4,5" "Std." · "128" "Std."
    struct Parts: Equatable {
        var value: Double
        var decimals: Int
        var unit: String
    }

    static func parts(_ minutes: Double) -> Parts {
        let figure = TimeBalanceFigure(minutes: minutes)   // KlimaCore: the rounding every figure of the screen shares
        return Parts(value: figure.value, decimals: figure.decimals, unit: figure.unit == .minutes ? "Min." : "Std.")
    }

    /// "45 Min." · "4,5 Std." · "128 Std." – sums.
    static func short(_ minutes: Double) -> String {
        let p = parts(minutes)
        return "\(Format.number(p.value, decimals: p.decimals))\(nb)\(p.unit)"
    }

    /// The hero's legend in the hero's precision (`TimeBalanceRounding.split` over the three sources, largest remainder):
    /// „eingetragen“ + „Abfahrt & Ankunft“ = „erfasst“, „erfasst“ + „geschätzt“ = the big number. Under „72 Std.“ never
    /// „8,4 Std.“ + „64 Std.“, and never „17 Std.“ + „9,6 Std.“ under an „erfasst“ of 26.
    struct Legend {
        var recorded: String
        var estimated: String
        var entered: String
        var timetable: String
        var recordedSpoken: String
        var estimatedSpoken: String
    }

    static func legend(_ balance: TimeBalance) -> Legend {
        let raw = [balance.enteredMinutes, balance.timetableMinutes, balance.estimatedMinutes]
        let shown = TimeBalanceRounding.split(raw)
        let step = TimeBalanceFigure.stepMinutes(ofShown: TimeBalanceFigure(minutes: raw.reduce(0, +)).shownMinutes)
        let recordedRaw = raw[0] + raw[1], recordedShown = shown[0] + shown[1]
        return Legend(recorded: partShort(recordedRaw, shown: recordedShown, step: step),
                      estimated: partShort(raw[2], shown: shown[2], step: step),
                      entered: partShort(raw[0], shown: shown[0], step: step),
                      timetable: partShort(raw[1], shown: shown[1], step: step),
                      recordedSpoken: partSpoken(recordedRaw, shown: recordedShown, step: step),
                      estimatedSpoken: partSpoken(raw[2], shown: shown[2], step: step))
    }

    /// A part in the sum's unit and precision: under „72 Std.“ whole hours („8 Std.“), under „2,1 Std.“ tenths („0,8 Std.“ –
    /// never „48 Min.“, which would look exact), under „45 Min.“ minutes. A part above 0 that got no step: „< 1 Std.“,
    /// „< 0,1 Std.“, „< 1 Min.“.
    private static func partShort(_ raw: Double, shown: Double, step: Double) -> String {
        let hours = step == 1 ? nil : shown / 60
        if shown <= 0, raw > 0 {
            switch step {
            case 60: return "<\(nb)1\(nb)Std."
            case 6: return "<\(nb)\(Format.number(0.1, decimals: 1))\(nb)Std."
            default: return "<\(nb)1\(nb)Min."
            }
        }
        guard let hours else { return short(shown) }
        return "\(Format.number(hours, decimals: tenthsDecimals(hours)))\(nb)Std."
    }

    private static func partSpoken(_ raw: Double, shown: Double, step: Double) -> String {
        if shown <= 0, raw > 0 {
            switch step {
            case 60: return "weniger als 1 Stunde"
            case 6: return "weniger als 6 Minuten"
            default: return "weniger als 1 Minute"
            }
        }
        guard step != 1 else { return spoken(shown) }
        let hours = shown / 60
        return hours == 1 ? "1 Stunde" : "\(Format.number(hours, decimals: tenthsDecimals(hours))) Stunden"
    }

    /// 1 for a tenth of an hour that is not whole („0,8“), 0 otherwise („8“).
    private static func tenthsDecimals(_ hours: Double) -> Int {
        let tenths = (hours * 10).rounded()
        return tenths.truncatingRemainder(dividingBy: 10) == 0 ? 0 : 1
    }

    /// "37 %" / "63 %" that add up to 100 % (a part above 0 never shows as 0 % or 100 %).
    static func splitPercent(_ firstShare: Double) -> (String, String) {
        let share = min(max(firstShare.isFinite ? firstShare : 0, 0), 1)
        var first = Int((share * 100).rounded())
        if share > 0, share < 1 { first = min(99, max(1, first)) }
        return ("\(first)\(nb)%", "\(100 - first)\(nb)%")
    }

    /// A mode's share: "< 1 %" instead of "0 %" for a little time.
    static func share(_ fraction: Double) -> String {
        fraction > 0 && (fraction * 100).rounded() < 1 ? "<\(nb)1\(nb)%" : Format.percent(fraction)
    }

    /// "1 Std. 15 Min." · "45 Min." · "3 Std." – one trip.
    static func clock(_ minutes: Double) -> String {
        let total = Int(max(0, minutes.isFinite ? minutes : 0).rounded())
        let hours = total / 60, rest = total % 60
        if hours == 0 { return "\(rest)\(nb)Min." }
        if rest == 0 { return "\(Format.number(Double(hours)))\(nb)Std." }
        return "\(Format.number(Double(hours)))\(nb)Std. \(rest)\(nb)Min."
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

    static func trips(_ count: Int) -> String { count == 1 ? "1\(nb)Fahrt" : "\(Format.number(Double(count)))\(nb)Fahrten" }

    /// What the weekly average is taken over: „in der ersten Woche“ · „über 11 Tage“ · „über 31 Wochen“ (never „über 1 Wochen“).
    static func averageSpan(weeksElapsed weeks: Double) -> String {
        let days = Int((max(0, weeks.isFinite ? weeks : 0) * 7).rounded())
        if days <= 7 { return "in der ersten Woche" }
        if days < 21 { return "über \(days)\(nb)Tage" }
        return "über \(Format.number((Double(days) / 7).rounded(.down)))\(nb)Wochen"
    }

    // MARK: Car

    struct Verdict {
        var title: String
        var detail: String
        var symbol: String
        /// Positive: the trains were faster. Never used to say „gespart“ for a longer ride.
        var isGain: Bool
    }

    /// The line under „Im Auto wärst du … selbst gefahren“. Longer rides are „Mehrzeit“, never „Zeit gespart“. The gap is
    /// the difference of the two figures on the card (79 Std. − 72 Std. = „7 Std.“, not the unrounded 7,3).
    static func verdict(_ balance: TimeBalance) -> Verdict? {
        let gap = TimeBalanceRounding.shownGap(balance.totalMinutes, balance.carMinutes)
        switch balance.carVerdict {
        case .unavailable:
            return nil
        case .transitLonger:
            return Verdict(title: "Mehrzeit im Öffi: +\(short(gap))",
                           detail: "Dafür Zeit zum Lesen, Arbeiten oder Entspannen – statt selbst am Steuer.",
                           symbol: "book.pages", isGain: false)
        case .aboutEqual:
            return Verdict(title: "Etwa so lang wie mit dem Auto",
                           detail: "Nur ohne selbst zu fahren: die Zeit gehört dir.", symbol: "equal.circle", isGain: false)
        case .transitShorter:
            return Verdict(title: "Zeit gewonnen: \(short(gap))",
                           detail: "Schneller als mit dem Auto – und du musstest nicht selbst fahren.", symbol: "hare", isGain: true)
        }
    }

    static func carSentence(_ minutes: Double) -> String { "Im Auto wärst du \(short(minutes)) selbst gefahren" }

    // MARK: Delays

    static func delayTitle(_ delays: TimeBalanceDelays) -> String {
        // Recorded and all on time: say so – „keine erfasst“ would read as if nothing had been recorded.
        delays.totalMinutes > 0 ? "Verspätungen: \(short(delays.totalMinutes)) verloren" : "Pünktlich: keine Zeit verloren"
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
            let parts = legend(balance)
            text += ". Davon \(parts.recordedSpoken) erfasst, \(parts.estimatedSpoken) geschätzt"
        } else {
            text += ". Alles geschätzt, weil keine Fahrt eine Dauer hat"
        }
        return text + "."
    }
}
