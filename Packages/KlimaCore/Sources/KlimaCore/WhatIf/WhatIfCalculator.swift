import Foundation

// MARK: - Result types

/// The price of one route of the assumptions mode, per trip (one direction).
public struct WhatIfRouteFare: Hashable, Sendable, Identifiable {
    public enum Status: String, Hashable, Sendable {
        case priced
        /// Start and destination are the same station.
        case sameStation
        /// A station id the bundled data does not know (an old save).
        case unknownStation
        /// The estimator found no usable price.
        case noFare
    }

    public var id: UUID
    public var fromName: String
    public var toName: String
    /// Federal states of the two stations – a regional ticket covers the route only if all of them are its own.
    public var states: Set<String>
    public var status: Status
    public var method: FareEstimate.Method?
    /// Price of one trip in the first month, EUR (0 when not priced).
    public var farePerTrip: Double
    /// Price of one trip in each of the 12 chart months – the fare index (price change by date) can make them differ.
    public var monthlyFare: [Double]
    public var distanceKm: Double

    public var isPriced: Bool { status == .priced }
}

/// One line of the ranking: single tickets or one KlimaTicket product.
public struct WhatIfOption: Hashable, Sendable, Identifiable {
    /// The product id, or "single".
    public var id: String
    public var name: String
    public var isSingle: Bool
    /// The user's own ticket (real-data mode).
    public var isCurrent: Bool
    public var family: TicketFamily?
    /// Federal states of a regional product (empty for KlimaTicket Ö and single tickets).
    public var states: [String]
    /// Ticket price for the start date, including the 1.-Klasse-Upgrade when `upgradePrice` is set (0 for single tickets).
    public var ticketPrice: Double
    /// The 1.-Klasse-Upgrade that is part of `ticketPrice` (KlimaTicket Ö in the 1.-Klasse scenario), else 0.
    public var upgradePrice: Double
    /// Regular fares of the trips the ticket does not cover, per year.
    public var uncoveredYearly: Double
    /// Share (0…1) of the trips the ticket covers.
    public var coveredShare: Double
    /// Cumulative cost after 0…12 months: the ticket price is paid at month 0, the fares of uncovered trips as they occur.
    public var cumulative: [Double]
    /// From this many trips per month on the ticket is cheaper than single tickets (the mix of routes stays the same);
    /// nil for single tickets, when it covers none of the trips or when there are no trips.
    public var breakEvenTripsPerMonth: Int?
    /// The same break-even before rounding up (9,3 trips per month). The screen shows it when the user's own volume already
    /// lies above it, so „ab 10“ never sits next to „du sparst schon bei 9,5“.
    public var breakEvenExact: Double?

    public var yearlyCost: Double { ticketPrice + uncoveredYearly }
}

/// The calculator's answer. `options` is ranked by yearly cost (cheapest first).
public struct WhatIfResult: Hashable, Sendable {
    public enum State: String, Hashable, Sendable {
        /// Assumptions mode without a priced route.
        case needsRoutes
        /// There is nothing to travel: 0 trips per month (or all trips filtered away).
        case noTrips
        case ready
    }

    public var state: State
    /// Single tickets and every compared product, cheapest first (ties: cheaper ticket, then id).
    public var options: [WhatIfOption]
    public var single: WhatIfOption
    /// The cheapest ticket that covers at least a tenth of the trips (`minimumShownCoverage`); nil when there are no trips or
    /// no ticket covers enough of them.
    public var bestTicket: WhatIfOption?
    /// Average trips per month over the 12 months (one trip = one direction).
    public var tripsPerMonth: Double
    public var yearlyTrips: Double
    /// Single tickets minus the best ticket per year: positive = the ticket saves that much, negative = it costs more.
    public var yearlyDelta: Double
    /// Break-even of `bestTicket` against single tickets, in trips per month.
    public var breakEvenTripsPerMonth: Int?
    /// Where the two chart lines cross (0…12 months, interpolated); nil when they do not cross within the year.
    public var crossing: Double?
    /// The month (1…12) at whose end the ticket is first not more expensive than single tickets.
    public var crossingMonth: Int?
    public var routeFares: [WhatIfRouteFare]
    /// The 13 month boundaries of the chart (the first of each month in the Vienna calendar, from the start date's month):
    /// chart position `m` (0…12) is `monthStarts[m]`.
    public var monthStarts: [Date]
    /// `TariffCatalog.updatedAt` of the bundled tariffs ("2026-10-09").
    public var tariffDate: String
    /// The scenario prices 1. Klasse.
    public var includesFirstClass: Bool

