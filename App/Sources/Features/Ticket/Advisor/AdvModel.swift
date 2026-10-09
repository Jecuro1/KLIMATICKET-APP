import SwiftUI
import KlimaCore

// MARK: - Building the advice

/// Bridges the SwiftData entities to the pure `TicketAdvisor` (KlimaCore).
@MainActor
enum AdvAdvisor {
    static func ticket(_ ticket: TicketEntity) -> AdvisorTicket {
        AdvisorTicket(productID: ticket.productID, name: ticket.name, family: ticket.family, variant: ticket.variant,
                      states: ticket.states, price: ticket.price, start: ticket.startDate, end: ticket.endDate,
                      isMonthlyPayment: ticket.isMonthlyPayment, autoRenews: ticket.autoRenews,
                      employerContribution: ticket.employerContribution, addOnPrice: ticket.addOnPrice, addOns: ticket.addOns)
    }

    /// All advisor sections for `ticket`, priced with the app's fare estimator (1st vs. 2nd class per relation).
    static func advice(for ticket: TicketEntity, trips: [TripEntity], app: AppState, now: Date = Date()) -> TicketAdvice {
        let period = ticket.period
        let estimator = app.estimator
        let stations = app.stations
        let inPeriod = trips.filter { $0.deletedAt == nil && period.contains($0.date) }
        let advisorTrips = inPeriod.map { trip in
            AdvisorTrip.make(trip.record, travelClass: trip.travelClass, estimator: estimator, stations: stations)
        }
        return TicketAdvisor.advise(ticket: Self.ticket(ticket), trips: advisorTrips, catalog: app.catalog, now: now)
    }
}

// MARK: - Sections

enum AdvSection: String, CaseIterable, Hashable, Identifiable {
    case renewal, cancellation, firstClass, family, jobticket

    var id: String { rawValue }

    var title: String {
        switch self {
        case .renewal: "Verlängern"
        case .cancellation: "Kündigen"
        case .firstClass: "1. Klasse"
        case .family: "Familie"
        case .jobticket: "Jobticket"
        }
    }

    var symbol: String {
        switch self {
        case .renewal: "arrow.triangle.2.circlepath"
        case .cancellation: "xmark.seal.fill"
        case .firstClass: "sofa.fill"
        case .family: "figure.2.and.child.holdinghands"
        case .jobticket: "briefcase.fill"
        }
    }

    var color: Color {
        switch self {
        case .renewal: Theme.glacier
        case .cancellation: Theme.dawn
        case .firstClass: Theme.dusk
        case .family: Theme.pine
        case .jobticket: Theme.gold
        }
    }
}

/// Meaning of a verdict – drives colour and symbol (colour is never the only carrier: text + symbol always).
enum AdvTone: Hashable {
    case positive, caution, neutral

    var textColor: Color {
        switch self {
        case .positive: Theme.positiveText
        case .caution: Theme.summitText
        case .neutral: Theme.textSecondary
        }
    }

    var fill: Color {
        switch self {
        case .positive: Theme.positive.opacity(0.15)
        case .caution: Theme.summit.opacity(0.16)
        case .neutral: Theme.surfaceSecondary
        }
    }

    var symbol: String {
        switch self {
        case .positive: "checkmark.circle.fill"
        case .caution: "exclamationmark.circle.fill"
        case .neutral: "info.circle.fill"
        }
    }
}

/// One line of „Auf einen Blick“.
struct AdvGlance: Identifiable, Hashable {
    var section: AdvSection
    var verdict: String
    var detail: String
    var value: String?
    var tone: AdvTone
    var id: AdvSection { section }
}

// MARK: - Copy

/// German copy for the Ratgeber (Du-Form, de-AT amounts).
enum AdvText {
    /// "+ € 640" / "– € 120" (whole euros).
    static func signed(_ value: Double) -> String {
        let rounded = value.rounded()
        return rounded >= 0 ? "+ \(Format.euro(rounded, decimals: 0))" : "– \(Format.euro(-rounded, decimals: 0))"
    }

    static func euro(_ value: Double) -> String { Format.euro(value.rounded(), decimals: 0) }

    /// "€ 349,98" – cents for refunds and fees (they are exact amounts).
    static func cents(_ value: Double) -> String { Format.euroPrecise(value) }

    static func trips(_ n: Int) -> String { n == 1 ? "1 Fahrt" : "\(Format.number(Double(n))) Fahrten" }

