import Foundation
import KlimaCore

/// All sentences of „Was wäre wenn?“ in one place: the hero sentence, the delta, the chart summary, the share text. Pure
/// functions of a `WhatIfResult` – numbers only through `Format.*` (de-AT), one-line German in du-Form, neutral wording
/// (a calculation aid, no buying recommendation).
enum WhatIfText {
    // MARK: Numbers

    static func trips(_ count: Int) -> String { count == 1 ? "1 Fahrt" : "\(Format.number(Double(count))) Fahrten" }

    /// "12 Fahrten pro Monat" (whole numbers) or "ca. 8,3 Fahrten pro Monat".
    static func perMonth(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.05 {
            return "\(trips(Int(rounded))) pro Monat"
        }
        return "ca. \(Format.number(value, decimals: 1)) Fahrten pro Monat"
    }

    /// "×1,5"
    static func factor(_ value: Double) -> String {
        let tenths = value * 10
        let decimals = abs(value - value.rounded()) < 0.0001 ? 0 : (abs(tenths - tenths.rounded()) < 0.0001 ? 1 : 2)
        return "×\(Format.number(value, decimals: decimals))"
    }

    /// "das KlimaTicket Ö Klassik" / "die Jahreskarte WIEN" – the product names of the catalogue are mostly neuter.
    static func withArticle(_ name: String) -> String {
        name.hasPrefix("Jahreskarte") ? "die \(name)" : "das \(name)"
    }

    // MARK: Hero

    /// The sentence at the top of the result.
    static func headline(_ result: WhatIfResult, usesHistory: Bool = false) -> String {
        switch result.state {
        case .needsRoutes: return "Wähle eine Strecke"
        case .noTrips: return usesHistory ? "Mit diesen Einstellungen bleibt keine Fahrt übrig" : "Dann lohnt sich kein Ticket"
        case .ready: break
        }
        guard let best = result.bestTicket else { return "Kein KlimaTicket deckt genug deiner Fahrten ab" }
        if result.isTie { return "\(best.name) kostet so viel wie Einzeltickets" }
        let name = withArticle(best.name)
        let breakEven = result.breakEvenTripsPerMonth
        if result.ticketIsCheaper {
            guard let breakEven else { return "\(name.prefix(1).uppercased())\(name.dropFirst()) ist günstiger als Einzeltickets" }
            return "Ab \(trips(breakEven)) pro Monat lohnt sich \(name)"
        }
        guard let breakEven else { return "Einzeltickets sind günstiger" }
        return "Einzeltickets sind günstiger – \(name) lohnt sich ab \(trips(breakEven)) pro Monat"
    }

    /// The one sentence under the hero: what the volume is.
    static func volumeLine(_ result: WhatIfResult, usesHistory: Bool) -> String {
        switch result.state {
        case .needsRoutes: return "Wähle Start und Ziel, dann rechnen wir los."
        case .noTrips:
            return usesHistory ? "Schalte einen Filter aus, dann rechnen wir wieder mit deinen Fahrten."
                : "Ohne Fahrten fallen keine Fahrtkosten an, ein Ticket kostet trotzdem."
        case .ready:
            let base = usesHistory ? "Bei deinen Fahrten" : "Bei deinen Annahmen"
            return "\(base): \(perMonth(result.tripsPerMonth))"
        }
    }

    /// "€ 312 weniger im Jahr" / "kostet € 85 mehr im Jahr" split into its words and the amount (the amount is set large),
    /// plus what it is compared with.
    struct Delta {
        var prefix: String
        var amount: String
        var suffix: String
        /// "als mit Einzeltickets" – the second line under the amount.
        var caption: String
        var isSaving: Bool
        /// The same as one sentence (VoiceOver, share text).
        var sentence: String
        /// Without the comparison ("€ 312 weniger im Jahr"): the line under a saved scenario.
        var shortSentence: String
    }

    /// A difference below this many euros a year is not worth a big number.
    static let negligibleDelta = 10.0

    static func delta(_ result: WhatIfResult) -> Delta? {
        guard result.state == .ready, result.bestTicket != nil else { return nil }
        let rounded = abs(result.yearlyDelta).rounded()
        let amount = Format.euro(rounded, decimals: 0)
        if result.isTie || rounded < 1 {
            return Delta(prefix: "", amount: "", suffix: "kein Unterschied", caption: "zu Einzeltickets", isSaving: true,
                         sentence: "kein Unterschied zu Einzeltickets", shortSentence: "kein Unterschied")
        }
        let direction = result.ticketIsCheaper ? "weniger" : "mehr"
        if rounded < negligibleDelta {
            return Delta(prefix: "", amount: "", suffix: "kaum ein Unterschied",
                         caption: "\(amount) \(direction) im Jahr als mit Einzeltickets", isSaving: result.ticketIsCheaper,
                         sentence: "kaum ein Unterschied: \(amount) \(direction) im Jahr als mit Einzeltickets",
                         shortSentence: "kaum ein Unterschied")
        }
        if result.ticketIsCheaper {
            return Delta(prefix: "", amount: amount, suffix: "weniger im Jahr", caption: "als mit Einzeltickets", isSaving: true,
                         sentence: "\(amount) weniger im Jahr als mit Einzeltickets", shortSentence: "\(amount) weniger im Jahr")
        }
        return Delta(prefix: "kostet", amount: amount, suffix: "mehr im Jahr", caption: "als Einzeltickets", isSaving: false,
                     sentence: "kostet \(amount) mehr im Jahr als Einzeltickets", shortSentence: "kostet \(amount) mehr im Jahr")
    }