    /// The best ticket is cheaper than single tickets by more than a cent.
    public var ticketIsCheaper: Bool { yearlyDelta > 0.005 }
    /// The best ticket costs as much as single tickets (to the cent).
    public var isTie: Bool { bestTicket != nil && abs(yearlyDelta) <= 0.005 }

    /// A ticket that covers less than this share of the trips is not part of the display ranking ("ab 45 Fahrten pro Monat" for
    /// a ticket of another federal state is noise).
    public static let minimumShownCoverage = 0.1

    /// The ranking for display: the cheapest `limit` options that matter (a ticket that covers hardly any of the trips is
    /// pointless), always including single tickets and the user's own ticket.
    public func displayOptions(limit: Int = 4) -> [WhatIfOption] {
        var tickets = 0
        var shown: [WhatIfOption] = []
        for option in options {
            if option.isSingle || option.isCurrent {
                shown.append(option)
                continue
            }
            guard option.coveredShare >= WhatIfResult.minimumShownCoverage, tickets < limit else { continue }
            tickets += 1
            shown.append(option)
        }
        return shown
    }
}

// MARK: - Calculator

/// „Was wäre wenn?“ – which ticket pays off, and what if I travel more or less (docs/WHATIF.md).
///
/// Two modes with one ranking:
/// - **Assumptions** (`evaluate(_:)`): up to three routes with trips per month. Every trip is priced like a single ticket
///   with `FareEstimator` (exact ÖBB table where it knows the relation, else the distance model), for the month it falls in.
/// - **Real data** (`evaluate(_:history:)`): the logged trips, valued with their own fares. Without exclusions, volume 1 and
///   no 1. Klasse the totals equal `TicketComparator.compare` for the same trips, ticket by ticket.
///
/// Tickets are the catalogue's products of the chosen variant (`TicketProduct.price(forStart:)`, regional ones through
/// `covers(states:)`), the same set `TicketComparator` compares. Everything is a model of regular single-ticket prices
/// (no Sparschiene, no Vorteilscard, no promotions): a calculation aid, not advice.
public struct WhatIfCalculator: Sendable {
    public var catalog: TariffCatalog
    public var relations: RelationPriceTable
    public var stations: StationIndex
    public var calendar: Calendar

    public init(catalog: TariffCatalog, relations: RelationPriceTable = .empty, stations: StationIndex,
                calendar: Calendar = .vienna) {
        self.catalog = catalog
        self.relations = relations
        self.stations = stations
        self.calendar = calendar
    }

    private var estimator: FareEstimator { FareEstimator(catalog: catalog, relations: relations) }

    // MARK: Months

    /// The 13 month boundaries of the ticket year: the first day of the start date's month and the 12 months after it.
    public func monthBoundaries(for start: Date) -> [Date] {
        let comps = calendar.dateComponents([.year, .month], from: start)
        let first = calendar.date(from: comps) ?? calendar.startOfDay(for: start)
        return (0...WhatIfLimits.months).map { calendar.date(byAdding: .month, value: $0, to: first) ?? first }
    }

    // MARK: Fares

    /// The per-trip prices of the input's routes (at most three).
    public func routeFares(for input: WhatIfInput) -> [WhatIfRouteFare] {
        let bounds = monthBoundaries(for: input.startDate)
        return input.activeRoutes.map { fare(for: $0, bounds: bounds, startDate: input.startDate) }
    }

