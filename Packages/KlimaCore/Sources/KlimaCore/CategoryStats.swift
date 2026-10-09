import Foundation

// "Kategorien & ehrliche Bilanz": what the trips were for, and how much of the payoff is money that was really saved.

/// Trips, value and share of one trip purpose ("Wofür du fährst"). `category == nil` collects the uncategorised trips.
public struct CategoryBucket: Hashable, Sendable, Identifiable {
    public var category: TripCategory?
    /// Logged entries (a round trip counts once, like the trip list).
    public var trips: Int
    /// Directions travelled (a round trip counts twice).
    public var legs: Int
    /// Regular-fare value of all entries, EUR.
    public var value: Double
    public var distanceKm: Double
    /// Entries marked "Ohne KlimaTicket wäre ich nicht gefahren".
    public var inducedTrips: Int
    public var inducedValue: Double
    /// Share of the total value (0…1).
    public var valueShare: Double
    /// Share of all entries (0…1).
    public var tripShare: Double

    public var id: String { category?.rawValue ?? CategoryBucket.uncategorizedID }
    public var isUncategorized: Bool { category == nil }

    public static let uncategorizedID = "uncategorized"

    public init(category: TripCategory?, trips: Int = 0, legs: Int = 0, value: Double = 0, distanceKm: Double = 0,
                inducedTrips: Int = 0, inducedValue: Double = 0, valueShare: Double = 0, tripShare: Double = 0) {
        self.category = category
        self.trips = trips
        self.legs = legs
        self.value = value
        self.distanceKm = distanceKm
        self.inducedTrips = inducedTrips
        self.inducedValue = inducedValue
        self.valueShare = valueShare
        self.tripShare = tripShare
    }
}

/// The payoff split into money really saved and extra value ("Ehrliche Bilanz").
///
/// Trips the holder would not have made without the flat-rate ticket (`TripRecord.isInduced`) were never going to be
/// paid for – they are real extra value (new excursions, visits), but no saving. The honest payoff only counts trips
/// that would otherwise have been bought. Research context: according to the BMIMI KlimaTicket report, up to 8 % of
/// KlimaTicket trips would not have been made at all without the ticket.
public struct HonestBalance: Hashable, Sendable {
    /// Up to 8 % of KlimaTicket trips would not have happened without the ticket (BMIMI, KlimaTicket-Report).
    public static let researchInducedShare = 0.08

    public var ticketPrice: Double
    /// Regular-fare value of all trips in the period (the normal payoff basis).
    public var totalValue: Double
    /// Value of the trips that would otherwise have been paid for ("echte Ersparnis").
    public var realSavings: Double
    /// Value of the trips made only because of the ticket ("Mehrwert").
    public var extraValue: Double
    public var tripCount: Int
    public var inducedTripCount: Int

    public init(ticketPrice: Double, totalValue: Double, realSavings: Double, extraValue: Double, tripCount: Int, inducedTripCount: Int) {
        self.ticketPrice = ticketPrice
        self.totalValue = totalValue
        self.realSavings = realSavings
        self.extraValue = extraValue
        self.tripCount = tripCount
        self.inducedTripCount = inducedTripCount
    }

    public var realTripCount: Int { tripCount - inducedTripCount }
    public var hasInducedTrips: Bool { inducedTripCount > 0 }

    private var safePrice: Double { max(ticketPrice, 0.01) }
    /// Normal payoff (all trips) – identical to `SavingsSummary.amortizedFraction`.
    public var amortizedFraction: Double { totalValue / safePrice }
    /// Honest payoff (only trips that would otherwise have been paid for).
    public var honestFraction: Double { realSavings / safePrice }
    /// Percentage points the induced trips add to the normal payoff.
    public var extraFraction: Double { extraValue / safePrice }

    public var isPaidOff: Bool { ticketPrice > 0 && totalValue >= ticketPrice }
    public var isHonestlyPaidOff: Bool { ticketPrice > 0 && realSavings >= ticketPrice }
    /// Real savings minus the ticket price (positive = money really saved).
    public var honestNet: Double { realSavings - ticketPrice }
    public var remainingHonest: Double { max(0, ticketPrice - realSavings) }

    /// Share of the logged value that is extra value (0…1).
    public var inducedValueShare: Double { totalValue > 0 ? extraValue / totalValue : 0 }
    /// Share of the logged trips that were induced (0…1) – comparable with `researchInducedShare`.
    public var inducedTripShare: Double { tripCount > 0 ? Double(inducedTripCount) / Double(tripCount) : 0 }
}

