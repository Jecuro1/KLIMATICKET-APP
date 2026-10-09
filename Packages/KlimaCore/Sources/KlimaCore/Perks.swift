import Foundation

// "Vorteilswelt & Fahrgastrechte" – pure logic for the KlimaTicket holder benefits ("Zusatz-Ersparnis") and the
// passenger-rights compensation estimate. Everything here is platform independent and covered by PerksTests.
//
// Sources:
// - Vorteilswelt: https://www.klimaticket.at/eins-fuer-mehr/ (partner list, Stand 9.10.2026) → App/Resources/benefits.json
// - Fahrgastrechte: AGB KlimaTicket Ö (gültig ab 1.1.2026) Pkt. 24; ÖBB-Tarifbestimmungen A.5.4 (KlimaTicket Ö) and A.5.3
//   (Verbund-Jahresnetzkarten); oebb.at/fahrgastrechte ("4,35 € pro Monat ab 01.01.2025"); data/klimaticket_products.json
//   (`rules.oe.passengerRights`).

// MARK: - Catalogue

/// Category of a Vorteilswelt partner – mirrors the sections of klimaticket.at/eins-fuer-mehr.
public enum PerkCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case mobility
    case museums
    case leisure
    case foodStay
    case more
    /// A benefit the user entered without a catalogue partner.
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mobility: "Mobilität"
        case .museums: "Museen"
        case .leisure: "Freizeit"
        case .foodStay: "Essen & Schlafen"
        case .more: "Weitere"
        case .custom: "Eigene"
        }
    }

    public var symbolName: String {
        switch self {
        case .mobility: "bicycle"
        case .museums: "building.columns.fill"
        case .leisure: "figure.hiking"
        case .foodStay: "fork.knife"
        case .more: "sparkles"
        case .custom: "star.fill"
        }
    }

    /// Categories that appear in the bundled catalogue (filter chips).
    public static let catalogCases: [PerkCategory] = [.mobility, .museums, .leisure, .foodStay, .more]
}

/// One partner offer of the KlimaTicket Vorteilswelt.
public struct PerkPartner: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Compact name for chips ("CAT", "Sommer-Bergbahnen"); nil = `name`.
    public var short: String?
    public var category: PerkCategory
    /// The offer in a few words ("−50 % auf das Ticket").
    public var benefit: String
    /// Typical saving per use in EUR – a prefill the user can adjust ("Richtwert").
    public var typicalSavingEUR: Double
    /// "AT" (whole of Austria) or comma separated federal-state codes ("W", "NÖ,B").
    public var region: String
    /// Partner page as linked from klimaticket.at/eins-fuer-mehr.
    public var url: String
    /// How to redeem ("KlimaTicket Ö in der App hinterlegen").
    public var hint: String?
    /// Promo code to enter when booking online.
    public var code: String?
    /// SF Symbol for the partner (falls back to the category symbol).
    public var symbol: String?
    /// Restriction on the ticket type ("Nur mit KlimaTicket Ö Jugend").
    public var ticketNote: String?
    /// Shown as a quick-add suggestion.
    public var featured: Bool

    public init(id: String, name: String, short: String? = nil, category: PerkCategory, benefit: String, typicalSavingEUR: Double,
                region: String, url: String, hint: String? = nil, code: String? = nil, symbol: String? = nil, ticketNote: String? = nil,
                featured: Bool = false) {
        self.id = id
        self.name = name
        self.short = short
        self.category = category
        self.benefit = benefit
        self.typicalSavingEUR = typicalSavingEUR
        self.region = region
        self.url = url
        self.hint = hint
        self.code = code
        self.symbol = symbol
        self.ticketNote = ticketNote
        self.featured = featured
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, short, category, benefit, typicalSavingEUR, region, url, hint, code, symbol, ticketNote, featured
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        short = try c.decodeIfPresent(String.self, forKey: .short)
        category = try c.decode(PerkCategory.self, forKey: .category)
        benefit = try c.decode(String.self, forKey: .benefit)
        typicalSavingEUR = try c.decodeIfPresent(Double.self, forKey: .typicalSavingEUR) ?? 0
        region = try c.decodeIfPresent(String.self, forKey: .region) ?? "AT"
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        hint = try c.decodeIfPresent(String.self, forKey: .hint)
        code = try c.decodeIfPresent(String.self, forKey: .code)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol)
        ticketNote = try c.decodeIfPresent(String.self, forKey: .ticketNote)
        featured = try c.decodeIfPresent(Bool.self, forKey: .featured) ?? false
    }

    /// Region codes ("AT" stands for the whole of Austria).
    public var regionCodes: [String] {
        region.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public var isNationwide: Bool { regionCodes.isEmpty || regionCodes.contains("AT") }

    /// "Ganz Österreich", "Wien", "Wien · Oberösterreich · Salzburg", "7 Bundesländer".
    public var regionName: String {
        if isNationwide { return "Ganz Österreich" }
        let codes = regionCodes
        if codes.count > 3 { return "\(codes.count) Bundesländer" }
        return codes.map { FederalState(rawValue: $0)?.displayName ?? $0 }.joined(separator: " · ")
    }

    /// Full list of the states ("Wien, Niederösterreich, …") – for VoiceOver and search.
    public var regionLongName: String {
        if isNationwide { return "Ganz Österreich" }
        return regionCodes.map { FederalState(rawValue: $0)?.displayName ?? $0 }.joined(separator: ", ")
    }

    public var symbolName: String { symbol ?? category.symbolName }

    /// Name for compact places (chips, toasts).
    public var shortName: String { short ?? name }

    /// Text that search matches against (name, offer, region, category, hint).
    var searchableText: String {
        [name, short ?? "", benefit, regionLongName, category.displayName, hint ?? "", ticketNote ?? ""].joined(separator: " ")
    }
}