    private func fare(for route: WhatIfRoute, bounds: [Date], startDate: Date) -> WhatIfRouteFare {
        func failure(_ status: WhatIfRouteFare.Status, from: Station? = nil, to: Station? = nil) -> WhatIfRouteFare {
            WhatIfRouteFare(id: route.id, fromName: from?.name ?? "", toName: to?.name ?? "",
                            states: Set([from?.state, to?.state].compactMap { $0 }), status: status, method: nil,
                            farePerTrip: 0, monthlyFare: Array(repeating: 0, count: WhatIfLimits.months), distanceKm: 0)
        }
        guard let from = stations.station(id: route.fromStationID), let to = stations.station(id: route.toStationID) else {
            return failure(.unknownStation, from: stations.station(id: route.fromStationID), to: stations.station(id: route.toStationID))
        }
        guard from.id != to.id else { return failure(.sameStation, from: from, to: to) }
        let mode: TransportMode = from.primaryMode == to.primaryMode ? from.primaryMode : .train
        var monthly: [Double] = []
        var first: FareEstimate?
        for m in 0..<WhatIfLimits.months {
            // Prices of the month's middle day: a fare change inside the year (fare index) starts with the month it reaches.
            let mid = bounds[m].addingTimeInterval(bounds[m + 1].timeIntervalSince(bounds[m]) / 2)
            let estimate = estimator.estimate(from: from, to: to, mode: mode, travelClass: route.travelClass, date: mid)
            first = first ?? estimate
            monthly.append(estimate.fareEUR.isFinite ? max(estimate.fareEUR, 0) : 0)
        }
        guard let first, monthly.allSatisfy({ $0 > 0 }) else { return failure(.noFare, from: from, to: to) }
        return WhatIfRouteFare(id: route.id, fromName: from.name, toName: to.name, states: [from.state, to.state],
                               status: .priced, method: first.method, farePerTrip: monthly[0], monthlyFare: monthly,
                               distanceKm: first.distanceKm)
    }

    // MARK: Evaluate

    /// Assumptions mode (`history == nil`): the input's routes. Real-data mode: the history's trips; the input's routes
    /// are ignored, its variant, start date, exclusions, region, class, volume and own ticket apply.
    public func evaluate(_ input: WhatIfInput, history: WhatIfHistory? = nil) -> WhatIfResult {
        let bounds = monthBoundaries(for: input.startDate)
        let months = Array(bounds.prefix(WhatIfLimits.months))
        let excluded = input.validExcludedMonths
        let active = months.map { !excluded.contains(calendar.component(.month, from: $0)) }
        var fares: [WhatIfRouteFare] = []
        var flows: [Flow]
        if let history {
            flows = historyFlows(history, input: input, active: active)
        } else {
            fares = routeFares(for: input)
            flows = routeFlows(input, fares: fares, active: active)
        }
        let hasPricedRoute = history != nil || fares.contains { $0.isPriced }
        return rank(flows: flows, input: input, fares: fares, boundaries: bounds, hasPricedRoute: hasPricedRoute)
    }

    // MARK: Flows

    /// Trips of one kind: the states they touch and, per chart month, how many there are and what they would cost.
    private struct Flow {
        var states: Set<String>
        var firstClass: Bool
        var count: [Double]
        var value: [Double]
    }

    private func passesRegion(_ states: Set<String>, _ input: WhatIfInput) -> Bool {
        guard let region = input.regionFilter else { return true }
        return !states.isEmpty && states.isSubset(of: [region])
    }

    private func routeFlows(_ input: WhatIfInput, fares: [WhatIfRouteFare], active: [Bool]) -> [Flow] {
        var flows: [Flow] = []
        for (route, fare) in zip(input.activeRoutes, fares) where fare.isPriced && passesRegion(fare.states, input) {
            let n = Double(route.clampedTrips)
            guard n > 0 else { continue }
            let count = active.map { $0 ? n : 0 }
            let value = zip(count, fare.monthlyFare).map { $0 * $1 }
            flows.append(Flow(states: fare.states, firstClass: route.travelClass == .first, count: count, value: value))
        }
        return flows
    }

