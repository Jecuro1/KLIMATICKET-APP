import Foundation

// "Dein Jahr" (docs/YEAR_REVIEW.md): the pages of the year story and the rules that skip a page whose data is missing.
//
// Nothing is stored and nothing is calculated twice: every figure comes out of the calculators Statistik and the PDF
// Jahresbericht use – `SavingsCalculator`, `CategoryStats.honestBalance`, `StatsAggregator`, `CarComparison`. The only
// new maths is the pro-rata ticket cost of a calendar year (`YearReviewPeriods.accountingPeriod`) and the reference
// distance (`ReferenceDistances`).

public enum YearReviewPageKind: String, CaseIterable, Hashable, Sendable {
    case intro
    case savings
    case distance
    case favoriteRoute
    case rhythm
    case onTheRoad
    case purpose
    case climate
    case finale
}

public struct YearReview: Hashable, Sendable {
    // MARK: Page payloads

    /// Page 1 – period, ticket and the number of trips.
    public struct Intro: Hashable, Sendable {
        public var ticketName: String?
        /// "Fahrten": a journey counts once, a round trip counts once (like everywhere in the app).
        public var tripCount: Int
        public var travelDays: Int
    }

    /// Page 2 – the value of all trips against the own ticket price (the headline Statistik, the Übersicht hero and the
    /// Jahresbericht show), with the honest balance as a separate line.
    public struct Savings: Hashable, Sendable {
        /// Own ticket costs of the period (a calendar year: pro rata up to today). 0 = no ticket in the period.
        public var ticketCost: Double
        /// Regular-fare value of all trips (`SavingsSummary.totalValue`) – the headline.
        public var totalValue: Double
        /// Value of the trips that would otherwise have been paid for (`HonestBalance.realSavings`).
        public var realValue: Double
        /// Value of the trips made only because of the ticket ("Ohne Ticket wäre ich nicht gefahren"): extra value, no saving.
        public var extraValue: Double
        public var inducedTripCount: Int
        public var tripCount: Int
        /// The day a ticket of the period paid off (`SavingsSummary.paidOffDate` rule: all trips), when that day lies inside
        /// the period.
        public var breakEvenDate: Date?
        public var breakEvenTicketName: String?
        /// A calendar year: the ticket cost is the share of the days up to today, not the whole price.
        public var costIsPartial: Bool

        public var hasTicketCost: Bool { ticketCost > 0.005 }
        public var hasInducedTrips: Bool { inducedTripCount > 0 }
        /// `totalValue − ticketCost`: positive = profit.
        public var net: Double { totalValue - ticketCost }
        public var isPaidOff: Bool { hasTicketCost && totalValue >= ticketCost }
        public var remaining: Double { max(0, ticketCost - totalValue) }
        /// The same, counting only trips that would otherwise have been bought (identical when nothing is induced).
        public var honestNet: Double { realValue - ticketCost }
        public var isHonestlyPaidOff: Bool { hasTicketCost && realValue >= ticketCost }
        public var honestRemaining: Double { max(0, ticketCost - realValue) }
    }

    /// Page 3 – kilometres, put in perspective.
    public struct Distance: Hashable, Sendable {
        public var km: Double
        public var legCount: Int
        public var reference: ReferenceComparison?
    }

    /// Page 4 – the route taken most often (a round trip counts once).
    public struct FavoriteRoute: Hashable, Sendable {
        public var top: RouteStat
        /// The next two routes.
        public var runnersUp: [RouteStat]
    }

    /// Page 5 – best month, busiest weekday, longest streak.
    public struct Rhythm: Hashable, Sendable {
        /// Every month of the period (empty ones included), oldest first.
        public var months: [MonthBucket]
        public var bestMonth: MonthBucket?
        public var weekdays: [WeekdayBucket]
        /// The weekday with the most trips (ties: higher value, then earlier in the week).
        public var busiestWeekday: WeekdayBucket?
        public var longestStreakDays: Int
        public var travelDays: Int
    }