    static func months(_ n: Int) -> String { n == 1 ? "1 Monat" : "\(n) Monate" }

    static func longDate(_ date: Date) -> String { Format.date(date, .long) }

    /// "in 23 Tagen" / "morgen" / "heute".
    static func countdown(to date: Date, now: Date = Date()) -> String {
        let cal = Calendar.vienna
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<1: return "heute"
        case 1: return "morgen"
        default: return "in \(days) Tagen"
        }
    }

    // MARK: Renewal

    static func renewalTitle(_ r: RenewalAdvice) -> String {
        if r.isExpired {
            switch r.verdict {
            case .renew: return "Ein neues Ticket lohnt sich"
            case .close: return "Ein neues Ticket wäre knapp"
            case .reconsider: return "Ein neues Ticket eher nicht"
            case .tooEarly: return "Zu wenige Fahrten für eine Empfehlung"
            }
        }
        switch r.verdict {
        case .renew: return "Verlängern lohnt sich"
        case .close: return "Knapp – ein paar Fahrten entscheiden"
        case .reconsider: return "Bei deinem Tempo eher nicht"
        case .tooEarly: return "Noch zu früh für eine Empfehlung"
        }
    }

    static func renewalTone(_ r: RenewalAdvice) -> AdvTone {
        switch r.verdict {
        case .renew: .positive
        case .close, .reconsider: .caution
        case .tooEarly: .neutral
        }
    }

    // MARK: Cancellation

    static func cancellationTitle(_ c: CancellationAdvice) -> String {
        switch c.verdict {
        case .beforeStart: return "Vor dem Start gebührenfrei zurückgeben"
        case .notYet: return "Kündbar ab \(Format.date(c.possibleFrom, .long))"
        case .keep: return "Behalten lohnt sich"
        case .consider: return "Kündigen kann sich lohnen"
        case .notWorthwhile: return "Kündigen bringt jetzt nichts mehr"
        case .expired: return "Dein Ticket ist abgelaufen"
        case .unsupported: return "Bedingungen deines Verbunds"
        }
    }

    static func cancellationTone(_ c: CancellationAdvice) -> AdvTone {
        switch c.verdict {
        case .keep: .positive
        case .consider: .caution
        default: .neutral
        }
    }

    // MARK: First class

    static func firstClassTitle(_ f: FirstClassAdvice) -> String {
        switch f.verdict {
        case .paidOff: "Dein Upgrade hat sich gelohnt"
        case .notPaidOff: "Dein Upgrade ist noch nicht drin"
        case .worthIt: "Das Upgrade würde sich lohnen"
        case .notWorthIt: "Für dich lohnt sich das Upgrade nicht"
        case .noTrainTrips: "Noch keine Zugfahrten"
        }
    }

    static func firstClassTone(_ f: FirstClassAdvice) -> AdvTone {
        switch f.verdict {
        case .paidOff, .worthIt: .positive
        case .notPaidOff: .caution
        case .notWorthIt, .noTrainTrips: .neutral
        }
    }

    // MARK: Family

    static func familyTitle(_ f: FamilyAdvice) -> String {
        switch f.verdict {
        case .paidOff: return "Der Familienaufschlag hat sich gelohnt"
        case .onTrack: return "Der Aufschlag holt sich bis Ablauf herein"
        case .notPaidOff: return "Noch \(euro(max(0, f.surcharge - f.childValueSoFar))) bis der Aufschlag drin ist"
        case .worthSwitching: return "KlimaTicket Familie würde sich lohnen"
        case .notWorthSwitching: return "Familie lohnt sich (noch) nicht"
        case .noChildTrips: return "Noch keine Fahrten mit Kindern"
        }
    }

    static func familyTone(_ f: FamilyAdvice) -> AdvTone {
        switch f.verdict {
        case .paidOff, .onTrack, .worthSwitching: .positive
        case .notPaidOff: .caution
        case .notWorthSwitching, .noChildTrips: .neutral
        }
    }
}

// MARK: - At a glance

extension TicketAdvice {
    /// Sections the Ratgeber shows for this ticket, in screen order.
    var advSections: [AdvSection] {
        var result: [AdvSection] = [.renewal]
        if cancellation.verdict != .expired { result.append(.cancellation) }
        if firstClass != nil { result.append(.firstClass) }
        if family != nil { result.append(.family) }
        result.append(.jobticket)
        return result
    }