    private func historyFlows(_ history: WhatIfHistory, input: WhatIfInput, active: [Bool]) -> [Flow] {
        let activeMonths = active.filter { $0 }.count
        guard activeMonths > 0 else { return [] }
        let excluded = input.validExcludedMonths
        let scale = input.clampedVolume * max(history.annualizationFactor.isFinite ? history.annualizationFactor : 1, 1)
        let upgrade = catalog.fareModel.firstClassFactor.isFinite ? max(catalog.fareModel.firstClassFactor, 1) : 1
        var groups: [Set<String>: (count: Double, value: Double)] = [:]
        for trip in history.trips {
            if !excluded.isEmpty, excluded.contains(calendar.component(.month, from: trip.date)) { continue }
            guard passesRegion(trip.states, input) else { continue }
            var value = trip.totalValue
            guard value.isFinite, value >= 0 else { continue }
            if input.useFirstClass, !history.firstClassTripIDs.contains(trip.id) { value *= upgrade }
            let entry = groups[trip.states] ?? (0, 0)
            groups[trip.states] = (entry.count + Double(trip.legs), entry.value + value)
        }
        // Spread evenly over the months that have trips (the exclusions were already taken out of the trips).
        return groups.keys.sorted { $0.sorted().joined(separator: ",") < $1.sorted().joined(separator: ",") }.compactMap { states in
            guard let entry = groups[states], entry.count > 0 else { return nil }
            let share = scale / Double(activeMonths)
            return Flow(states: states, firstClass: input.useFirstClass,
                        count: active.map { $0 ? entry.count * share : 0 },
                        value: active.map { $0 ? entry.value * share : 0 })
        }
    }

    // MARK: Ranking

    private func covers(_ product: TicketProduct, _ flow: Flow) -> Bool {
        // Same rule as TicketComparator (no states = only KlimaTicket Ö), plus: regional tickets are 2. Klasse only.
        let byState = flow.states.isEmpty ? product.family == .oe : product.covers(states: flow.states)
        return byState && (!flow.firstClass || product.family == .oe)
    }

