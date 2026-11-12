import Foundation
import KlimaCore

/// German copy and figures of the year story, in one place: the pages, their spoken summaries and the share image all
/// say the same thing the same way. Numbers only through `Format.*` / `SummitFigures` (de-AT, whole euros as on the hero).
enum YearReviewText {
    // MARK: Savings

    /// What the Ersparnis page says in one line.
    enum Verdict: Equatable {
        /// `totalValue ≥ cost`: the whole-euro profit (can be 0 for a dead heat).
        case profit(Double)
        /// The whole-euro rest to the break-even.
        case remaining(Double)
        /// No ticket price in the period: the value is shown, nothing is claimed.
        case valueOnly(Double)
    }

    /// The headline: the value of all trips against the ticket price, rounded like the Übersicht hero and the Jahresbericht
    /// (`SummitFigures`, the same figures as `SavingsSummary.shownProfitEuro` / `shownRemainingEuro`).
    static func verdict(_ savings: YearReview.Savings) -> Verdict {
        guard savings.hasTicketCost else { return .valueOnly(max(0, savings.totalValue.rounded())) }
        if savings.isPaidOff {
            return .profit(SummitFigures.shownProfit(value: savings.totalValue, price: savings.ticketCost))
        }
        return .remaining(SummitFigures.shownRemaining(value: savings.totalValue, price: savings.ticketCost, isPaidOff: false))
    }

    /// "€ 1.050": the value of all trips next to the ticket cost.
    static func valueText(_ savings: YearReview.Savings) -> String { SummitFigures.euro(savings.totalValue) }

    static func costText(_ savings: YearReview.Savings) -> String { SummitFigures.euro(savings.ticketCost) }

    static func verdictLine(_ savings: YearReview.Savings) -> String {
        switch verdict(savings) {
        case .profit(let amount):
            return amount >= 1 ? "Gewinn \(SummitFigures.euro(amount))" : "Punktlandung – das Ticket hat sich bezahlt"
        case .remaining(let amount):
            let target = savings.costIsPartial ? "bis zu den anteiligen Ticketkosten" : "bis zum Break-even"
            return "noch \(SummitFigures.euro(amount)) \(target)"
        case .valueOnly(let value):
            return "Fahrtwert \(SummitFigures.euro(value))"
        }
    }

    /// "Ehrlich gerechnet: Gewinn € 12" / "… noch € 70 bis zum Break-even" – the same balance without the trips you would not have made.
    static func honestOutcome(_ savings: YearReview.Savings) -> String? {
        guard savings.hasTicketCost else { return nil }
        if savings.isHonestlyPaidOff {
            let profit = SummitFigures.shownProfit(value: savings.realValue, price: savings.ticketCost)
            return profit >= 1 ? "Ehrlich gerechnet: Gewinn \(SummitFigures.euro(profit))" : "Ehrlich gerechnet: Punktlandung"
        }
        let rest = SummitFigures.shownRemaining(value: savings.realValue, price: savings.ticketCost, isPaidOff: false)
        let target = savings.costIsPartial ? "bis zu den anteiligen Ticketkosten" : "bis zum Break-even"
        return "Ehrlich gerechnet: noch \(SummitFigures.euro(rest)) \(target)"
    }

    /// The induced trips as their own line: extra value, no saving.
    static func inducedLine(_ savings: YearReview.Savings) -> String {
        let trips = savings.inducedTripCount == 1 ? "einer Fahrt" : "\(savings.inducedTripCount) Fahrten"
        return "\(SummitFigures.euro(savings.extraValue)) Mehrwert aus \(trips), die du ohne Ticket nicht gemacht hättest – das ist kein gespartes Geld."
    }

    // MARK: Distance

    /// "rund 9,0-mal von Bregenz nach Wien" · "mehr als einmal von Wien nach Salzburg" · "40 % der Strecke von Wien nach Graz".
    static func referenceLine(_ reference: ReferenceComparison) -> String {
        let route = "von \(reference.fromLabel) nach \(reference.toLabel)"
        let factor = reference.factor
        if factor >= 1.95 { return "rund \(Format.number(factor, decimals: factor < 10 ? 1 : 0))-mal \(route)" }
        if factor >= 1.15 { return "mehr als einmal \(route)" }
        if factor >= 0.9 { return "etwa einmal \(route)" }
        return "\(Format.number((factor * 100).rounded())) % der Strecke \(route)"
    }

    /// "Luftlinie Bregenz – Wien: 501 km" – the great-circle distance the comparison is based on.
    static func referenceNote(_ reference: ReferenceComparison) -> String {
        "Luftlinie \(reference.fromLabel) – \(reference.toLabel): \(Format.number(reference.referenceKm)) km"
    }

    // MARK: Rhythm