/// The bundled Vorteilswelt catalogue (App/Resources/benefits.json).
public struct PerkCatalog: Codable, Sendable {
    public var version: Int
    /// ISO day of the last check against the source ("2026-10-09").
    public var asOf: String
    /// Official overview page.
    public var source: String
    public var partners: [PerkPartner]

    /// Partner id used for benefits that are not in the catalogue.
    public static let customID = "custom"

    public init(version: Int, asOf: String, source: String, partners: [PerkPartner]) {
        self.version = version
        self.asOf = asOf
        self.source = source
        self.partners = partners
    }

    public static let empty = PerkCatalog(version: 0, asOf: "", source: "https://www.klimaticket.at/eins-fuer-mehr/", partners: [])

    public static func decode(_ data: Data) throws -> PerkCatalog {
        try JSONDecoder().decode(PerkCatalog.self, from: data)
    }

    public func partner(id: String) -> PerkPartner? {
        partners.first { $0.id == id }
    }

    /// Category of a logged benefit's partner id (unknown or custom ids → `.custom`).
    public func category(forPartnerID id: String) -> PerkCategory {
        partner(id: id)?.category ?? .custom
    }

    /// Featured partners first in catalogue order.
    public var featured: [PerkPartner] { partners.filter(\.featured) }

    /// Case-, diacritic- and umlaut-tolerant search ("oebb" finds "ÖBB", "museum" finds "Technisches Museum"),
    /// optionally limited to one category. All words of the query must match. Keeps the catalogue order.
    public func search(_ query: String, category: PerkCategory? = nil) -> [PerkPartner] {
        let words = PerkSearch.words(query)
        return partners.filter { partner in
            if let category, partner.category != category { return false }
            guard !words.isEmpty else { return true }
            let haystack = PerkSearch.normalizedVariants(partner.searchableText)
            return words.allSatisfy { word in haystack.contains { $0.contains(word) } }
        }
    }
}

