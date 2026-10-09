import Foundation

// MARK: - "Arbeit & Steuer" (Austria)
//
// Rules as checked on 9 Oct 2026 (research/competitors.md §2, data/klimaticket_products.json › oe-jobticket):
// • Jobticket / Arbeitgeberzuschuss: employers may provide or subsidise the KlimaTicket tax-free (§ 26 Z 5 lit. b EStG).
//   The payoff is then measured against the holder's own share (TicketEntity.period).
// • Pendlerpauschale: reduced by the amount the employer paid tax-free for the ticket; the Pendlereuro stays
//   (BMF example: € 2.016 − € 1.000 = € 1.016). Actual travel costs cannot be claimed by employees.
// • Dienstreisen with an own KlimaTicket (AK): per business trip the cost of an equivalent single ticket (2nd class, no
//   Sparschiene) may be claimed – in total at most what the employee paid for the ticket; a tax-free employer contribution
//   lowers that cap (AK example: € 1.400 − € 800 = € 600).
// • Selbständige (WKO, since 2022): 50 % of a non-transferable annual pass as a lump sum (1st class included, family
//   surcharge excluded – it is private). With more than 50 % business use the business share can be claimed instead,
//   documented with an "Öffi-Fahrtenbuch".

/// Employment situation that decides which rules apply.
public enum WorkTaxRole: String, Codable, CaseIterable, Sendable, Identifiable {
    case employee
    case selfEmployed

    public var id: String { rawValue }
    public var displayName: String { self == .employee ? "Angestellt" : "Selbständig" }
}

/// A trip as needed for work & tax purposes.
public struct WorkTaxTrip: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var fromName: String
    public var toName: String
    public var mode: TransportMode
    /// Distance of ONE direction, km.
    public var distanceKm: Double
    public var isRoundTrip: Bool
    /// Equivalent single ticket for ONE direction, 2nd class, EUR.
    public var singleFare: Double
    public var category: TripCategory?
    /// Occasion / note (Reiseanlass).
    public var note: String

    public init(id: UUID = UUID(), date: Date, fromName: String, toName: String, mode: TransportMode, distanceKm: Double,
                isRoundTrip: Bool, singleFare: Double, category: TripCategory?, note: String = "") {
        self.id = id
        self.date = date
        self.fromName = fromName
        self.toName = toName
        self.mode = mode
        self.distanceKm = distanceKm
        self.isRoundTrip = isRoundTrip
        self.singleFare = singleFare
        self.category = category
        self.note = note
    }

    /// Builds the tax view of a logged trip; `singleFare` overrides the logged fare (e.g. 1st class converted to 2nd).
    public init(record: TripRecord, singleFare: Double? = nil, note: String = "") {
        self.init(id: record.id, date: record.date, fromName: record.fromName, toName: record.toName, mode: record.mode,
                  distanceKm: record.distanceKm, isRoundTrip: record.isRoundTrip, singleFare: singleFare ?? record.fareEUR,
                  category: record.category, note: note)
    }

    public var legs: Int { isRoundTrip ? 2 : 1 }
    /// Single tickets for all legs.
    public var totalValue: Double { singleFare * Double(legs) }
    public var totalKm: Double { distanceKm * Double(legs) }
}

/// Business trips of one calendar year with the part of the cap that falls on it (chronological allocation).
public struct WorkTaxYearShare: Hashable, Sendable, Identifiable {
    public var year: Int
    public var tripCount: Int
    public var total: Double
    public var claimable: Double
    public var id: Int { year }
}

/// Dienstreisen of an employee using their own ticket.
public struct WorkTaxBusinessTrips: Hashable, Sendable {
    public var trips: [WorkTaxTrip]
    /// Sum of the equivalent single tickets.
    public var total: Double
    /// What the employee paid themselves (ticket incl. extras − tax-free employer contribution).
    public var cap: Double
    /// min(total, cap).
    public var claimable: Double
    public var totalKm: Double
    public var years: [WorkTaxYearShare]

    public var remainingCap: Double { max(0, cap - total) }
    public var isCapped: Bool { total > cap }
    public var spansSeveralYears: Bool { years.count > 1 }
    /// Share of the cap used (0…1).
    public var capUsage: Double { cap > 0 ? min(1, total / cap) : (total > 0 ? 1 : 0) }
}

