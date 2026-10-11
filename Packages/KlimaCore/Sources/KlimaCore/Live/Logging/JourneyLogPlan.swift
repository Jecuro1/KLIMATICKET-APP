import Foundation

/// One trip of a logged connection (docs/OEBB_LIVE.md §E6): a ride leg with its own stations, mode, distance, price share
/// and via stops. A planner connection with several ride legs becomes one „Reise mit Etappen“ (docs/JOURNEYS.md), one
/// ride leg a trip of its own.
public struct JourneyLogLeg: Hashable, Sendable {
    public var fromName: String
    public var toName: String
    public var fromStationID: String?
    public var toStationID: String?
    public var mode: TransportMode
    public var distanceKm: Double
    public var fareEUR: Double
    /// Requested via stops this leg passes (docs/VIA.md), in travel order.
    public var via: [TripVia]
    /// Federal states of the leg's stops (app station codes), first appearance first.
    public var states: [String]
    /// „RJX 19910“, „Bus 760“.
    public var lineTitle: String
    public var departure: Date?
    public var arrival: Date?

    public init(fromName: String, toName: String, fromStationID: String? = nil, toStationID: String? = nil, mode: TransportMode,
                distanceKm: Double, fareEUR: Double, via: [TripVia] = [], states: [String] = [], lineTitle: String = "",
                departure: Date? = nil, arrival: Date? = nil) {
        self.fromName = fromName
        self.toName = toName
        self.fromStationID = fromStationID
        self.toStationID = toStationID
        self.mode = mode
        self.distanceKm = distanceKm
        self.fareEUR = fareEUR
        self.via = via
        self.states = states
        self.lineTitle = lineTitle
        self.departure = departure
        self.arrival = arrival
    }
}

/// What logging a connection stores: the legs, the shared date and the totals. Pure and deterministic (no I/O, no clock).
public struct JourneyLogPlan: Hashable, Sendable {
    public var legs: [JourneyLogLeg]
    /// Planned departure of the first ride leg – the date of every leg.
    public var date: Date
    /// Planned arrival of the last logged ride leg.
    public var arrivalAt: Date?
    /// The regular price that was distributed over the legs (the quote's amount).
    public var totalFareEUR: Double
    /// Only the covered part of a partially covered connection is logged and valued (`coverage_rules.json` savingsRule).
    public var isPartial: Bool
    /// Last stop that counts when `isPartial` („Landeck-Zams“).
    public var lastCoveredName: String?
    /// „RJX 19910 · Bus 760“ of the logged legs.
    public var lineSummary: String
    /// `Journey.refreshToken` – refresh handle for „Rückfahrt planen“.
    public var journeyRef: String

    public var isEmpty: Bool { legs.isEmpty }
    public var isJourney: Bool { legs.count > 1 }
    public var totalDistanceKm: Double { legs.reduce(0) { $0 + $1.distanceKm } }

    public init(legs: [JourneyLogLeg], date: Date, arrivalAt: Date? = nil, totalFareEUR: Double, isPartial: Bool = false,
                lastCoveredName: String? = nil, lineSummary: String = "", journeyRef: String = "") {
        self.legs = legs
        self.date = date
        self.arrivalAt = arrivalAt
        self.totalFareEUR = totalFareEUR
        self.isPartial = isPartial
        self.lastCoveredName = lastCoveredName
        self.lineSummary = lineSummary
        self.journeyRef = journeyRef
    }
}