    /// Page 6 – where the year took you.
    public struct OnTheRoad: Hashable, Sendable {
        /// Visited Austrian federal states in the usual order (Wien … Burgenland), abroad excluded.
        public var states: [FederalState]
        public var stateCount: Int { states.count }
        /// All Austrian states (`FederalState` without "Ausland").
        public static let totalStates = FederalState.allCases.filter { $0 != .foreign }.count
        public var longestTrip: TripRecord?
        public var mostValuableTrip: TripRecord?
        public var uniqueStations: Int
    }

    /// Optional page "Wofür" – only with at least `YearReview.minPurposeTrips` categorised trips.
    public struct Purpose: Hashable, Sendable {
        /// Categorised buckets, most trips first (ties: higher value, then the usual category order); the uncategorised
        /// bucket is left out.
        public var buckets: [CategoryBucket]
        public var categorisedTrips: Int
        /// All trips of the period: the percentages of `CategoryBucket.tripShare` are shares of these (like Statistik ›
        /// "Wofür du fährst"), so the page can say "70 von 79 Fahrten haben einen Zweck".
        public var totalTrips: Int
    }

    /// Page 7 – CO₂ against the car (Schätzung).
    public struct Climate: Hashable, Sendable {
        /// `CarComparisonResult.co2SavedKg` – the figure of Statistik › "Öffis vs. Auto".
        public var co2SavedKg: Double
        public var co2CarKg: Double
        public var co2TransitKg: Double
        /// Road km the car would have driven (rail km × road factor).
        public var carRoadKm: Double
    }

    /// Page 8 – the totals the share image carries.
    public struct Finale: Hashable, Sendable {
        public var tripCount: Int
        public var distanceKm: Double
        public var totalValue: Double
        public var net: Double
        public var hasTicketCost: Bool
        public var co2SavedKg: Double?
    }

    public enum Page: Hashable, Sendable, Identifiable {
        case intro(Intro)
        case savings(Savings)
        case distance(Distance)
        case favoriteRoute(FavoriteRoute)
        case rhythm(Rhythm)
        case onTheRoad(OnTheRoad)
        case purpose(Purpose)
        case climate(Climate)
        case finale(Finale)

        public var kind: YearReviewPageKind {
            switch self {
            case .intro: .intro
            case .savings: .savings
            case .distance: .distance
            case .favoriteRoute: .favoriteRoute
            case .rhythm: .rhythm
            case .onTheRoad: .onTheRoad
            case .purpose: .purpose
            case .climate: .climate
            case .finale: .finale
            }
        }

        public var id: String { kind.rawValue }
    }

    // MARK: Skip rules

    /// A route is a "Lieblingsroute" from this many trips on – a single ride is no favourite.
    public static let minFavoriteRouteTrips = 2
    /// Best month, weekday and streak say something from this many trips on.
    public static let minRhythmTrips = 3
    /// "Wofür" needs this many categorised trips.
    public static let minPurposeTrips = 3
    /// The climate page needs at least this many kg saved: the page shows whole kilograms, so less would read "0 kg".
    public static let minClimateKg = 0.5

    // MARK: Value

    public var period: YearReviewPeriod
    /// The period as one `TicketPeriod` (the ticket itself, or the pro-rata year) – what the calculators were fed with.
    public var accounting: TicketPeriod
    public var pages: [Page]

    /// No trip in the period: no page at all (the story shows its friendly empty state).
    public var isEmpty: Bool { pages.isEmpty }

    public init(period: YearReviewPeriod, accounting: TicketPeriod, pages: [Page]) {
        self.period = period
        self.accounting = accounting
        self.pages = pages
    }

    public func page(_ kind: YearReviewPageKind) -> Page? { pages.first { $0.kind == kind } }

