import Foundation

// MARK: - Rules

/// KlimaTicket rules applied by the Ticket-Ratgeber.
///
/// Sources: `data/klimaticket_products.json` › `rules.oe` (AGB KlimaTicket Ö, gültig ab 01.01.2026: renewal,
/// ordinaryCancellation, extraordinaryCancellation, payment, categorySwitch, monthBoundaries), `specialProducts`
/// (Kennenlern-Aktion 2026, Familie) and ÖBB „Extras zum KlimaTicket Ö“ / „Mit Kindern unterwegs“ (verified 09.10.2026).
public enum AdvisorRules {
    /// Ordinary cancellation is possible from this validity month on (no reason needed).
    public static let ordinaryCancellationMonth = 7
    /// Kennenlern-Aktion 2026 (validity start 1.5.–30.6.2026): fee-free cancellation from the 2nd validity month.
    public static let kennenlernCancellationMonth = 2
    public static let kennenlernFirstStart = "2026-05-01"
    public static let kennenlernLastStart = "2026-06-30"
    /// Extraordinary cancellation (moving abroad, illness ≥ 3 months, unemployment) must be filed within 4 weeks.
    public static let extraordinaryFilingWeeks = 4
    /// The renewal letter arrives about 2 months before expiry; the objection deadline is printed in it.
    public static let renewalLetterMonths = 2
    /// Reminder for SEPA tickets: ~9 weeks before expiry, i.e. about a week before the letter is due.
    public static let renewalReminderDays = 63
    /// Wiener Linien / VOR: automatic renewal unless cancelled 1 month before expiry → remind two weeks before that.
    public static let monthBeforeReminderLeadDays = 14
    /// KlimaTicket Ö Familie: up to 4 children from the 6th birthday until the day before the 15th.
    public static let familyMaxChildren = 4
    /// ÖBB Standard-Ticket for children 6–14: half price.
    public static let childFareFactor = 0.5
    /// Familienaufschlag on KlimaTicket Ö (2026) – used when the catalogue cannot tell.
    public static let defaultFamilySurcharge = 140.0
    /// ÖBB Vorteilsabo: −30 % on class changes, 2 free class changes.
    public static let vorteilsaboClassChangeFactor = 0.7
    public static let vorteilsaboFreeUpgrades = 2
}

// MARK: - Add-ons

/// ÖBB extras that can be bought for a KlimaTicket Ö (persisted in `TicketEntity.addOnsRaw` – never rename the raw values).
public enum TicketAddOn: String, CaseIterable, Codable, Sendable, Identifiable {
    case firstClass
    case vorteilsabo
    case business

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .firstClass: "1.-Klasse-Upgrade"
        case .vorteilsabo: "Vorteilsabo"
        case .business: "Businessplatz-Abo"
        }
    }

    public var detail: String {
        switch self {
        case .firstClass: "1. Klasse in ÖBB-Fernverkehrszügen, Lounges, 10 Reservierungen"
        case .vorteilsabo: "−30 % auf den Klassenwechsel, 2 Gratis-Klassenwechsel"
        case .business: "20 Businessplätze im Railjet, nur mit 1.-Klasse-Upgrade"
        }
    }

    public var symbolName: String {
        switch self {
        case .firstClass: "sofa.fill"
        case .vorteilsabo: "percent"
        case .business: "briefcase.fill"
        }
    }

    /// ÖBB list price for the ticket category (ÖBB Extras zum KlimaTicket Ö, one-off payment, as of 09.10.2026).
    /// Upgrade: Classic 1.490 · Classic Familie 1.645 · Jugend/Senior/Spezial 1.130 · J/S/S Familie 1.285.
    /// Vorteilsabo: 100 (Classic) / 90 (Jugend/Senior/Spezial). Businessplatz-Abo: 20 Stück 290.
    public func listPrice(productID: String, variant: TicketVariant) -> Double {
        let reduced = TicketAddOn.isReducedCategory(productID: productID, variant: variant)
        let family = variant == .familie || productID.contains("familie")
        switch self {
        case .firstClass: return reduced ? (family ? 1_285 : 1_130) : (family ? 1_645 : 1_490)
        case .vorteilsabo: return reduced ? 90 : 100
        case .business: return 290
        }
    }

    /// Jugend / Senior / Spezial (and their Familie variant) are the reduced categories.
    public static func isReducedCategory(productID: String, variant: TicketVariant) -> Bool {
        switch variant {
        case .jugend, .senior, .spezial: return true
        case .klassik: return false
        case .familie: return productID.contains("ermaessigt")
        }
    }

    /// Known add-ons from their raw identifiers (unknown values are ignored).
    public static func parse(_ raw: [String]) -> Set<TicketAddOn> {
        Set(raw.compactMap { TicketAddOn(rawValue: $0.trimmingCharacters(in: .whitespaces)) })
    }

    /// Sum of the list prices of `addOns`.
    public static func listTotal(_ addOns: Set<TicketAddOn>, productID: String, variant: TicketVariant) -> Double {
        addOns.reduce(0) { $0 + $1.listPrice(productID: productID, variant: variant) }
    }
}

// MARK: - Euro input