public enum CategoryStats {
    /// One bucket per category that has trips, sorted by value (then trips, then canonical order); the
    /// uncategorised bucket ("Ohne Kategorie") always comes last. Shares are relative to all given trips.
    public static func buckets(_ trips: [TripRecord]) -> [CategoryBucket] {
        guard !trips.isEmpty else { return [] }
        var map: [String: CategoryBucket] = [:]
        // A journey counts once per bucket (docs/JOURNEYS.md); its legs add their values.
        var journeys = JourneyCounter<String>()
        var inducedJourneys = JourneyCounter<String>()
        for trip in trips {
            let key = trip.category?.rawValue ?? CategoryBucket.uncategorizedID
            var bucket = map[key] ?? CategoryBucket(category: trip.category)
            bucket.trips += journeys.count(trip, in: key)
            bucket.legs += trip.legs
            bucket.value += trip.totalValue
            bucket.distanceKm += trip.totalDistanceKm
            if trip.isInduced {
                bucket.inducedTrips += inducedJourneys.count(trip, in: key)
                bucket.inducedValue += trip.totalValue
            }
            map[key] = bucket
        }
        let totalValue = trips.reduce(0) { $0 + $1.totalValue }
        let totalTrips = Double(max(1, JourneySummary.tripCount(trips)))
        let order = TripCategory.allCases
        func rank(_ category: TripCategory?) -> Int { category.flatMap { order.firstIndex(of: $0) } ?? order.count }
        return map.values
            .map { bucket -> CategoryBucket in
                var b = bucket
                b.valueShare = totalValue > 0 ? b.value / totalValue : 0
                b.tripShare = Double(b.trips) / totalTrips
                return b
            }
            .sorted { lhs, rhs in
                if lhs.isUncategorized != rhs.isUncategorized { return rhs.isUncategorized }
                if abs(lhs.value - rhs.value) > 0.004 { return lhs.value > rhs.value }
                if lhs.trips != rhs.trips { return lhs.trips > rhs.trips }
                return rank(lhs.category) < rank(rhs.category)
            }
    }

    /// Honest payoff of a ticket period. Trips outside the period are ignored (like `SavingsCalculator.summary`).
    public static func honestBalance(ticket: TicketPeriod, trips allTrips: [TripRecord]) -> HonestBalance {
        let trips = allTrips.filter { ticket.contains($0.date) }
        var total = 0.0, extra = 0.0
        for trip in trips {
            total += trip.totalValue
            if trip.isInduced { extra += trip.totalValue }
        }
        // Journeys count once (docs/JOURNEYS.md).
        return HonestBalance(ticketPrice: ticket.price, totalValue: total, realSavings: total - extra, extraValue: extra,
                             tripCount: JourneySummary.tripCount(trips),
                             inducedTripCount: JourneySummary.tripCount(trips.filter(\.isInduced)))
    }

    /// Share of the value that is work-related (Arbeitsweg + Dienstreise) – nil when nothing is categorised yet.
    public static func workRelatedValueShare(_ trips: [TripRecord]) -> Double? {
        let categorised = trips.filter { $0.category != nil }
        guard !categorised.isEmpty else { return nil }
        let total = trips.reduce(0) { $0 + $1.totalValue }
        guard total > 0 else { return nil }
        let work = categorised.filter { $0.category?.isWorkRelated == true }.reduce(0) { $0 + $1.totalValue }
        return work / total
    }

    /// The category of the most recent categorised trip on the same route (direction-independent, case-insensitive) –
    /// used to suggest a purpose when the same route is logged again. Trips with `excludingID` (the trip being edited) are skipped.
    public static func suggestedCategory(fromName: String, toName: String, in trips: [TripRecord], excludingID: UUID? = nil) -> TripCategory? {
        let from = fromName.trimmingCharacters(in: .whitespaces)
        let to = toName.trimmingCharacters(in: .whitespaces)
        guard !from.isEmpty, !to.isEmpty else { return nil }
        let key = TripRecord(date: Date(), fromName: from, toName: to, mode: .train, distanceKm: 0, fareEUR: 0).routeKey
        var best: TripRecord?
        for trip in trips where trip.category != nil && trip.id != excludingID && trip.routeKey == key {
            if let current = best, current.date >= trip.date { continue }
            best = trip
        }
        return best?.category
    }
}