    private func rank(flows: [Flow], input: WhatIfInput, fares: [WhatIfRouteFare], boundaries: [Date], hasPricedRoute: Bool) -> WhatIfResult {
        let monthCount = WhatIfLimits.months
        let yearlyTrips = flows.reduce(0.0) { $0 + $1.count.reduce(0, +) }
        let tripsPerMonth = yearlyTrips / Double(monthCount)
        let anyFirstClass = flows.contains { $0.firstClass && $0.count.contains { $0 > 0 } }

        func cumulative(price: Double, flows covered: [Flow]) -> [Double] {
            var points = [price]
            for m in 0..<monthCount { points.append(points[m] + covered.reduce(0) { $0 + $1.value[m] }) }
            return points
        }

        let singleCumulative = cumulative(price: 0, flows: flows)
        let singleYearly = singleCumulative[monthCount]
        let single = WhatIfOption(id: "single", name: "Einzeltickets", isSingle: true, isCurrent: false, family: nil, states: [],
                                  ticketPrice: 0, upgradePrice: 0, uncoveredYearly: singleYearly,
                                  coveredShare: 0, cumulative: singleCumulative, breakEvenTripsPerMonth: nil, breakEvenExact: nil)

        var options = [single]
        for product in catalog.products where (product.variant == input.variant && product.isLocal != true) || product.id == input.currentProductID {
            let uncovered = flows.filter { !covers(product, $0) }
            let upgrade = (anyFirstClass && product.family == .oe)
                ? TicketAddOn.firstClass.listPrice(productID: product.id, variant: product.variant) : 0
            let price = product.price(forStart: input.startDate) + upgrade
            let points = cumulative(price: price, flows: uncovered)
            let coveredCount = flows.filter { covers(product, $0) }.reduce(0.0) { $0 + $1.count.reduce(0, +) }
            // Trips per month at which this ticket costs as much as single tickets: P ÷ (what the covered trips cost per
            // year) is the share of the current volume that is needed, times the current volume.
            let coveredYearly = singleYearly - points[monthCount] + price
            var breakEven: Int?
            var exact: Double?
            if tripsPerMonth > 0, coveredYearly > 0.005, price.isFinite {
                let needed = price / coveredYearly * tripsPerMonth
                if needed.isFinite, needed < 1_000_000 {
                    breakEven = max(Int((needed - 1e-9).rounded(.up)), 1)
                    exact = needed
                }
            }
            options.append(WhatIfOption(id: product.id, name: product.name, isSingle: false,
                                        isCurrent: product.id == input.currentProductID, family: product.family,
                                        states: product.states, ticketPrice: price, upgradePrice: upgrade,
                                        uncoveredYearly: points[monthCount] - price,
                                        coveredShare: yearlyTrips > 0 ? coveredCount / yearlyTrips : 0,
                                        cumulative: points, breakEvenTripsPerMonth: breakEven, breakEvenExact: exact))
        }
        options.sort(by: Self.rankedBefore)
        let single0 = options.first { $0.isSingle } ?? single

        let state: WhatIfResult.State = !hasPricedRoute ? .needsRoutes : (yearlyTrips <= 0 ? .noTrips : .ready)
        let best = state == .ready ? options.first { !$0.isSingle && $0.coveredShare >= WhatIfResult.minimumShownCoverage } : nil
        var crossing: Double?
        var crossingMonth: Int?
        if let best { (crossing, crossingMonth) = Self.crossing(single: single0.cumulative, ticket: best.cumulative) }
        return WhatIfResult(state: state, options: options, single: single0, bestTicket: best, tripsPerMonth: tripsPerMonth,
                            yearlyTrips: yearlyTrips,
                            yearlyDelta: best.map { single0.yearlyCost - $0.yearlyCost } ?? 0,
                            breakEvenTripsPerMonth: best?.breakEvenTripsPerMonth, crossing: crossing, crossingMonth: crossingMonth,
                            routeFares: fares, monthStarts: boundaries, tariffDate: catalog.updatedAt, includesFirstClass: anyFirstClass)
    }

    /// Cheapest first; the same cost (to the cent) – the cheaper ticket, then the id: the order never flickers.
    static func rankedBefore(_ a: WhatIfOption, _ b: WhatIfOption) -> Bool {
        let ca = cents(a.yearlyCost), cb = cents(b.yearlyCost)
        if ca != cb { return ca < cb }
        let pa = cents(a.ticketPrice), pb = cents(b.ticketPrice)
        if pa != pb { return pa < pb }
        return a.id < b.id
    }

    /// Whole cents; non-finite and absurdly large values are clamped (a huge hand-edited fare must not trap the conversion).
    private static func cents(_ value: Double) -> Int {
        value.isFinite ? Int(min(max(value * 100, -1e15), 1e15).rounded()) : Int.max
    }

    /// Where the ticket line meets the single-ticket line: the interpolated position and the first month at whose end the
    /// ticket is not more expensive.
    static func crossing(single: [Double], ticket: [Double]) -> (Double?, Int?) {
        guard single.count == ticket.count, single.count > 1 else { return (nil, nil) }
        for m in 1..<single.count {
            let before = single[m - 1] - ticket[m - 1]
            let after = single[m] - ticket[m]
            if after >= -1e-9, before < -1e-9 {
                let span = after - before
                let position = span > 0 ? Double(m - 1) + (-before) / span : Double(m)
                return (min(max(position, 0), Double(single.count - 1)), m)
            }
        }
        return (nil, nil)
    }
}