enum PerkSearch {
    /// Normalised query words (each matched in both transliterated and folded form).
    static func words(_ query: String) -> [String] {
        query.split(whereSeparator: { $0.isWhitespace })
            .map { fold(String($0)) }
            .filter { !$0.isEmpty }
    }

    /// Both "ö → oe" and "ö → o" variants of the text, so either spelling of the query matches.
    static func normalizedVariants(_ text: String) -> [String] {
        [fold(text), fold(transliterate(text))]
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "de_AT"))
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    static func transliterate(_ text: String) -> String {
        var s = text
        for (from, to) in [("Ä", "Ae"), ("Ö", "Oe"), ("Ü", "Ue"), ("ä", "ae"), ("ö", "oe"), ("ü", "ue"), ("ß", "ss")] {
            s = s.replacingOccurrences(of: from, with: to)
        }
        return s
    }
}

// MARK: - Totals ("Zusatz-Ersparnis")

/// Value snapshot of one logged benefit.
public struct PerkUsage: Hashable, Sendable {
    public var date: Date
    public var partnerID: String
    public var savedEUR: Double

    public init(date: Date, partnerID: String, savedEUR: Double) {
        self.date = date
        self.partnerID = partnerID
        self.savedEUR = savedEUR
    }
}

/// Totals of the benefits used in a period – always reported separately from the trip-based payoff.
public struct PerkSummary: Equatable, Sendable {
    public struct CategoryTotal: Equatable, Sendable, Identifiable {
        public var category: PerkCategory
        public var total: Double
        public var count: Int
        public var id: String { category.rawValue }
    }

    public struct MonthTotal: Equatable, Sendable, Identifiable {
        /// Start of the calendar month (Vienna).
        public var month: Date
        public var total: Double
        public var count: Int
        public var id: Date { month }
    }

    public var total: Double = 0
    public var count: Int = 0
    /// Largest share first.
    public var byCategory: [CategoryTotal] = []
    /// Oldest month first; only months with benefits.
    public var byMonth: [MonthTotal] = []
    /// Most used partner (by count, then saving).
    public var topPartnerID: String?

    public init() {}

    public var isEmpty: Bool { count == 0 }

    /// Sums `usages` whose date lies in `from...to` (inclusive). Negative or non-finite savings are ignored.
    public static func make(usages: [PerkUsage], from start: Date, to end: Date, catalog: PerkCatalog,
                            calendar: Calendar = .vienna) -> PerkSummary {
        var summary = PerkSummary()
        var categories: [PerkCategory: CategoryTotal] = [:]
        var months: [Date: MonthTotal] = [:]
        var partners: [String: (count: Int, total: Double)] = [:]
        for usage in usages where usage.date >= start && usage.date <= end {
            let saved = usage.savedEUR.isFinite ? max(0, usage.savedEUR) : 0
            summary.total += saved
            summary.count += 1
            let category = catalog.category(forPartnerID: usage.partnerID)
            categories[category, default: CategoryTotal(category: category, total: 0, count: 0)].total += saved
            categories[category, default: CategoryTotal(category: category, total: 0, count: 0)].count += 1
            let month = calendar.dateInterval(of: .month, for: usage.date)?.start ?? calendar.startOfDay(for: usage.date)
            months[month, default: MonthTotal(month: month, total: 0, count: 0)].total += saved
            months[month, default: MonthTotal(month: month, total: 0, count: 0)].count += 1
            if usage.partnerID != PerkCatalog.customID {
                partners[usage.partnerID, default: (0, 0)].count += 1
                partners[usage.partnerID, default: (0, 0)].total += saved
            }
        }
        summary.total = (summary.total * 100).rounded() / 100
        summary.byCategory = categories.values.sorted { lhs, rhs in
            if lhs.total != rhs.total { return lhs.total > rhs.total }
            return (PerkCategory.allCases.firstIndex(of: lhs.category) ?? 0) < (PerkCategory.allCases.firstIndex(of: rhs.category) ?? 0)
        }
        summary.byMonth = months.values.sorted { $0.month < $1.month }
        summary.topPartnerID = partners.max { lhs, rhs in
            if lhs.value.count != rhs.value.count { return lhs.value.count < rhs.value.count }
            if lhs.value.total != rhs.value.total { return lhs.value.total < rhs.value.total }
            return lhs.key > rhs.key
        }?.key
        return summary
    }
}