/// Lenient parsing of euro amounts typed in Austrian notation – fixes the classic "1,50 € wird zu 150 €" bug.
public enum AdvisorEuro {
    /// Accepts "1.234,50", "1234,5", "800", "€ 1 234,50", "1.490,-", "23.50" and "1,234.50".
    /// Returns nil for anything that is not a non-negative amount. Rounded to cents.
    public static func parse(_ text: String) -> Double? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for junk in ["€", "EUR", "Euro", " ", "\u{00A0}", "\u{202F}", "'", "’"] {
            s = s.replacingOccurrences(of: junk, with: "")
        }
        for dash in [",-", ",–", ".-", ".–"] where s.hasSuffix(dash) {
            s = String(s.dropLast(dash.count))
        }
        guard !s.isEmpty, s.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "," || $0 == ".") }),
              s.contains(where: { $0.isNumber }) else { return nil }
        let commas = s.filter { $0 == "," }.count
        let dots = s.filter { $0 == "." }.count
        var normalized: String
        if commas > 0 && dots > 0 {
            // Both present: the last one is the decimal separator, the other groups thousands.
            guard let lastComma = s.lastIndex(of: ","), let lastDot = s.lastIndex(of: ".") else { return nil }
            let decimal: Character = lastComma > lastDot ? "," : "."
            let group: Character = decimal == "," ? "." : ","
            guard s.filter({ $0 == decimal }).count == 1 else { return nil }
            normalized = s.replacingOccurrences(of: String(group), with: "")
            normalized = normalized.replacingOccurrences(of: String(decimal), with: ".")
        } else if commas > 0 {
            normalized = commas == 1 ? s.replacingOccurrences(of: ",", with: ".") : s.replacingOccurrences(of: ",", with: "")
        } else if dots > 0 {
            if dots == 1, let dot = s.firstIndex(of: ".") {
                let before = s[..<dot].count
                let after = s[s.index(after: dot)...].count
                // "1.234" is a thousands separator in de-AT, "23.5" / "23.50" a decimal point.
                normalized = (after == 3 && before > 0) ? s.replacingOccurrences(of: ".", with: "") : s
            } else {
                normalized = s.replacingOccurrences(of: ".", with: "")
            }
        } else {
            normalized = s
        }
        guard let value = Double(normalized), value.isFinite, value >= 0 else { return nil }
        return (value * 100).rounded() / 100
    }

    /// Editable de-AT text for an amount: "800", "1.234,50" (empty for 0).
    public static func editString(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "" }
        let cents = Int((value * 100).rounded())
        let euros = cents / 100
        let rest = cents % 100
        var digits = String(euros)
        var grouped = ""
        while digits.count > 3 {
            grouped = "." + digits.suffix(3) + grouped
            digits = String(digits.dropLast(3))
        }
        grouped = digits + grouped
        guard rest > 0 else { return grouped }
        return grouped + "," + (rest < 10 ? "0\(rest)" : "\(rest)")
    }
}

// MARK: - Validity months

/// Validity months of a ticket: a new month starts on the same calendar day as the first day of validity
/// (rules.oe.monthBoundaries; clamped to the month's last day, e.g. 31 Jan → 28 Feb).
public struct AdvisorValidityMonths: Sendable {
    public let start: Date
    public let end: Date
    public let calendar: Calendar
    /// Number of validity months (12 for a standard ticket).
    public let monthCount: Int

    public init(start: Date, end: Date, calendar: Calendar = .vienna) {
        self.calendar = calendar
        self.start = calendar.startOfDay(for: start)
        self.end = end
        var count = 0
        for index in 1...36 {
            guard let monthStart = calendar.date(byAdding: .month, value: index - 1, to: calendar.startOfDay(for: start)),
                  monthStart <= end else { break }
            count = index
        }
        monthCount = max(1, count)
    }

    /// First day of validity month `index` (1-based). Always measured from the ticket start, so day 31 never drifts.
    public func start(ofMonth index: Int) -> Date {
        calendar.date(byAdding: .month, value: max(index, 1) - 1, to: start) ?? start
    }

    /// Last day (start of day) of validity month `index`.
    public func lastDay(ofMonth index: Int) -> Date {
        if index >= monthCount { return calendar.startOfDay(for: end) }
        let next = start(ofMonth: index + 1)
        return calendar.date(byAdding: .day, value: -1, to: next) ?? next
    }

    /// Validity month containing `date` (1…monthCount); 0 before the first day of validity.
    public func month(containing date: Date) -> Int {
        guard date >= start else { return 0 }
        var month = 1
        while month < monthCount && start(ofMonth: month + 1) <= date { month += 1 }
        return month
    }

    /// Whole days from the day of `from` to the day of `to` (0 when `to` is earlier).
    public func days(from: Date, to: Date) -> Int {
        max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)).day ?? 0)
    }
}

// MARK: - Inputs

/// Value snapshot of the user's ticket incl. the advisor-relevant fields (`TicketEntity` in the app).
public struct AdvisorTicket: Hashable, Sendable {
    public var productID: String
    public var name: String
    public var family: TicketFamily
    public var variant: TicketVariant
    public var states: [String]
    /// Ticket price paid to KlimaTicket (without add-ons, before the employer contribution).
    public var price: Double
    public var start: Date
    public var end: Date
    public var isMonthlyPayment: Bool
    public var autoRenews: Bool
    public var employerContribution: Double
    public var addOnPrice: Double
    public var addOns: [String]

    public init(productID: String, name: String, family: TicketFamily, variant: TicketVariant, states: [String] = [],
                price: Double, start: Date, end: Date, isMonthlyPayment: Bool = false, autoRenews: Bool = false,
                employerContribution: Double = 0, addOnPrice: Double = 0, addOns: [String] = []) {
        self.productID = productID
        self.name = name
        self.family = family
        self.variant = variant
        self.states = states
        self.price = price
        self.start = start
        self.end = end
        self.isMonthlyPayment = isMonthlyPayment
        self.autoRenews = autoRenews
        self.employerContribution = employerContribution
        self.addOnPrice = addOnPrice
        self.addOns = addOns
    }

    /// What the holder pays themselves (price + add-ons − employer contribution, never negative) – the payoff target.
    public var ownShare: Double { max(0, price + addOnPrice - employerContribution) }
    /// Price incl. add-ons, before the employer contribution.
    public var fullPrice: Double { max(0, price + addOnPrice) }
    public var addOnSet: Set<TicketAddOn> { TicketAddOn.parse(addOns) }
    public var period: TicketPeriod { TicketPeriod(productID: productID, name: name, price: ownShare, start: start, end: end) }
    public var isFamilyTicket: Bool { variant == .familie }
}