/// Jobticket / employer contribution.
public struct WorkTaxJobticket: Hashable, Sendable {
    /// Ticket price incl. extras.
    public var fullPrice: Double
    /// Employer contribution, clamped to the full price.
    public var employerContribution: Double
    public var ownShare: Double
    /// Regular fares of the trips in the period.
    public var tripValue: Double

    public var hasContribution: Bool { employerContribution > 0.004 }
    public var employerFraction: Double { fullPrice > 0 ? employerContribution / fullPrice : 0 }
    /// Payoff against the own share (what KlimaBilanz shows everywhere); nil when the employer pays everything.
    public var amortizationOwnShare: Double? { ownShare > 0.004 ? tripValue / ownShare : nil }
    /// Payoff against the full price, for comparison.
    public var amortizationFullPrice: Double { fullPrice > 0 ? tripValue / fullPrice : 0 }
    /// The Pendlerpauschale is reduced by what the employer paid tax-free for the ticket.
    public var pendlerpauschaleReduction: Double { employerContribution }
}

/// Selbständige: 50 % lump sum vs. "Öffi-Fahrtenbuch".
public struct WorkTaxSelfEmployed: Hashable, Sendable {
    public enum Method: String, Hashable, Sendable {
        case flatRate
        case logbook
    }

    /// Price of the annual pass (without extras).
    public var ticketPrice: Double
    /// ÖBB 1st-class upgrade for the year – part of the lump sum.
    public var firstClassUpgrade: Double
    /// KlimaTicket Familie surcharge – private, never deductible.
    public var familySurcharge: Double
    public var businessKm: Double
    public var privateKm: Double
    public var businessTripCount: Int
    public var tripCount: Int

    /// Deductible basis: ticket + 1st-class upgrade − family surcharge.
    public var basis: Double { max(0, ticketPrice + firstClassUpgrade - min(familySurcharge, ticketPrice)) }
    public var flatRateAmount: Double { basis * WorkTax.flatRateShare }
    public var totalKm: Double { businessKm + privateKm }
    public var businessShare: Double { totalKm > 0 ? businessKm / totalKm : 0 }
    /// The logbook route is only open with more than 50 % business use.
    public var logbookApplies: Bool { businessShare > WorkTax.logbookThreshold }
    /// Business share of the basis (what the logbook would yield).
    public var logbookAmount: Double { basis * businessShare }
    public var recommended: Method { logbookApplies && logbookAmount > flatRateAmount ? .logbook : .flatRate }
    public var recommendedAmount: Double { recommended == .logbook ? logbookAmount : flatRateAmount }
    /// Extra amount of the logbook over the lump sum (0 when it does not apply).
    public var logbookAdvantage: Double { logbookApplies ? max(0, logbookAmount - flatRateAmount) : 0 }
}

public enum WorkTax {
    /// Lump-sum share for self-employed (WKO, since 1 Jan 2022).
    public static let flatRateShare = 0.5
    /// Business use above which the "Öffi-Fahrtenbuch" may be used.
    public static let logbookThreshold = 0.5
    /// Day the rules above were last checked against AK, BMF and WKO.
    public static let rulesCheckedISODate = "2026-10-09"