// MARK: - Fahrgastrechte (passenger rights)

/// Which compensation scheme applies to a ticket.
public enum PerkRightsScheme: String, Sendable {
    /// KlimaTicket Ö: 93 % punctuality per validity month and railway (AGB Pkt. 24).
    case klimaTicketOe
    /// Regional KlimaTickets (Verbund annual network passes): ÖBB guarantees 95 % for its regional trains (Tarif A.5.3).
    case regional
    /// Custom tickets – no known scheme.
    case unknown

    public static func forFamily(_ family: TicketFamily) -> PerkRightsScheme {
        switch family {
        case .oe: .klimaTicketOe
        case .regional: .regional
        case .custom: .unknown
        }
    }

    /// Guaranteed punctuality (0…1).
    public var threshold: Double {
        switch self {
        case .klimaTicketOe: PerkRightsRules.oeThreshold
        case .regional, .unknown: PerkRightsRules.regionalThreshold
        }
    }
}

/// Official numbers behind the estimate.
public enum PerkRightsRules {
    /// KlimaTicket Ö punctuality guarantee per validity month (AGB 24.2).
    public static let oeThreshold = 0.93
    /// ÖBB guarantee for Verbund annual network passes (Tarifbestimmungen A.5.3.1.1).
    public static let regionalThreshold = 0.95
    /// 10 % of the monthly share of the compensation basis per month below the threshold (AGB 24.3).
    public static let compensationRate = 0.10
    /// Payouts below € 4 may be withheld (AGB 24.3; ÖBB A.5.4.1.6).
    public static let minimumPayoutEUR = 4.0
    /// ÖBB's published KlimaTicket Ö value per month below 93 % ("4,35 € ab 01.01.2025", oebb.at/fahrgastrechte).
    public static let oebbMonthlyEUR = 4.35
    /// KlimaTicket Ö Classic price for validity starts from 1.1.2025 – the price the published value belongs to
    /// (data/klimaticket_products.json `oe-klassik-202501`).
    public static let oebbReferencePriceEUR = 1_179.30
    /// A train counts as late from 5 min 30 s (ÖBB A.5.4.1.1).
    public static let lateFromSeconds = 330
    /// Reminder: this many days after the ticket's last valid day.
    public static let reminderDelayDays = 3
    /// Reminder time of day (Vienna).
    public static let reminderHour = 9
}

/// Honest compensation range for one ticket year.
public struct PerkRightsEstimate: Equatable, Sendable {
    public var scheme: PerkRightsScheme
    /// Compensation per month below the threshold – lower and upper end of the estimate.
    public var monthlyLow: Double
    public var monthlyHigh: Double
    /// Validity months considered.
    public var months: Int
    /// Months the user marked as "unter 93 %".
    public var badMonths: Int
    /// Additional compensation per bad month for a 1st-class upgrade (basis = upgrade price, ÖBB A.5.4.1.4).
    public var upgradeMonthly: Double

    /// Compensation for the marked months (incl. upgrade).
    public var expectedLow: Double { Self.round(Double(badMonths) * (monthlyLow + upgradeMonthly)) }
    public var expectedHigh: Double { Self.round(Double(badMonths) * (monthlyHigh + upgradeMonthly)) }
    /// Cap for a whole ticket year (= 10 % of the compensation basis, AGB 24.3).
    public var yearlyMaxLow: Double { Self.round(Double(months) * (monthlyLow + upgradeMonthly)) }
    public var yearlyMaxHigh: Double { Self.round(Double(months) * (monthlyHigh + upgradeMonthly)) }
    /// KlimaTicket Ö: the marked months may add up to less than the € 4 minimum payout.
    public var mayFallBelowMinimum: Bool {
        scheme == .klimaTicketOe && badMonths > 0 && expectedLow < PerkRightsRules.minimumPayoutEUR
    }
    /// The estimate is a range (not a single published value).
    public var isRange: Bool { abs(monthlyHigh - monthlyLow) >= 0.005 }