/// A logged trip plus what the advisor needs beyond `TripRecord` (travel class, ÖBB 1st-class surcharge).
public struct AdvisorTrip: Hashable, Sendable {
    public var record: TripRecord
    public var travelClass: TravelClass
    /// Normal-fare difference 1st − 2nd class for ONE direction (from the FareEstimator); nil = derive from the tariff factor.
    public var firstClassSurcharge: Double?

    public init(record: TripRecord, travelClass: TravelClass = .second, firstClassSurcharge: Double? = nil) {
        self.record = record
        self.travelClass = travelClass
        self.firstClassSurcharge = firstClassSurcharge
    }

    /// Builds the trip with the 1st-class surcharge priced by the estimator (official relation table or distance tariff,
    /// full fare without Vorteilscard) – only for train trips between known stations.
    public static func make(_ record: TripRecord, travelClass: TravelClass, estimator: FareEstimator,
                            stations: StationIndex) -> AdvisorTrip {
        guard record.mode == .train,
              let a = record.fromStationID.flatMap({ stations.station(id: $0) }),
              let b = record.toStationID.flatMap({ stations.station(id: $0) }), a.id != b.id else {
            return AdvisorTrip(record: record, travelClass: travelClass)
        }
        let first = estimator.estimate(from: a, to: b, mode: .train, travelClass: .first, discount: .none, date: record.date)
        let second = estimator.estimate(from: a, to: b, mode: .train, travelClass: .second, discount: .none, date: record.date)
        guard second.method != .cityTicket, first.fareEUR > second.fareEUR else {
            return AdvisorTrip(record: record, travelClass: travelClass)
        }
        return AdvisorTrip(record: record, travelClass: travelClass, firstClassSurcharge: first.fareEUR - second.fareEUR)
    }
}

// MARK: - Results

/// „Verlängern oder kündigen?“ – projection to expiry and for the next ticket year.
public struct RenewalAdvice: Hashable, Sendable {
    public enum Verdict: String, Sendable {
        /// Next year clearly pays off at the current pace.
        case renew
        /// Within ±10 % of the break-even – a handful of trips decide.
        case close
        /// Clearly below the price at the current pace.
        case reconsider
        /// Too little data for an honest recommendation.
        case tooEarly
    }

    public enum PriceStatus: Hashable, Sendable {
        /// A newer catalogue price for the renewal start is already published (valid from the date).
        case announced(Date)
        /// No newer price published yet – the price valid today is assumed.
        case latestKnown
        /// Ticket without catalogue product – the price paid is assumed.
        case custom
    }

    public var expiry: Date
    /// First day of the follow-up ticket (day after expiry; today at the earliest).
    public var renewalStart: Date
    public var autoRenews: Bool
    /// KlimaTicket Ö: the renewal letter with the objection deadline arrives about 2 months before expiry.
    public var letterDate: Date?
    /// Wiener Linien / VOR: cancellation must arrive 1 month before expiry.
    public var cancellationDeadline: Date?
    /// Suggested reminder (09:00 Vienna).
    public var reminderDate: Date
    public var ownShare: Double
    public var projectedValueAtExpiry: Double
    public var projectedNetAtExpiry: Double
    public var nextPrice: Double
    /// Next year's own share (next price − employer contribution, add-ons not included).
    public var nextOwnShare: Double
    public var priceStatus: PriceStatus
    /// Next price minus the price of the current ticket.
    public var priceChange: Double
    /// Tariff increase of regular fares between this and the next ticket year (catalogue fare index).
    public var fareGrowth: Double
    public var projectedNextYearValue: Double
    public var projectedNextYearNet: Double
    /// Trips (at today's average trip value) needed to pay off next year.
    public var nextYearBreakEvenTrips: Int?
    /// Projected break-even day next year at the same pace (nil when it would not be reached).
    public var nextYearBreakEvenDate: Date?
    public var nextYearLabel: String
    public var verdict: Verdict
    public var isExpired: Bool

    public var nextYearRatio: Double { nextOwnShare > 0 ? projectedNextYearValue / nextOwnShare : .infinity }
}

/// „Kündigungsrechner“ (rules.oe.ordinaryCancellation / extraordinaryCancellation / refundBeforeStart).
public struct CancellationAdvice: Hashable, Sendable {
    public enum Policy: Hashable, Sendable {
        /// KlimaTicket Ö: from the 7th month, fee 1/12.
        case klimaTicketOe
        /// Kennenlern-Aktion 2026: fee-free from the 2nd month.
        case kennenlern
        /// KlimaTicket OÖ: same scheme as KlimaTicket Ö (OÖVV).
        case ooevv
        /// Other regional ticket: only the operator's conditions in short.
        case regional(note: String)
        /// Own ticket: conditions unknown.
        case custom

        public var supportsCalculation: Bool {
            switch self {
            case .klimaTicketOe, .kennenlern, .ooevv: true
            case .regional, .custom: false
            }
        }
    }

    public enum Verdict: String, Sendable {
        /// Validity has not started yet → fee-free return possible.
        case beforeStart
        /// Ordinary cancellation not possible yet.
        case notYet
        /// Projected trips are worth more than the money back.
        case keep
        /// Money back exceeds the projected trip value – cancelling may pay off.
        case consider
        /// The fee eats up the refund (last months).
        case notWorthwhile
        case expired
        /// No calculation for this ticket type.
        case unsupported
    }

    public struct Quote: Hashable, Sendable {
        /// Day on which form and card are handed in.
        public var date: Date
        /// Validity month of that day.
        public var month: Int
        public var unstartedMonths: Int
        /// unstarted months × monthly amount.
        public var refundGross: Double
        public var fee: Double
        /// refundGross − fee (negative when the fee is higher).
        public var saving: Double
        /// Money paid back (single payment); 0 with monthly payment (instalments simply stop).
        public var refund: Double
        /// What the ticket costs in total when cancelled on `date`.
        public var totalCost: Double
        /// Projected value of the trips you would no longer make after `date`.
        public var lostTripValue: Double