    static func tripsText(_ n: Int) -> String { StatsNames.trips(n) }

    /// "an einem Tag" · "an 76 Tagen".
    static func onDays(_ n: Int) -> String { n == 1 ? "an einem Tag" : "an \(n) Tagen" }

    static func streakText(_ days: Int) -> String { days == 1 ? "1 Tag" : "\(days) Tage" }

    // MARK: Climate

    static func co2Text(_ kg: Double) -> String {
        let parts = StatsCalc.co2Parts(kg)
        return "\(parts.value) \(parts.unit)"
    }

    // MARK: Routes & trips

    static func routeTitle(_ route: RouteStat) -> String { "\(route.fromName) – \(route.toName)" }

    static func tripTitle(_ trip: TripRecord) -> String { "\(trip.fromName) → \(trip.toName)" }

    // MARK: Pages

    /// "Seite 3 von 8".
    static func pageOf(_ number: Int, _ total: Int) -> String { "Seite \(number) von \(total)" }

    static func kicker(for kind: YearReviewPageKind) -> String {
        switch kind {
        case .intro: "Rückblick"
        case .savings: "Ersparnis"
        case .distance: "Strecke"
        case .favoriteRoute: "Lieblingsroute"
        case .rhythm: "Rhythmus"
        case .onTheRoad: "Unterwegs"
        case .purpose: "Wofür"
        case .climate: "Klima"
        case .finale: "Teilen"
        }
    }

    /// The spoken summary of a page ("Seite 3 von 8: Du bist 4.812 Kilometer gefahren"). The visual pages say more, this
    /// is what VoiceOver reads for the whole page.
    static func spoken(_ page: YearReview.Page, review: YearReview, number: Int, total: Int) -> String {
        let prefix = pageOf(number, total) + ": "
        switch page {
        case .intro(let intro):
            var text = "Dein \(review.period.title()): \(StatsNames.trips(intro.tripCount)) \(onDays(intro.travelDays))."
            if let name = intro.ticketName { text += " Ticket: \(name)." }
            return prefix + text
        case .savings(let savings):
            var text = verdictLine(savings).capitalizedFirst + "."
            if savings.hasTicketCost {
                text += " Fahrten im Wert von \(valueText(savings)) gegen \(costText(savings)) Ticketkosten\(savings.costIsPartial ? ", anteilig" : "")."
            }
            if let date = savings.breakEvenDate { text += " Rentiert seit \(Format.dayMonth(date))." }
            if savings.hasInducedTrips {
                if let honest = honestOutcome(savings) { text += " \(honest)." }
                text += " " + inducedLine(savings)
            }
            return prefix + text
        case .distance(let distance):
            var text = "Du bist \(Format.number(distance.km)) Kilometer gefahren."
            if let reference = distance.reference { text += " Das ist \(referenceLine(reference))." }
            return prefix + text
        case .favoriteRoute(let favorite):
            return prefix + "Deine Lieblingsroute ist \(routeTitle(favorite.top)), \(StatsNames.trips(favorite.top.trips))."
        case .rhythm(let rhythm):
            var parts: [String] = []
            if let best = rhythm.bestMonth { parts.append("Dein stärkster Monat war der \(StatsNames.wideMonth(best.month)) mit \(SummitFigures.euro(best.value)).") }
            if let day = rhythm.busiestWeekday { parts.append("Am häufigsten bist du \(StatsNames.wideWeekday(day.weekday)) gefahren.") }
            parts.append("Längste Serie: \(streakText(rhythm.longestStreakDays)).")
            return prefix + parts.joined(separator: " ")
        case .onTheRoad(let road):
            var parts = ["Du warst in \(road.stateCount) von \(YearReview.OnTheRoad.totalStates) Bundesländern."]
            if let trip = road.longestTrip { parts.append("Längste Fahrt: \(tripTitle(trip)), \(Format.km(trip.totalDistanceKm)).") }
            if let trip = road.mostValuableTrip, trip.id != road.longestTrip?.id { parts.append("Wertvollste Fahrt: \(tripTitle(trip)), \(SummitFigures.euro(trip.totalValue)).") }
            return prefix + parts.joined(separator: " ")
        case .purpose(let purpose):
            let top = purpose.buckets.first?.category?.displayName ?? ""
            return prefix + "Wofür du gefahren bist: am häufigsten \(top). \(purpose.categorisedTrips) Fahrten mit Zweck."
        case .climate(let climate):
            return prefix + "Du hast etwa \(co2Text(climate.co2SavedKg)) CO₂ gespart – eine Schätzung im Vergleich zum Auto."
        case .finale:
            return prefix + "Dein Jahr zum Teilen als Bild."
        }
    }
}

extension String {
    /// "gewinn" → "Gewinn" without touching the rest ("noch € 5" stays).
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