    static func round(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}

public enum PerkPassengerRights {
    /// Estimate for a ticket. For KlimaTicket Ö the range spans ÖBB's published € 4,35 per month and the same value
    /// scaled to the holder's ticket price (the basis is a share of the ticket price). For regional tickets only the
    /// upper bound is known (10 % of the price per year), so the low end is 0.
    public static func estimate(scheme: PerkRightsScheme, ticketPrice: Double, badMonths: Int = 0, months: Int = 12,
                                firstClassUpgradePrice: Double = 0) -> PerkRightsEstimate {
        let price = ticketPrice.isFinite ? max(0, ticketPrice) : 0
        let monthCount = max(1, months)
        let bad = min(max(0, badMonths), monthCount)
        var low = 0.0, high = 0.0
        switch scheme {
        case .klimaTicketOe:
            let published = PerkRightsRules.oebbMonthlyEUR
            let scaled = price > 0 ? published * price / PerkRightsRules.oebbReferencePriceEUR : published
            low = PerkRightsEstimate.round(min(published, scaled))
            high = PerkRightsEstimate.round(max(published, scaled))
        case .regional:
            low = 0
            high = PerkRightsEstimate.round(PerkRightsRules.compensationRate * price / 12)
        case .unknown:
            low = 0
            high = 0
        }
        let upgrade = scheme == .klimaTicketOe && firstClassUpgradePrice > 0
            ? PerkRightsEstimate.round(PerkRightsRules.compensationRate * firstClassUpgradePrice / 12)
            : 0
        return PerkRightsEstimate(scheme: scheme, monthlyLow: low, monthlyHigh: high, months: monthCount, badMonths: bad,
                                  upgradeMonthly: upgrade)
    }

    /// Validity months of a ticket: a new month starts on the same day number as the validity start (AGB:
    /// "am ziffernmäßig gleichen Kalendertag"); the last month ends with the ticket.
    public static func validityMonths(start: Date, end: Date, calendar: Calendar = .vienna) -> [DateInterval] {
        guard end > start else { return [] }
        let first = calendar.startOfDay(for: start)
        var result: [DateInterval] = []
        var index = 0
        while index < 24 {
            guard let monthStart = calendar.date(byAdding: .month, value: index, to: first) else { break }
            if monthStart > end { break }
            let next = calendar.date(byAdding: .month, value: index + 1, to: first) ?? end
            let monthEnd = min(next.addingTimeInterval(-1), end)
            result.append(DateInterval(start: monthStart, end: max(monthStart, monthEnd)))
            index += 1
        }
        return result
    }

    /// Index of the validity month containing `date` (nil outside the ticket).
    public static func monthIndex(of date: Date, in months: [DateInterval]) -> Int? {
        months.firstIndex { $0.start <= date && date <= $0.end }
    }

    /// When the reminder fires: `reminderDelayDays` after the ticket's last valid day, 09:00 Vienna.
    public static func reminderDate(expiry: Date, calendar: Calendar = .vienna) -> Date {
        let lastDay = calendar.startOfDay(for: expiry)
        let day = calendar.date(byAdding: .day, value: PerkRightsRules.reminderDelayDays, to: lastDay) ?? lastDay
        return calendar.date(bySettingHour: PerkRightsRules.reminderHour, minute: 0, second: 0, of: day) ?? day
    }

    /// First day on which the yearly compensation can be paid (the day after the ticket expired).
    public static func payoutFrom(expiry: Date, calendar: Calendar = .vienna) -> Date {
        let lastDay = calendar.startOfDay(for: expiry)
        return calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
    }
}