        public var isWorthwhile: Bool { saving > 0.005 }
        /// Positive = cancelling leaves you better off (money saved − trips lost).
        public var balance: Double { saving - lostTripValue }
    }

    public struct Month: Hashable, Sendable, Identifiable {
        public var index: Int
        public var start: Date
        public var lastDay: Date
        public var isAllowed: Bool
        public var isPast: Bool
        public var isCurrent: Bool
        /// Saving when cancelling on the last day of this month.
        public var saving: Double
        /// Projected trip value after the last day of this month.
        public var lostTripValue: Double
        public var id: Int { index }
    }

    public var policy: Policy
    public var verdict: Verdict
    public var isMonthlyPayment: Bool
    public var price: Double
    public var monthCount: Int
    /// 0 before the start.
    public var currentMonth: Int
    public var possibleFromMonth: Int
    public var possibleFrom: Date
    /// Monthly amount (price / 12, cents).
    public var monthlyAmount: Double
    /// Ordinary cancellation fee (one monthly amount, rounded to 10 cent as in the AGB: 116,70 € for 1.400 €).
    public var fee: Double
    /// Cancelling today (only when allowed today).
    public var today: Quote?
    /// Cancelling on the last day of the current validity month – same money back, trips until then still included.
    public var endOfMonth: Quote?
    /// Cancelling on the first day of the next validity month (one monthly amount less).
    public var nextMonth: Quote?
    /// The first possible ordinary cancellation (last day of the first allowed month) when not allowed yet.
    public var firstPossible: Quote?
    /// Extraordinary cancellation today (no fee).
    public var extraordinary: Quote?
    public var months: [Month]
    /// Daily trip value used for the projections.
    public var dailyPace: Double
}

/// „1.-Klasse-Upgrade – lohnt sich das?“
public struct FirstClassAdvice: Hashable, Sendable {
    public enum Verdict: String, Sendable {
        case paidOff, notPaidOff, worthIt, notWorthIt, noTrainTrips
    }

    public var hasUpgrade: Bool
    public var upgradePrice: Double
    public var vorteilsaboPrice: Double
    /// Train trip entries considered / their legs.
    public var trainTrips: Int
    public var trainLegs: Int
    /// Trip entries logged in 1st class.
    public var firstClassTrips: Int
    /// True when only the trips logged in 1st class were counted (upgrade holders who mark their class).
    public var countsOnlyFirstClassTrips: Bool
    /// Σ (1st − 2nd class normal fare) of the considered trips so far.
    public var surchargeSoFar: Double
    /// … projected until expiry at the current pace.
    public var projectedSurcharge: Double
    public var averageSurchargePerLeg: Double
    /// Legs like yours needed for the upgrade to pay off.
    public var legsNeeded: Int?
    /// Projected cost of paying each class change with the Vorteilsabo (−30 %, 2 free).
    public var vorteilsaboCost: Double
    public var verdict: Verdict

    /// The cheapest way to ride all considered trips in 1st class (by projected cost).
    public var cheapestOption: Option {
        let options: [(Option, Double)] = [(.payPerTrip, projectedSurcharge), (.vorteilsabo, vorteilsaboCost), (.upgrade, upgradePrice)]
        return options.min { $0.1 < $1.1 }?.0 ?? .payPerTrip
    }

    public enum Option: String, Sendable { case payPerTrip, vorteilsabo, upgrade }
}

/// „Familien-Bilanz“ – value of the children's trips vs. the Familie surcharge.
public struct FamilyAdvice: Hashable, Sendable {
    public enum Verdict: String, Sendable {
        /// Familie ticket: children's trips already exceed the surcharge.
        case paidOff
        /// Familie ticket: projected to exceed it by expiry.
        case onTrack
        /// Familie ticket: projected below the surcharge.
        case notPaidOff
        /// No Familie ticket, but the logged companions would have been worth more than the surcharge.
        case worthSwitching
        case notWorthSwitching
        /// Familie ticket without trips with children yet.
        case noChildTrips
    }

    public var isFamilyTicket: Bool
    public var surcharge: Double
    public var tripsWithChildren: Int
    /// Σ children × legs (max. 4 children per trip).
    public var childJourneys: Int
    public var averageChildren: Double
    public var childValueSoFar: Double
    public var projectedChildValue: Double
    public var verdict: Verdict
}

/// „Jobticket“ – payoff measured against the own share.
public struct JobticketAdvice: Hashable, Sendable {
    public var hasContribution: Bool
    public var fullPrice: Double
    public var contribution: Double
    public var ownShare: Double
    /// ownShare / fullPrice (0…1).
    public var ownShareFraction: Double
    public var value: Double
    public var projectedValueAtExpiry: Double
    public var isOwnSharePaidOff: Bool
    /// Break-even of the own share (reached or forecast).
    public var ownBreakEven: Date?
    /// Break-even of the full price (reached or forecast) – what it would be without the contribution.
    public var fullBreakEven: Date?
    public var isFullPricePaidOff: Bool
    /// Regular fares of trips categorised as business trips.
    public var businessTripValue: Double
    /// AK rule: business trips with the own ticket are deductible up to the price paid yourself.
    public var deductibleBusinessValue: Double
}

/// Everything the Ratgeber screen shows for one ticket.
public struct TicketAdvice: Sendable {
    public var ticket: AdvisorTicket
    public var summary: SavingsSummary
    public var dailyPace: Double
    public var renewal: RenewalAdvice
    public var cancellation: CancellationAdvice
    /// KlimaTicket Ö only (ÖBB extra).
    public var firstClass: FirstClassAdvice?
    /// Familie tickets, or when trips with companions were logged on a ticket that offers a Familie option.
    public var family: FamilyAdvice?
    public var jobticket: JobticketAdvice
}

// MARK: - Advisor