    public static func rulesCheckedDate(calendar: Calendar = .vienna) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 12)) ?? Date(timeIntervalSince1970: 1_791_540_000)
    }

    /// AK: business trips are valued with the 2nd-class single ticket – a logged 1st-class fare is converted back.
    public static func secondClassFare(_ fare: Double, travelClass: TravelClass, firstClassFactor: Double) -> Double {
        guard travelClass == .first, firstClassFactor > 1 else { return max(0, fare) }
        return max(0, fare / firstClassFactor)
    }

    /// Whether a trip counts as business use. Employees: Dienstreisen only. Self-employed: Dienstreisen and – if
    /// `countsCommute` – the way to the business premises.
    public static func isBusinessUse(_ category: TripCategory?, role: WorkTaxRole, countsCommute: Bool = true) -> Bool {
        switch category {
        case .business: true
        case .commute: role == .selfEmployed && countsCommute
        default: false
        }
    }

    /// Dienstreisen (category `.business`) valued with single tickets and capped at the own share. When the ticket year
    /// spans two calendar years, the cap is allocated chronologically (first year first).
    public static func businessTrips(_ trips: [WorkTaxTrip], cap: Double, calendar: Calendar = .vienna) -> WorkTaxBusinessTrips {
        let business = trips.filter { $0.category == .business }.sorted { $0.date < $1.date }
        let total = business.reduce(0) { $0 + $1.totalValue }
        let cap = max(0, cap)
        var years: [WorkTaxYearShare] = []
        var remaining = cap
        let grouped = Dictionary(grouping: business) { calendar.component(.year, from: $0.date) }
        for year in grouped.keys.sorted() {
            let items = grouped[year] ?? []
            let sum = items.reduce(0) { $0 + $1.totalValue }
            let claim = min(sum, remaining)
            remaining -= claim
            years.append(WorkTaxYearShare(year: year, tripCount: items.count, total: sum, claimable: claim))
        }
        return WorkTaxBusinessTrips(trips: business, total: total, cap: cap, claimable: min(total, cap),
                                    totalKm: business.reduce(0) { $0 + $1.totalKm }, years: years)
    }

    /// Own share vs. employer contribution and the two payoff views.
    public static func jobticket(price: Double, addOnPrice: Double = 0, employerContribution: Double, tripValue: Double) -> WorkTaxJobticket {
        let full = max(0, price) + max(0, addOnPrice)
        let employer = min(max(0, employerContribution), full)
        return WorkTaxJobticket(fullPrice: full, employerContribution: employer, ownShare: full - employer, tripValue: max(0, tripValue))
    }

    /// Lump sum vs. logbook for self-employed. `trips` should be all trips of the ticket period.
    public static func selfEmployed(ticketPrice: Double, firstClassUpgrade: Double = 0, familySurcharge: Double = 0,
                                    trips: [WorkTaxTrip], countsCommute: Bool = true) -> WorkTaxSelfEmployed {
        var businessKm = 0.0, privateKm = 0.0, businessCount = 0
        for trip in trips {
            if isBusinessUse(trip.category, role: .selfEmployed, countsCommute: countsCommute) {
                businessKm += trip.totalKm
                businessCount += 1
            } else {
                privateKm += trip.totalKm
            }
        }
        return WorkTaxSelfEmployed(ticketPrice: max(0, ticketPrice), firstClassUpgrade: max(0, firstClassUpgrade),
                                   familySurcharge: max(0, familySurcharge), businessKm: businessKm, privateKm: privateKm,
                                   businessTripCount: businessCount, tripCount: trips.count)
    }

    /// KlimaTicket Familie surcharge for a ticket starting on `start` = family price − price of the matching base product
    /// (e.g. "oe-familie-klassik" − "oe-klassik" = € 140 for tickets from 1 Jan 2026). 0 for non-family or unknown products.
    public static func familySurcharge(productID: String, start: Date, products: [TicketProduct], calendar: Calendar = .vienna) -> Double {
        guard let family = products.first(where: { $0.id == productID }), family.variant == .familie,
              let base = products.first(where: { $0.id == baseProductID(forFamilyProductID: productID) }) else { return 0 }
        return max(0, family.price(forStart: start, calendar: calendar) - base.price(forStart: start, calendar: calendar))
    }

    /// "oe-familie-klassik" → "oe-klassik", "oe-familie-ermaessigt" → "oe-jugend", "ktn-senior-familie" → "ktn-senior".
    static func baseProductID(forFamilyProductID id: String) -> String {
        var parts = id.split(separator: "-").map(String.init).filter { $0 != "familie" }
        if let index = parts.firstIndex(of: "ermaessigt") { parts[index] = "jugend" }
        return parts.joined(separator: "-")
    }
}

// MARK: - Export (CSV for Excel AT: semicolon, decimal comma, UTF-8 BOM)