    /// One summary line per section.
    var advGlances: [AdvGlance] {
        advSections.map { section in
            switch section {
            case .renewal: renewalGlance
            case .cancellation: cancellationGlance
            case .firstClass: firstClassGlance
            case .family: familyGlance
            case .jobticket: jobticketGlance
            }
        }
    }

    private var renewalGlance: AdvGlance {
        let r = renewal
        let value: String? = r.verdict == .tooEarly ? nil : AdvText.signed(r.projectedNextYearNet)
        let detail: String
        switch r.verdict {
        case .tooEarly: detail = "Erfass noch ein paar Wochen deine Fahrten"
        default: detail = "Prognose für \(r.nextYearLabel) zum Preis von \(AdvText.euro(r.nextPrice))"
        }
        return AdvGlance(section: .renewal, verdict: AdvText.renewalTitle(r), detail: detail, value: value,
                         tone: AdvText.renewalTone(r))
    }

    private var cancellationGlance: AdvGlance {
        let c = cancellation
        var value: String?
        var detail: String
        switch c.verdict {
        case .keep, .consider:
            let q = c.endOfMonth
            value = q.map { AdvText.euro(c.isMonthlyPayment ? $0.saving : $0.refund) }
            let lost = q.map { AdvText.euro($0.lostTripValue) } ?? "–"
            detail = c.isMonthlyPayment ? "gespart, Fahrten bis Ablauf ≈ \(lost)" : "zurück, Fahrten bis Ablauf ≈ \(lost)"
        case .notYet:
            detail = "7. Gültigkeitsmonat · \(AdvText.countdown(to: c.possibleFrom))"
            if c.policy == .kennenlern { detail = "Kennenlern-Aktion · \(AdvText.countdown(to: c.possibleFrom))" }
        case .notWorthwhile:
            detail = "Das Kündigungsentgelt frisst die Erstattung auf"
        case .beforeStart:
            detail = "Rückgabe vor dem ersten Gültigkeitstag"
        case .unsupported:
            detail = "Für dein Ticket gelten eigene Regeln"
        case .expired:
            detail = ""
        }
        return AdvGlance(section: .cancellation, verdict: AdvText.cancellationTitle(c), detail: detail, value: value,
                         tone: AdvText.cancellationTone(c))
    }

    private var firstClassGlance: AdvGlance {
        guard let f = firstClass else {
            return AdvGlance(section: .firstClass, verdict: "", detail: "", value: nil, tone: .neutral)
        }
        let detail = f.verdict == .noTrainTrips
            ? "Sobald du Zug fährst, rechnen wir es dir aus"
            : "≈ \(AdvText.euro(f.projectedSurcharge)) Aufpreis vs. \(AdvText.euro(f.upgradePrice)) Upgrade"
        return AdvGlance(section: .firstClass, verdict: AdvText.firstClassTitle(f), detail: detail, value: nil,
                         tone: AdvText.firstClassTone(f))
    }

    private var familyGlance: AdvGlance {
        guard let f = family else {
            return AdvGlance(section: .family, verdict: "", detail: "", value: nil, tone: .neutral)
        }
        let detail = f.isFamilyTicket
            ? "Kinderfahrten \(AdvText.euro(f.childValueSoFar)) vs. Aufschlag \(AdvText.euro(f.surcharge))"
            : "Mitfahrende ≈ \(AdvText.euro(f.projectedChildValue)) vs. Aufschlag \(AdvText.euro(f.surcharge))"
        return AdvGlance(section: .family, verdict: AdvText.familyTitle(f), detail: detail, value: nil, tone: AdvText.familyTone(f))
    }

    private var jobticketGlance: AdvGlance {
        let j = jobticket
        guard j.hasContribution else {
            return AdvGlance(section: .jobticket, verdict: "Zahlt dein Arbeitgeber mit?",
                             detail: "Dann rechnen wir auf deinen Eigenanteil", value: nil, tone: .neutral)
        }
        let verdict = j.isOwnSharePaidOff ? "Für dich schon rentiert" : "Rentiert sich für dich ab \(AdvText.euro(j.ownShare))"
        return AdvGlance(section: .jobticket, verdict: verdict,
                         detail: "Dein Anteil: \(AdvText.euro(j.ownShare)) von \(AdvText.euro(j.fullPrice))",
                         value: nil, tone: j.isOwnSharePaidOff ? .positive : .neutral)
    }
}