public enum TicketAdvisor {
    public static func advise(ticket: AdvisorTicket, trips allTrips: [AdvisorTrip], catalog: TariffCatalog,
                              now: Date = Date(), calendar: Calendar = .vienna) -> TicketAdvice {
        let period = ticket.period
        let trips = allTrips.filter { period.contains($0.record.date) }.sorted { $0.record.date < $1.record.date }
        let records = trips.map(\.record)
        let summary = SavingsSummary.advisorSummary(period: period, records: records, now: now, catalog: catalog, calendar: calendar)
        let pace = now > ticket.end ? 0 : BreakEvenForecaster.dailyPace(ticket: period, trips: records, now: now, calendar: calendar)
        let projectedAtExpiry = now > ticket.end ? summary.totalValue : max(summary.forecastEndValue, summary.totalValue)
        let months = AdvisorValidityMonths(start: ticket.start, end: ticket.end, calendar: calendar)

        let renewal = renewalAdvice(ticket: ticket, summary: summary, projectedAtExpiry: projectedAtExpiry, catalog: catalog,
                                    now: now, calendar: calendar)
        let cancellation = cancellationAdvice(ticket: ticket, months: months, pace: pace, now: now)
        let firstClass = ticket.family == .oe
            ? firstClassAdvice(ticket: ticket, trips: trips, summary: summary, projectedAtExpiry: projectedAtExpiry,
                               factor: catalog.fareModel.firstClassFactor, isExpired: now > ticket.end)
            : nil
        let family = familyAdvice(ticket: ticket, trips: trips, summary: summary, projectedAtExpiry: projectedAtExpiry,
                                  catalog: catalog, factor: catalog.fareModel.firstClassFactor, isExpired: now > ticket.end)
        let job = jobticketAdvice(ticket: ticket, trips: trips, summary: summary, projectedAtExpiry: projectedAtExpiry,
                                  now: now, catalog: catalog, calendar: calendar)
        return TicketAdvice(ticket: ticket, summary: summary, dailyPace: pace, renewal: renewal, cancellation: cancellation,
                            firstClass: firstClass, family: family, jobticket: job)
    }

    // MARK: Renewal

    static func renewalAdvice(ticket: AdvisorTicket, summary: SavingsSummary, projectedAtExpiry: Double, catalog: TariffCatalog,
                              now: Date, calendar: Calendar) -> RenewalAdvice {
        let expiryDay = calendar.startOfDay(for: ticket.end)
        let dayAfter = calendar.date(byAdding: .day, value: 1, to: expiryDay) ?? ticket.end
        let renewalStart = max(calendar.startOfDay(for: dayAfter), calendar.startOfDay(for: now))
        let isExpired = now > ticket.end

        // Price for the renewal start (rules.oe.priceAppliesBy: the price depends on the first day of validity).
        let product = catalog.product(id: ticket.productID)
        let nextPrice: Double
        let status: RenewalAdvice.PriceStatus
        if let product {
            nextPrice = product.price(forStart: renewalStart, calendar: calendar)
            let today = TicketProduct.isoDay(now, calendar: calendar)
            let startDay = TicketProduct.isoDay(renewalStart, calendar: calendar)
            let points = (product.priceHistory ?? []) + [TicketProduct.PricePoint(validFrom: product.validFrom, priceEUR: product.priceEUR)]
            if let announced = points.filter({ $0.validFrom > today && $0.validFrom <= startDay }).max(by: { $0.validFrom < $1.validFrom }),
               let date = isoDate(announced.validFrom, calendar: calendar) {
                status = .announced(date)
            } else {
                status = .latestKnown
            }
        } else {
            nextPrice = ticket.price
            status = .custom
        }
        let nextOwnShare = max(0, nextPrice - ticket.employerContribution)

        // Same travel pattern next year, regular fares indexed (catalogue fare index, e.g. +3,5 % from 13.12.2026).
        let thisFactor = catalog.fareFactor(on: ticket.start, calendar: calendar)
        let nextFactor = catalog.fareFactor(on: renewalStart, calendar: calendar)
        let growth = thisFactor > 0 ? max(nextFactor / thisFactor, 0.5) : 1
        let nextEnd = TicketPeriod.standardEnd(for: renewalStart, calendar: calendar)
        let nextDays = max(1, (calendar.dateComponents([.day], from: renewalStart, to: calendar.startOfDay(for: nextEnd)).day ?? 364) + 1)
        let yearValue = projectedAtExpiry * Double(nextDays) / Double(max(summary.daysTotal, 1))
        let nextValue = yearValue * growth
        let nextDaily = nextValue / Double(nextDays)

        var breakEvenTrips: Int?
        if summary.averageValuePerTrip > 0 {
            breakEvenTrips = Int((nextOwnShare / (summary.averageValuePerTrip * growth)).rounded(.up))
        }
        var breakEvenDate: Date?
        if nextDaily > 0.0001 {
            let days = Int((nextOwnShare / nextDaily).rounded(.up))
            if days < nextDays { breakEvenDate = calendar.date(byAdding: .day, value: days, to: renewalStart) }
        }

        let reliable = summary.tripCount >= 5 && (summary.daysElapsed >= 28 || isExpired)
        let verdict: RenewalAdvice.Verdict
        if now < ticket.start || !reliable {
            verdict = .tooEarly
        } else if nextOwnShare <= 0.01 {
            verdict = .renew
        } else {
            let ratio = nextValue / nextOwnShare
            verdict = ratio >= 1.1 ? .renew : (ratio >= 0.9 ? .close : .reconsider)
        }

        // Reminder and deadlines.
        var letter: Date?
        var deadline: Date?
        var reminderDay: Date
        if ticket.productID.hasPrefix("wien-") || ticket.productID.hasPrefix("vor-") {
            let cut = calendar.date(byAdding: .month, value: -1, to: expiryDay) ?? expiryDay
            deadline = cut
            reminderDay = calendar.date(byAdding: .day, value: -AdvisorRules.monthBeforeReminderLeadDays, to: cut) ?? cut
        } else {
            if ticket.family == .oe {
                letter = calendar.date(byAdding: .month, value: -AdvisorRules.renewalLetterMonths, to: expiryDay)
            }
            reminderDay = calendar.date(byAdding: .day, value: -AdvisorRules.renewalReminderDays, to: expiryDay) ?? expiryDay
        }
        let reminder = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: reminderDay) ?? reminderDay

