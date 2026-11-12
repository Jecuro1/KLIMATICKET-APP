import Foundation

// MARK: - Limits

/// Hard limits of „Was wäre wenn?“ (docs/WHATIF.md). Every input is clamped to them, so a hand-edited scenario, an
/// old save or a slider dragged to the end can never produce a nonsensical number.
public enum WhatIfLimits {
    /// Routes in the assumptions mode.
    public static let maxRoutes = 3
    /// Trips per month and route (one trip = one direction).
    public static let maxTripsPerMonth = 60
    /// Slider of the real-data mode: „Fahrten ×0,5 bis ×2“.
    public static let volumeRange: ClosedRange<Double> = 0.5...2
    /// Saved scenarios.
    public static let maxScenarios = 5
    /// Months of the cost chart (the ticket year).
    public static let months = 12
    /// Real-data mode needs this many trips in the last 12 months to be the default.
    public static let minHistoryTrips = 5
}

// MARK: - Assumptions

/// One route of the assumptions mode: two stations, how often per month, in which class.
public struct WhatIfRoute: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var fromStationID: String
    public var toStationID: String
    /// One trip = one direction: a daily commute with the way back is about 40 per month.
    public var tripsPerMonth: Int
    public var travelClass: TravelClass

    public init(id: UUID = UUID(), fromStationID: String, toStationID: String, tripsPerMonth: Int = 4,
                travelClass: TravelClass = .second) {
        self.id = id
        self.fromStationID = fromStationID
        self.toStationID = toStationID
        self.tripsPerMonth = tripsPerMonth
        self.travelClass = travelClass
    }

    /// `tripsPerMonth` limited to 0…60.
    public var clampedTrips: Int { min(max(tripsPerMonth, 0), WhatIfLimits.maxTripsPerMonth) }
}

/// Everything the calculator needs besides the trips themselves.
public struct WhatIfInput: Codable, Hashable, Sendable {
    /// Assumptions mode: up to three routes (more are ignored). Unused in the real-data mode.
    public var routes: [WhatIfRoute]
    /// Compared ticket variant (Klassik, Jugend, Senior); single tickets are always part of the comparison.
    public var variant: TicketVariant
    /// Start of the ticket year: prices of the tickets (`TicketProduct.price(forStart:)`) and the fare index apply from
    /// here, and the chart's first month is this month.
    public var startDate: Date
    /// Calendar months (1 = Jänner … 12 = Dezember) without any trips, e.g. `[7, 8]` for „Juli/August ohne Fahrten“.
    public var excludedMonths: Set<Int>
    /// Only trips entirely inside this federal state count (`FederalState.rawValue`, e.g. "T"); nil = all trips.
    public var regionFilter: String?
    /// Real-data mode: price every trip as 1. Klasse (single tickets × the catalogue's 1.-Klasse factor; KlimaTicket Ö plus
    /// the 1.-Klasse-Upgrade; regional tickets cover only the 2. Klasse).
    public var useFirstClass: Bool
    /// Real-data mode: „Fahrten ×0,5 bis ×2“.
    public var volumeFactor: Double
    /// The user's own ticket (kept in the comparison even if it is not of `variant`), nil without a ticket.
    public var currentProductID: String?

    public init(routes: [WhatIfRoute] = [], variant: TicketVariant = .klassik, startDate: Date = Date(),
                excludedMonths: Set<Int> = [], regionFilter: String? = nil, useFirstClass: Bool = false,
                volumeFactor: Double = 1, currentProductID: String? = nil) {
        self.routes = routes
        self.variant = variant
        self.startDate = startDate
        self.excludedMonths = excludedMonths
        self.regionFilter = regionFilter
        self.useFirstClass = useFirstClass
        self.volumeFactor = volumeFactor
        self.currentProductID = currentProductID
    }

    /// Routes that count: at most `maxRoutes`.
    public var activeRoutes: [WhatIfRoute] { Array(routes.prefix(WhatIfLimits.maxRoutes)) }

    /// `volumeFactor` inside 0,5…2; NaN counts as 1.
    public var clampedVolume: Double {
        guard volumeFactor.isFinite else { return 1 }
        return min(max(volumeFactor, WhatIfLimits.volumeRange.lowerBound), WhatIfLimits.volumeRange.upperBound)
    }

    /// `excludedMonths` reduced to valid months.
    public var validExcludedMonths: Set<Int> { excludedMonths.filter { (1...12).contains($0) } }
}

// MARK: - Real data

/// The user's own trips for the real-data mode: the last 12 months plus how long they have been collected.
public struct WhatIfHistory: Sendable {
    /// Trips of the observed window (deleted ones are not part of it).
    public var trips: [TripRecord]
    /// Trips logged in 1. Klasse – with „mit 1. Klasse“ they are not priced up a second time.
    public var firstClassTripIDs: Set<UUID>
    /// Scales the trips to a full year when the window just started (≥ 1); see `WhatIfBaseline`.
    public var annualizationFactor: Double

    public init(trips: [TripRecord], firstClassTripIDs: Set<UUID> = [], annualizationFactor: Double = 1) {
        self.trips = trips
        self.firstClassTripIDs = firstClassTripIDs
        self.annualizationFactor = annualizationFactor
    }

    /// Whether the history is rich enough to be the default mode (≥ 5 trips).
    public var isRichEnough: Bool { trips.count >= WhatIfLimits.minHistoryTrips }
}

/// Which trips are „the last 12 months“ and whether they have to be scaled to a year.
///
/// The screen speaks of „pro Jahr“, so a window shorter than a year is always projected to a full year (× 365 ÷ observed
/// days). Without that, 225 days of trips would be compared with a full year's ticket price and „kaum ein Unterschied“ would
/// hide a saving of a few hundred euros. (The Ticket-Vergleich in Statistik answers a different question – „bisher“ – and
/// scales only below a quarter of the year; the two therefore agree for a full year and differ, on purpose, in between.)
public struct WhatIfBaseline: Hashable, Sendable {
    /// First day of the window.
    public var windowStart: Date
    /// Days from `windowStart` to today, inclusive (1…365).
    public var observedDays: Int
    /// 1 for (nearly) a full year, else year ÷ observed days (never more than the cap).
    public var annualizationFactor: Double

    public static let yearDays = 365
    /// One observed day would otherwise mean „× 365“: the window counts as at least a month.
    public static let minimumObservedDays = 30
    /// A factor below this (a window of 348 days or more) counts as a full year: „× 1,02“ is noise.
    public static let fullYearFactor = 1.05

    /// - Parameter firstActivity: the earliest of the first ticket start and the first trip; nil = a full window.
    public static func make(now: Date, firstActivity: Date?, calendar: Calendar = .vienna) -> WhatIfBaseline {
        let today = calendar.startOfDay(for: now)
        let yearAgo = calendar.date(byAdding: .year, value: -1, to: today) ?? today
        var start = yearAgo
        if let first = firstActivity.map({ calendar.startOfDay(for: $0) }), first > yearAgo { start = min(first, today) }
        let span = (calendar.dateComponents([.day], from: start, to: today).day ?? 0) + 1
        let observed = min(max(span, 1), yearDays)
        let effective = Double(max(observed, minimumObservedDays))
        let raw = Double(yearDays) / effective
        return WhatIfBaseline(windowStart: start, observedDays: observed, annualizationFactor: raw < fullYearFactor ? 1 : raw)
    }

    /// Whether the figures are scaled up to a year (then the screen says so).
    public var isAnnualized: Bool { annualizationFactor > 1.0001 }
}