    public var intro: Intro? { if case .intro(let value)? = page(.intro) { return value } else { return nil } }
    public var savings: Savings? { if case .savings(let value)? = page(.savings) { return value } else { return nil } }
    public var distance: Distance? { if case .distance(let value)? = page(.distance) { return value } else { return nil } }
    public var favoriteRoute: FavoriteRoute? { if case .favoriteRoute(let value)? = page(.favoriteRoute) { return value } else { return nil } }
    public var rhythm: Rhythm? { if case .rhythm(let value)? = page(.rhythm) { return value } else { return nil } }
    public var onTheRoad: OnTheRoad? { if case .onTheRoad(let value)? = page(.onTheRoad) { return value } else { return nil } }
    public var purpose: Purpose? { if case .purpose(let value)? = page(.purpose) { return value } else { return nil } }
    public var climate: Climate? { if case .climate(let value)? = page(.climate) { return value } else { return nil } }
    public var finale: Finale? { if case .finale(let value)? = page(.finale) { return value } else { return nil } }

    // MARK: Make

    /// Builds the story of `period`.
    ///
    /// - `trips`: all live trips (any superset of the period works; the period's trips are picked here).
    /// - `tickets`: all ticket periods – a calendar year needs them for its pro-rata cost and its break-even day.
    /// - `car`: `CarComparison.compare` over `YearReviewPeriods.accountingPeriod(for:)` with the same trips (the app's
    ///   `WorkCarCalc.result`); nil skips the climate page.
    /// - `stations`: station lookup for the reference distance; nil skips the comparison, the page stays.
    public static func make(trips allTrips: [TripRecord], tickets: [TicketPeriod], car: CarComparisonResult?, period: YearReviewPeriod,
                            now: Date = Date(), stations: ((String) -> Station?)? = nil, calendar: Calendar = .vienna) -> YearReview {
        let accounting = YearReviewPeriods.accountingPeriod(for: period, tickets: tickets, now: now, calendar: calendar)
        let trips = allTrips.filter { period.contains($0.date) }
        guard !trips.isEmpty else { return YearReview(period: period, accounting: accounting, pages: []) }

        let summary = SavingsCalculator.summary(ticket: accounting, trips: trips, now: now, calendar: calendar)
        let honest = CategoryStats.honestBalance(ticket: accounting, trips: trips)
        let records = StatsAggregator.records(trips, now: now, calendar: calendar)
        var pages: [Page] = []

        pages.append(.intro(Intro(ticketName: ticketName(period: period, accounting: accounting, tickets: tickets),
                                  tripCount: summary.tripCount, travelDays: summary.travelDays)))

        let breakEven = breakEvenDay(period: period, tickets: tickets, trips: allTrips, calendar: calendar)
        pages.append(.savings(Savings(ticketCost: accounting.price, totalValue: summary.totalValue, realValue: honest.realSavings,
                                      extraValue: honest.extraValue, inducedTripCount: honest.inducedTripCount,
                                      tripCount: summary.tripCount, breakEvenDate: breakEven?.date,
                                      breakEvenTicketName: breakEven?.ticketName, costIsPartial: period.kind == .calendarYear)))

        if summary.distanceKm > 0 {
            let reference = stations.flatMap { ReferenceDistances.compare(km: summary.distanceKm, stations: $0) }
            pages.append(.distance(Distance(km: summary.distanceKm, legCount: summary.legCount, reference: reference)))
        }

        let routes = StatsAggregator.topRoutes(trips, limit: 3)
        if let top = routes.first, top.trips >= minFavoriteRouteTrips {
            pages.append(.favoriteRoute(FavoriteRoute(top: top, runnersUp: Array(routes.dropFirst()))))
        }

        if summary.tripCount >= minRhythmTrips {
            let weekdays = StatsAggregator.weekdays(trips, calendar: calendar)
            let busiest = weekdays.filter { $0.trips > 0 }
                .max { ($0.trips, $0.value, -$0.weekday) < ($1.trips, $1.value, -$1.weekday) }
            let best = records.bestMonth.flatMap { $0.value > 0 ? $0 : nil }
            pages.append(.rhythm(Rhythm(months: StatsAggregator.months(trips, in: accounting, calendar: calendar), bestMonth: best,
                                        weekdays: weekdays, busiestWeekday: busiest, longestStreakDays: records.longestStreakDays,
                                        travelDays: summary.travelDays)))
        }

        let states = FederalState.allCases.filter { $0 != .foreign && records.statesVisited.contains($0.rawValue) }
        if !states.isEmpty || records.longestTrip != nil {
            pages.append(.onTheRoad(OnTheRoad(states: states, longestTrip: records.longestTrip, mostValuableTrip: records.mostValuableTrip,
                                              uniqueStations: records.uniqueStations)))
        }

        let categorised = trips.filter { $0.category != nil }
        if JourneySummary.tripCount(categorised) >= minPurposeTrips {
            // `CategoryStats.buckets` sorts by value; this page says "am meisten gefahren", so it ranks by trips.
            let order = TripCategory.allCases
            let buckets = CategoryStats.buckets(trips).filter { !$0.isUncategorized }.sorted { a, b in
                if a.trips != b.trips { return a.trips > b.trips }
                if abs(a.value - b.value) > 0.004 { return a.value > b.value }
                return (a.category.flatMap { order.firstIndex(of: $0) } ?? order.count) < (b.category.flatMap { order.firstIndex(of: $0) } ?? order.count)
            }
            pages.append(.purpose(Purpose(buckets: buckets, categorisedTrips: JourneySummary.tripCount(categorised),
                                          totalTrips: summary.tripCount)))
        }

        if let car, car.co2SavedKg >= minClimateKg {
            pages.append(.climate(Climate(co2SavedKg: car.co2SavedKg, co2CarKg: car.co2CarKg, co2TransitKg: car.co2TransitKg,
                                          carRoadKm: car.roadKm)))
        }

        pages.append(.finale(Finale(tripCount: summary.tripCount, distanceKm: summary.distanceKm, totalValue: summary.totalValue,
                                    net: summary.totalValue - accounting.price, hasTicketCost: accounting.price > 0.005,
                                    co2SavedKg: car.flatMap { $0.co2SavedKg >= minClimateKg ? $0.co2SavedKg : nil })))
        return YearReview(period: period, accounting: accounting, pages: pages)
    }