        return RenewalAdvice(
            expiry: ticket.end,
            renewalStart: renewalStart,
            autoRenews: ticket.autoRenews,
            letterDate: letter,
            cancellationDeadline: deadline,
            reminderDate: reminder,
            ownShare: ticket.ownShare,
            projectedValueAtExpiry: projectedAtExpiry,
            projectedNetAtExpiry: projectedAtExpiry - ticket.ownShare,
            nextPrice: nextPrice,
            nextOwnShare: nextOwnShare,
            priceStatus: status,
            priceChange: nextPrice - ticket.price,
            fareGrowth: growth,
            projectedNextYearValue: nextValue,
            projectedNextYearNet: nextValue - nextOwnShare,
            nextYearBreakEvenTrips: breakEvenTrips,
            nextYearBreakEvenDate: breakEvenDate,
            nextYearLabel: yearLabel(start: renewalStart, end: nextEnd, calendar: calendar),
            verdict: verdict,
            isExpired: isExpired
        )
    }

    // MARK: Cancellation

    /// Cancellation rules of the ticket (KlimaTicket Ö, Kennenlern-Aktion, OÖVV, or a note for other operators).
    public static func cancellationPolicy(for ticket: AdvisorTicket, calendar: Calendar = .vienna) -> CancellationAdvice.Policy {
        switch ticket.family {
        case .oe:
            let day = TicketProduct.isoDay(ticket.start, calendar: calendar)
            if day >= AdvisorRules.kennenlernFirstStart && day <= AdvisorRules.kennenlernLastStart { return .kennenlern }
            return .klimaTicketOe
        case .regional:
            let id = ticket.productID
            if id.hasPrefix("ooe-") { return .ooevv }
            if id.hasPrefix("wien-") {
                return .regional(note: "Jahreskarte WIEN: ordentliche Kündigung frühestens nach 7 Monaten, mit einem zusätzlichen Monatsbetrag (1/12). Davor nur Sonderkündigung, etwa bei Umzug aus Wien oder Arbeitslosigkeit. Bei SEPA verlängert sie sich automatisch, wenn du nicht 1 Monat vor Ablauf kündigst.")
            }
            if id.hasPrefix("vor-") {
                return .regional(note: "VOR KlimaTicket: Mindestlaufzeit 7 Monate. Bei Abbuchung verlängert es sich automatisch, wenn du nicht 1 Monat vor Ablauf kündigst.")
            }
            if id.hasPrefix("vbg-") {
                return .regional(note: "KlimaTicket VMOBIL: Bei vorzeitiger Kündigung wird je angefangenem Monat der Preis einer Monatskarte abgezogen (ab dem 3. Tag zählt ein Monat voll). Es verlängert sich automatisch.")
            }
            if id.hasPrefix("tirol-") {
                return .regional(note: "KlimaTicket Tirol: gilt ab Monatsersten für 12 Monate, mit Einmalzahlung oder monatlicher Abbuchung. Kündigung und Erstattung regelt der VVT.")
            }
            if id.hasPrefix("sbg-") {
                return .regional(note: "KlimaTicket Salzburg: Storno und Erstattung beantragst du beim Salzburger Verkehrsverbund (SVV).")
            }
            if id.hasPrefix("stmk-") {
                return .regional(note: "KlimaTicket Steiermark: Kündigung und Erstattung regelt der Verbund Linie nach seinen Tarifbestimmungen.")
            }
            if id.hasPrefix("ktn-") {
                return .regional(note: "Kärnten Ticket: Bei monatlicher Abbuchung zahlst du 12 Raten plus 1 € Spesen je Rate. Kündigung und Erstattung regeln die Kärntner Linien.")
            }
            return .regional(note: "Für regionale KlimaTickets gelten die Bedingungen deines Verkehrsverbunds.")
        case .custom:
            return .custom
        }
    }

    static func cancellationAdvice(ticket: AdvisorTicket, months: AdvisorValidityMonths, pace: Double, now: Date) -> CancellationAdvice {
        let calendar = months.calendar
        let policy = cancellationPolicy(for: ticket, calendar: calendar)
        let price = max(ticket.price, 0)
        let monthly = (price / 12 * 100).rounded() / 100
        let ordinaryFee: Double = policy == .kennenlern ? 0 : (price / 12 * 10).rounded() / 10
        let fromMonth = policy == .kennenlern ? AdvisorRules.kennenlernCancellationMonth : AdvisorRules.ordinaryCancellationMonth
        let current = months.month(containing: now)
        let isExpired = now > ticket.end

        func quote(on date: Date, fee: Double) -> CancellationAdvice.Quote {
            let month = max(1, months.month(containing: date))
            let unstarted = max(0, months.monthCount - month)
            let gross = Double(unstarted) * monthly
            let saving = gross - fee
            let refund = ticket.isMonthlyPayment ? 0 : max(0, saving)
            let total = ticket.isMonthlyPayment ? price - saving : price - refund
            let lost = pace * Double(months.days(from: date, to: ticket.end))
            return .init(date: calendar.startOfDay(for: date), month: month, unstartedMonths: unstarted, refundGross: gross,
                         fee: fee, saving: saving, refund: refund, totalCost: total, lostTripValue: lost)
        }

        let possibleFrom = months.start(ofMonth: fromMonth)
        var timeline: [CancellationAdvice.Month] = []
        if policy.supportsCalculation {
            for index in 1...months.monthCount {
                let last = months.lastDay(ofMonth: index)
                let q = quote(on: last, fee: ordinaryFee)
                timeline.append(.init(index: index, start: months.start(ofMonth: index), lastDay: last,
                                      isAllowed: index >= fromMonth, isPast: current > index || isExpired,
                                      isCurrent: index == current && !isExpired,
                                      saving: q.saving, lostTripValue: q.lostTripValue))
            }
        }

        var today: CancellationAdvice.Quote?
        var endOfMonth: CancellationAdvice.Quote?
        var nextMonth: CancellationAdvice.Quote?
        var firstPossible: CancellationAdvice.Quote?
        var extraordinary: CancellationAdvice.Quote?
        let verdict: CancellationAdvice.Verdict

        if !policy.supportsCalculation {
            verdict = isExpired ? .expired : (current == 0 ? .beforeStart : .unsupported)
        } else if isExpired {
            verdict = .expired
        } else if current == 0 {
            verdict = .beforeStart
        } else {
            extraordinary = quote(on: now, fee: 0)
            if current >= fromMonth {
                let q = quote(on: now, fee: ordinaryFee)
                let e = quote(on: months.lastDay(ofMonth: current), fee: ordinaryFee)
                today = q
                endOfMonth = e
                if current < months.monthCount {
                    nextMonth = quote(on: months.start(ofMonth: current + 1), fee: ordinaryFee)
                }
                if !e.isWorthwhile {
                    verdict = .notWorthwhile
                } else {
                    verdict = e.lostTripValue > e.saving ? .keep : .consider
                }
            } else {
                firstPossible = quote(on: months.lastDay(ofMonth: fromMonth), fee: ordinaryFee)
                verdict = .notYet
            }
        }

        return CancellationAdvice(policy: policy, verdict: verdict, isMonthlyPayment: ticket.isMonthlyPayment, price: price,
                                  monthCount: months.monthCount, currentMonth: current, possibleFromMonth: fromMonth,
                                  possibleFrom: possibleFrom, monthlyAmount: monthly, fee: ordinaryFee, today: today,
                                  endOfMonth: endOfMonth, nextMonth: nextMonth, firstPossible: firstPossible,
                                  extraordinary: extraordinary, months: timeline, dailyPace: pace)
    }

    // MARK: First class

    static func firstClassAdvice(ticket: AdvisorTicket, trips: [AdvisorTrip], summary: SavingsSummary, projectedAtExpiry: Double,
                                 factor: Double, isExpired: Bool) -> FirstClassAdvice {
        let addOns = ticket.addOnSet
        let hasUpgrade = addOns.contains(.firstClass)
        let listPrice = TicketAddOn.firstClass.listPrice(productID: ticket.productID, variant: ticket.variant)
        // The price the holder entered counts when the upgrade is the only add-on (otherwise the list price).
        let upgradePrice = hasUpgrade && addOns.count == 1 && ticket.addOnPrice > 0 ? ticket.addOnPrice : listPrice
        let aboPrice = TicketAddOn.vorteilsabo.listPrice(productID: ticket.productID, variant: ticket.variant)

        let train = trips.filter { $0.record.mode == .train }
        let firstTrips = train.filter { $0.travelClass == .first }
        let onlyFirst = hasUpgrade && !firstTrips.isEmpty
        let considered = onlyFirst ? firstTrips : train

        var legSurcharges: [Double] = []
        for trip in considered {
            let perLeg = surcharge(of: trip, factor: factor)
            for _ in 0..<trip.record.legs { legSurcharges.append(perLeg) }
        }
        let soFar = legSurcharges.reduce(0, +)
        let scale = summary.totalValue > 0 ? max(1, projectedAtExpiry / summary.totalValue) : 1
        let projected = isExpired ? soFar : soFar * scale
        let average = legSurcharges.isEmpty ? 0 : soFar / Double(legSurcharges.count)
        let legsNeeded = average > 0 ? Int((upgradePrice / average).rounded(.up)) : nil
        let free = legSurcharges.sorted(by: >).prefix(AdvisorRules.vorteilsaboFreeUpgrades).reduce(0, +)
        let aboCost = aboPrice + AdvisorRules.vorteilsaboClassChangeFactor * max(0, projected - free)

        let verdict: FirstClassAdvice.Verdict
        if considered.isEmpty {
            verdict = .noTrainTrips
        } else if hasUpgrade {
            verdict = projected >= upgradePrice ? .paidOff : .notPaidOff
        } else {
            verdict = projected >= upgradePrice ? .worthIt : .notWorthIt
        }
        return FirstClassAdvice(hasUpgrade: hasUpgrade, upgradePrice: upgradePrice, vorteilsaboPrice: aboPrice,
                                trainTrips: considered.count, trainLegs: legSurcharges.count, firstClassTrips: firstTrips.count,
                                countsOnlyFirstClassTrips: onlyFirst, surchargeSoFar: soFar, projectedSurcharge: projected,
                                averageSurchargePerLeg: average, legsNeeded: legsNeeded, vorteilsaboCost: aboCost, verdict: verdict)
    }

    /// 2nd-class normal fare of one leg (the stored fare is the 1st-class fare when the trip was logged in 1st class).
    static func secondClassFare(of trip: AdvisorTrip, factor: Double) -> Double {
        let fare = max(trip.record.fareEUR, 0)
        guard trip.travelClass == .first, trip.record.mode == .train, factor > 0 else { return fare }
        return fare / factor
    }

    /// 1st − 2nd class difference of one leg: the estimator's value, otherwise the tariff's 1st-class factor.
    static func surcharge(of trip: AdvisorTrip, factor: Double) -> Double {
        if let value = trip.firstClassSurcharge { return max(0, value) }
        return secondClassFare(of: trip, factor: factor) * max(0, factor - 1)
    }

    // MARK: Family

    /// Familie surcharge for a ticket start (catalogue: Familie product − base product), nil when there is no Familie option.
    public static func familySurcharge(productID: String, variant: TicketVariant, start: Date, catalog: TariffCatalog,
                                       calendar: Calendar = .vienna) -> Double? {
        let ids: (family: String, base: String)?
        if variant == .familie {
            ids = familyBaseID(for: productID).map { (productID, $0) }
        } else {
            ids = familyVariantID(for: productID).map { ($0, productID) }
        }
        if let ids, let familyProduct = catalog.product(id: ids.family), let base = catalog.product(id: ids.base) {
            let value = familyProduct.price(forStart: start, calendar: calendar) - base.price(forStart: start, calendar: calendar)
            if value > 0 { return value }
        }
        if productID.hasPrefix("oe-") || (variant == .familie && catalog.product(id: productID)?.family == .oe) {
            return AdvisorRules.defaultFamilySurcharge
        }
        return nil
    }

    static func familyBaseID(for familyID: String) -> String? {
        switch familyID {
        case "oe-familie-klassik": return "oe-klassik"
        case "oe-familie-ermaessigt": return "oe-jugend"
        default: return familyID.hasSuffix("-familie") ? String(familyID.dropLast("-familie".count)) : nil
        }
    }

    static func familyVariantID(for baseID: String) -> String? {
        switch baseID {
        case "oe-klassik": return "oe-familie-klassik"
        case "oe-jugend", "oe-senior", "oe-spezial": return "oe-familie-ermaessigt"
        default: return baseID + "-familie"
        }
    }

    static func familyAdvice(ticket: AdvisorTicket, trips: [AdvisorTrip], summary: SavingsSummary, projectedAtExpiry: Double,
                             catalog: TariffCatalog, factor: Double, isExpired: Bool) -> FamilyAdvice? {
        let withChildren = trips.filter { $0.record.companions > 0 }
        guard ticket.isFamilyTicket || !withChildren.isEmpty else { return nil }
        guard let surcharge = familySurcharge(productID: ticket.productID, variant: ticket.variant, start: ticket.start,
                                              catalog: catalog) else { return nil }
        var journeys = 0
        var value = 0.0
        for trip in withChildren {
            let children = min(trip.record.companions, AdvisorRules.familyMaxChildren)
            journeys += children * trip.record.legs
            value += Double(children * trip.record.legs) * secondClassFare(of: trip, factor: factor) * AdvisorRules.childFareFactor
        }
        let scale = summary.totalValue > 0 ? max(1, projectedAtExpiry / summary.totalValue) : 1
        let projected = isExpired ? value : value * scale
        let verdict: FamilyAdvice.Verdict
        if ticket.isFamilyTicket {
            if withChildren.isEmpty { verdict = .noChildTrips }
            else if value >= surcharge { verdict = .paidOff }
            else { verdict = projected >= surcharge ? .onTrack : .notPaidOff }
        } else {
            verdict = projected >= surcharge ? .worthSwitching : .notWorthSwitching
        }
        let average = withChildren.isEmpty ? 0 : Double(withChildren.reduce(0) { $0 + min($1.record.companions, AdvisorRules.familyMaxChildren) }) / Double(withChildren.count)
        return FamilyAdvice(isFamilyTicket: ticket.isFamilyTicket, surcharge: surcharge, tripsWithChildren: withChildren.count,
                            childJourneys: journeys, averageChildren: average, childValueSoFar: value,
                            projectedChildValue: projected, verdict: verdict)
    }

    // MARK: Jobticket

    static func jobticketAdvice(ticket: AdvisorTicket, trips: [AdvisorTrip], summary: SavingsSummary, projectedAtExpiry: Double,
                                now: Date, catalog: TariffCatalog, calendar: Calendar) -> JobticketAdvice {
        let records = trips.map(\.record)
        let fullPeriod = TicketPeriod(productID: ticket.productID, name: ticket.name, price: ticket.fullPrice,
                                      start: ticket.start, end: ticket.end)
        let full = SavingsSummary.advisorSummary(period: fullPeriod, records: records, now: now, catalog: catalog, calendar: calendar)
        let business = records.filter { $0.category == .business }.reduce(0) { $0 + $1.totalValue }
        let contribution = min(max(ticket.employerContribution, 0), ticket.fullPrice)
        return JobticketAdvice(
            hasContribution: contribution > 0.004,
            fullPrice: ticket.fullPrice,
            contribution: contribution,
            ownShare: ticket.ownShare,
            ownShareFraction: ticket.fullPrice > 0 ? ticket.ownShare / ticket.fullPrice : 1,
            value: summary.totalValue,
            projectedValueAtExpiry: projectedAtExpiry,
            isOwnSharePaidOff: summary.isPaidOff,
            ownBreakEven: summary.paidOffDate ?? (summary.forecastReachesBreakEven ? summary.forecastBreakEvenDate : nil),
            fullBreakEven: full.paidOffDate ?? (full.forecastReachesBreakEven ? full.forecastBreakEvenDate : nil),
            isFullPricePaidOff: full.isPaidOff,
            businessTripValue: business,
            deductibleBusinessValue: min(business, ticket.ownShare)
        )
    }

    // MARK: Helpers

    static func isoDate(_ iso: String, calendar: Calendar) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// "2027/28" (or "2027" within one calendar year).
    public static func yearLabel(start: Date, end: Date, calendar: Calendar = .vienna) -> String {
        let a = calendar.component(.year, from: start)
        let b = calendar.component(.year, from: end)
        return a == b ? "\(a)" : "\(a)/\(String(format: "%02d", b % 100))"
    }
}

extension SavingsSummary {
    /// Summary with the catalogue's Kilometergeld and emission factors (same as the app's Analytics).
    static func advisorSummary(period: TicketPeriod, records: [TripRecord], now: Date, catalog: TariffCatalog, calendar: Calendar) -> SavingsSummary {
        SavingsCalculator.summary(ticket: period, trips: records, now: now, kilometergeld: catalog.kilometergeldEUR,
                                  emissions: catalog.emissions, calendar: calendar)
    }
}