public enum WorkTaxExport {
    /// "Dienstreise-Nachweis": one row per business trip, then the totals block.
    public static func businessTripsCSV(_ summary: WorkTaxBusinessTrips, holder: String, ticketName: String,
                                        calendar: Calendar = .vienna) -> String {
        let header = ["Datum", "Von", "Nach", "Verkehrsmittel", "Hin & Retour", "Distanz (km)",
                      "Einzelfahrschein 2. Kl. je Richtung (€)", "Wert (€)", "Anlass / Notiz"]
        var lines = [row(header)]
        for trip in summary.trips {
            lines.append(row([day(trip.date, calendar), trip.fromName, trip.toName, trip.mode.displayName,
                              trip.isRoundTrip ? "ja" : "nein", CSVExport.decimal(trip.totalKm, 1),
                              CSVExport.decimal(trip.singleFare, 2), CSVExport.decimal(trip.totalValue, 2), trip.note]))
        }
        lines.append("")
        lines.append(totalRow("Summe Einzelfahrscheine (\(summary.trips.count) Dienstreisen)", summary.total))
        lines.append(totalRow("Obergrenze: selbst bezahlter Ticketpreis", summary.cap))
        lines.append(totalRow("Absetzbar", summary.claimable))
        if summary.spansSeveralYears {
            for year in summary.years {
                lines.append(totalRow("davon Kalenderjahr \(year.year)", year.claimable))
            }
        }
        lines.append("")
        var meta = [ticketName]
        if !holder.isEmpty { meta.insert(holder, at: 0) }
        lines.append(row(["Dienstreise-Nachweis · " + meta.joined(separator: " · ")]))
        lines.append(row([disclaimer(calendar: calendar)]))
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    /// "Öffi-Fahrtenbuch" for self-employed: all trips with purpose (betrieblich/privat) and the business share.
    public static func logbookCSV(trips: [WorkTaxTrip], summary: WorkTaxSelfEmployed, countsCommute: Bool,
                                  holder: String, ticketName: String, calendar: Calendar = .vienna) -> String {
        let header = ["Datum", "Uhrzeit", "Von", "Nach", "Verkehrsmittel", "Hin & Retour", "Distanz (km)",
                      "Zweck", "Kategorie", "Normalpreis (€)", "Anlass / Notiz"]
        var lines = [row(header)]
        for trip in trips.sorted(by: { $0.date < $1.date }) {
            let business = WorkTax.isBusinessUse(trip.category, role: .selfEmployed, countsCommute: countsCommute)
            lines.append(row([day(trip.date, calendar), time(trip.date, calendar), trip.fromName, trip.toName, trip.mode.displayName,
                              trip.isRoundTrip ? "ja" : "nein", CSVExport.decimal(trip.totalKm, 1),
                              business ? "betrieblich" : "privat", trip.category?.displayName ?? "",
                              CSVExport.decimal(trip.totalValue, 2), trip.note]))
        }
        lines.append("")
        lines.append(row(["Betriebliche km", "", "", "", "", "", CSVExport.decimal(summary.businessKm, 1)]))
        lines.append(row(["Private km", "", "", "", "", "", CSVExport.decimal(summary.privateKm, 1)]))
        lines.append(row(["Betrieblicher Anteil (%)", "", "", "", "", "", CSVExport.decimal(summary.businessShare * 100, 1)]))
        lines.append(row(["Basis: Ticketpreis + 1.-Klasse-Upgrade − Familienaufschlag (€)", "", "", "", "", "", "", "", "",
                          CSVExport.decimal(summary.basis, 2)]))
        lines.append(row(["50-%-Pauschale (€)", "", "", "", "", "", "", "", "", CSVExport.decimal(summary.flatRateAmount, 2)]))
        lines.append(row(["Betrieblicher Anteil laut Fahrtenbuch (€)" + (summary.logbookApplies ? "" : " – erst ab mehr als 50 %"),
                          "", "", "", "", "", "", "", "", CSVExport.decimal(summary.logbookAmount, 2)]))
        lines.append("")
        var meta = [ticketName]
        if !holder.isEmpty { meta.insert(holder, at: 0) }
        lines.append(row(["Öffi-Fahrtenbuch · " + meta.joined(separator: " · ")]))
        lines.append(row([disclaimer(calendar: calendar)]))
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    /// "Keine Steuerberatung – Angaben ohne Gewähr, Stand 09.10.2026"
    public static func disclaimer(calendar: Calendar = .vienna) -> String {
        "Keine Steuerberatung – Angaben ohne Gewähr, Stand \(day(WorkTax.rulesCheckedDate(calendar: calendar), calendar))"
    }

    static func row(_ fields: [String]) -> String { fields.map(CSVExport.escape).joined(separator: ";") }

    static func totalRow(_ label: String, _ value: Double) -> String {
        row([label, "", "", "", "", "", "", CSVExport.decimal(value, 2)])
    }

    static func day(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d.%02d.%04d", c.day ?? 0, c.month ?? 0, c.year ?? 0)
    }

    static func time(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