    // MARK: Helpers

    /// "KlimaTicket Ö Klassik": the ticket of a ticket period, or the ticket that covered most of the calendar year.
    private static func ticketName(period: YearReviewPeriod, accounting: TicketPeriod, tickets: [TicketPeriod]) -> String? {
        if period.kind == .ticket { return accounting.name }
        return accounting.price > 0.005 ? accounting.name : nil
    }

    /// The first day inside the period on which a ticket of the period paid off – like `SavingsCalculator` over all trips
    /// of that ticket (the day Statistik and the Übersicht call "Rentiert seit"). A ticket whose price is 0 (the employer
    /// pays) never "pays off".
    static func breakEvenDay(period: YearReviewPeriod, tickets: [TicketPeriod], trips: [TripRecord],
                             calendar: Calendar) -> (date: Date, ticketName: String)? {
        let candidates: [TicketPeriod]
        if period.kind == .ticket, let ticket = period.ticket {
            candidates = [ticket]
        } else {
            candidates = tickets.filter { $0.start <= period.end && $0.end >= period.start }
        }
        var best: (date: Date, ticketName: String)?
        for ticket in candidates where ticket.price > 0.005 {
            var running = 0.0
            let own = trips.filter { ticket.contains($0.date) }.sorted { $0.date < $1.date }
            for trip in own {
                running += trip.totalValue
                guard running >= ticket.price else { continue }
                if period.contains(trip.date), best == nil || trip.date < best!.date { best = (trip.date, ticket.name) }
                break
            }
        }
        return best
    }
}