    // MARK: Chart

    /// "Nach 2,5 Monaten" – where the lines cross.
    static func crossingText(_ crossing: Double) -> String {
        crossing < 1 ? "im 1. Monat" : "nach \(Format.number(crossing, decimals: 1)) Monaten"
    }

    /// "Nach 2,5 Monaten" as the label of the flag.
    static func crossingTitle(_ crossing: Double) -> String {
        let text = crossingText(crossing)
        return String(text.prefix(1)).uppercased() + String(text.dropFirst())
    }

    /// Text summary of the chart (visible under it, and the summary of its audio graph).
    static func chartSummary(_ result: WhatIfResult) -> String {
        guard result.state == .ready else { return "Ohne Fahrten entstehen keine Kosten." }
        let single = Format.euro(result.single.yearlyCost.rounded(), decimals: 0)
        guard let best = result.bestTicket else { return "Nach 12 Monaten kosten Einzeltickets \(single)." }
        let ticket = Format.euro(best.yearlyCost.rounded(), decimals: 0)
        var text = "Nach 12 Monaten: Einzeltickets \(single), \(best.name) \(ticket)."
        if let crossing = result.crossing {
            text += " Die Linien kreuzen sich \(crossingText(crossing))."
        } else if result.ticketIsCheaper == false {
            text += " Die Linien kreuzen sich innerhalb eines Jahres nicht."
        }
        return text
    }

    // MARK: Ranking

    /// The detail line under an option of the ranking.
    static func detail(_ option: WhatIfOption, result: WhatIfResult) -> String {
        if option.isSingle { return "Normalpreis aller Fahrten · \(perMonth(result.tripsPerMonth))" }
        let ticket = Format.euro(option.ticketPrice - option.upgradePrice, decimals: 0)
        var parts: [String] = ["\(ticket) Ticket"]
        if option.upgradePrice > 0 { parts.append("\(Format.euro(option.upgradePrice, decimals: 0)) 1.-Klasse-Upgrade") }
        let uncovered = Format.euro(option.uncoveredYearly.rounded(), decimals: 0)
        let joined = parts.joined(separator: " + ")
        if option.coveredShare >= 0.9995 { return "\(joined) · deckt alle Fahrten ab" }
        if option.coveredShare <= 0.0005 { return "\(joined) · deckt keine deiner Fahrten ab" }
        let share = Format.percent(1 - option.coveredShare)
        return "\(joined) + \(uncovered) für \(share) der Fahrten außerhalb"
    }

    // MARK: Scenarios

    /// "KlimaTicket Tirol · € 312 weniger im Jahr als mit Einzeltickets" – the line under a saved scenario.
    static func scenarioHeadline(_ result: WhatIfResult) -> String {
        guard result.state == .ready else { return headline(result) }
        var parts: [String] = []
        if let best = result.bestTicket { parts.append(best.name) }
        if let delta = delta(result) { parts.append(delta.shortSentence) }
        return parts.isEmpty ? headline(result) : parts.joined(separator: " · ")
    }

    // MARK: Share

    /// Plain text for the share sheet. Numbers only, no link, no purchase hint.
    static func share(_ result: WhatIfResult, title: String, usesHistory: Bool) -> String {
        var lines = ["KlimaBilanz · Was wäre wenn?", title]
        lines.append(headline(result, usesHistory: usesHistory))
        if let delta = delta(result) { lines.append(delta.sentence) }
        if result.state == .ready {
            lines.append("Pro Jahr: Einzeltickets \(Format.euro(result.single.yearlyCost.rounded(), decimals: 0))"
                         + (result.bestTicket.map { ", \($0.name) \(Format.euro($0.yearlyCost.rounded(), decimals: 0))" } ?? ""))
            lines.append(usesHistory ? "Grundlage: meine Fahrten der letzten 12 Monate" : "Grundlage: meine Annahmen (\(perMonth(result.tripsPerMonth)))")
        }
        lines.append("Rechenhilfe, keine Beratung · Tarifstand \(tariffDate(result.tariffDate))")
        return lines.joined(separator: "\n")
    }

    // MARK: Footnote

    /// "9. Okt. 2026" from the catalogue's ISO date ("2026-10-09"); the raw text when it is not an ISO date.
    static func tariffDate(_ iso: String) -> String {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]) else { return iso }
        return "\(parts[2]). \(StatsNames.monthShort[parts[1] - 1]). \(parts[0])"
    }

    /// The one honest line under the ranking.
    static func footnote(_ result: WhatIfResult) -> String {
        "Rechenhilfe, keine Beratung · Preise: reguläre Einzeltickets (ÖBB-Standardticket, ohne Sparschiene, Vorteilscard oder Aktionen) · Tarifstand \(tariffDate(result.tariffDate))"
    }

    static let explanation = """
    Eine Fahrt ist eine Strecke in eine Richtung: Pendeln hin und zurück sind zwei Fahrten am Tag. \
    Einzeltickets sind mit den offiziellen ÖBB-Relationspreisen gerechnet, wo es die Strecke gibt, sonst mit einem Modell nach Entfernung. \
    Ein KlimaTicket kostet den Preis seines Starttermins und deckt alle Fahrten seines Gebiets ab; Fahrten außerhalb zahlst du zusätzlich. \
    Regionale Tickets gelten nur, wenn Start und Ziel im selben Bundesland liegen. Das Ergebnis ist ein Modell, kein Angebot und keine Beratung – \
    im Ticketshop können die Preise abweichen.
    """
}