public enum JourneyLogPlanner {
    /// The trips for a planner connection.
    ///
    /// - Ride legs only: walks and changes inside a station are no trips (leading and trailing walks to addresses or POIs
    ///   disappear with them).
    /// - `.partial` coverage: legs after `coverage.lastCoveredLegIndex` are dropped and the last logged leg ends at
    ///   `lastCoveredStopName` (its stops cut there); the quote is expected for that covered part (the planner requests it).
    /// - Price: `quote.amountEUR` is the regular price of everything that is logged. With several legs it is shared by
    ///   distance (cents, the remainder to the longest leg) so the journey adds up to exactly the quoted amount.
    /// - Stations: an app station within reach (`StationLinker.appStation`) gives id and name, else the display name.
    public static func plan(journey: Journey, quote: PriceQuote?, coverage: JourneyCoverage?, via: [ViaStop] = [],
                            stations: StationIndex, model: FareModel = .fallback) -> JourneyLogPlan {
        var rides: [(index: Int, leg: Leg)] = journey.legs.enumerated().filter { $0.element.kind == .ride }.map { ($0.offset, $0.element) }
        var isPartial = false
        var lastCoveredName: String?
        if let coverage, coverage.overall == .partial, let last = coverage.lastCoveredLegIndex {
            isPartial = true
            lastCoveredName = coverage.lastCoveredStopName
            rides = rides.filter { $0.index <= last }
            if let name = coverage.lastCoveredStopName, let tail = rides.last, let trimmed = trim(tail.leg, to: name) {
                rides[rides.count - 1] = (tail.index, trimmed)
            }
        }
        guard let first = rides.first else {
            return JourneyLogPlan(legs: [], date: journey.departure?.planned ?? Date(timeIntervalSince1970: 0), totalFareEUR: 0)
        }
        let date = first.leg.departure.planned ?? first.leg.departure.effective ?? journey.departure?.planned ?? Date(timeIntervalSince1970: 0)
        let viaStops = via.prefix(JourneyQuery.maxViaStops)
        var legs: [JourneyLogLeg] = rides.map { entry in
            let leg = entry.leg
            let from = endpoint(leg.origin, stations: stations), to = endpoint(leg.destination, stations: stations)
            let km = JourneyMetrics.distanceKm(Journey(legs: [leg]), model: model) ?? 0
            let viaHere = viaStops.filter { passes(leg, $0.location) }.map { stop -> TripVia in
                let station = StationLinker.appStation(for: stop.location, in: stations)
                return TripVia(name: station?.name ?? DisplayNames.name(stop.location.name), stationID: station?.id)
            }
            var states: [String] = []
            func add(_ s: String?) { if let s, !s.isEmpty, !states.contains(s) { states.append(s) } }
            add(from.station?.state)
            for stop in leg.stopovers where !stop.passesWithoutStop {
                add(StationLinker.appStation(for: stop.location, in: stations)?.state)
            }
            add(to.station?.state)
            return JourneyLogLeg(fromName: from.name, toName: to.name, fromStationID: from.station?.id, toStationID: to.station?.id,
                                 mode: leg.line?.mode ?? .train, distanceKm: km, fareEUR: 0, via: TripViaCodec.sanitized(Array(viaHere)),
                                 states: states, lineTitle: leg.line.map(LinePresentation.title) ?? "",
                                 departure: leg.departure.planned ?? leg.departure.effective, arrival: leg.arrival.planned ?? leg.arrival.effective)
        }
        let total = max(0, quote?.amountEUR ?? 0)
        let shares = distribute(total, over: legs.map(\.distanceKm))
        for index in legs.indices { legs[index].fareEUR = shares[index] }
        let summary = LinePresentation.lineSummary(rides.compactMap(\.leg.line))
        return JourneyLogPlan(legs: legs, date: date, arrivalAt: legs.last?.arrival, totalFareEUR: total, isPartial: isPartial,
                              lastCoveredName: lastCoveredName, lineSummary: summary, journeyRef: journey.refreshToken ?? "")
    }

    /// Shares `total` by weight in whole cents; the remainder goes to the heaviest entry. Equal shares without weights.
    static func distribute(_ total: Double, over weights: [Double]) -> [Double] {
        guard !weights.isEmpty else { return [] }
        let cents = Int((total * 100).rounded())
        if weights.count == 1 { return [Double(cents) / 100] }
        let sum = weights.reduce(0, +)
        let basis = sum > 0 ? weights : weights.map { _ in 1.0 }
        let basisSum = basis.reduce(0, +)
        var parts = basis.map { Int((Double(cents) * $0 / basisSum).rounded(.down)) }
        let remainder = cents - parts.reduce(0, +)
        if remainder != 0, let heaviest = basis.indices.max(by: { basis[$0] < basis[$1] }) { parts[heaviest] += remainder }
        return parts.map { Double($0) / 100 }
    }

    // MARK: helpers

    private static func endpoint(_ location: Location, stations: StationIndex) -> (name: String, station: Station?) {
        let station = StationLinker.appStation(for: location, in: stations)
        return (station?.name ?? DisplayNames.name(location.name), station)
    }

    /// True when the leg stops at `location` between its ends (the planner's via stops).
    private static func passes(_ leg: Leg, _ location: Location) -> Bool {
        Journey(legs: [leg]).passes(location)
    }

    /// The leg cut at the stop called `name` (display names compared); nil when it has no such stop.
    private static func trim(_ leg: Leg, to name: String) -> Leg? {
        let wanted = DisplayNames.name(name)
        guard let cut = leg.stopovers.firstIndex(where: { DisplayNames.name($0.location.name) == wanted || $0.location.name == name }) else { return nil }
        guard cut < leg.stopovers.count - 1 else { return leg }
        var out = leg
        out.stopovers = Array(leg.stopovers[...cut])
        let stop = leg.stopovers[cut]
        out.destination = stop.location
        out.arrival = stop.arrival ?? stop.departure ?? leg.arrival
        out.polyline = nil
        return out
    }
}
