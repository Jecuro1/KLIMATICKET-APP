import Foundation

/// CO₂ estimate of a connection from the Umweltbundesamt per-passenger-km factors (`EmissionFactors`), per ride leg.
/// Walks and transfers inside a station emit nothing here. Distances come from the polyline, else from the stop coordinates,
/// else from the straight line between the ends (with the rail detour), so the figure is an estimate, not a measurement.
public enum PlannerEmissions {
    /// Distance of one ride leg in km, nil when the leg has no coordinates at all.
    public static func rideDistanceKm(_ leg: Leg) -> Double? {
        guard leg.kind == .ride else { return nil }
        if let line = leg.polyline, line.count >= 2 { return length(line) }
        let stops = leg.stopovers.compactMap(\.location.coordinate)
        if stops.count >= 2 { return length(stops) }
        guard let a = leg.origin.coordinate, let b = leg.destination.coordinate else { return nil }
        return FareModel.fallback.railDistance(fromStraightLineKm: a.distanceKm(to: b))
    }

    /// Estimated CO₂ of the whole connection in kg. nil when a ride leg has no coordinates (no honest number then).
    /// A connection without ride legs (walk only) is 0 kg.
    public static func co2Kg(_ journey: Journey, factors: EmissionFactors = .fallback) -> Double? {
        var total = 0.0
        for leg in journey.rideLegs {
            guard let km = rideDistanceKm(leg) else { return nil }
            total += km * factors.grams(for: leg.line?.mode ?? .other) / 1000
        }
        return total
    }

    static func length(_ points: [GeoPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0.0) { $0 + $1.0.distanceKm(to: $1.1) }
    }
}

/// Walking and paging rules of the result list (pure; the app keeps the rows, the network and the consent).
public enum PlannerResults {
    /// Metres on foot in the connection: footpaths and walks with a distance. A change inside a station adds nothing.
    public static func walkMeters(_ journey: Journey) -> Int {
        journey.legs.reduce(0) { $0 + ($1.kind == .ride ? 0 : ($1.walkDistanceMeters ?? 0)) }
    }

    /// Keeps the connections whose walking stays within `maxMeters`. nil = no limit. Walks without a distance count as 0 m.
    public static func withinWalk(_ journeys: [Journey], maxMeters: Int?) -> [Journey] {
        guard let maxMeters else { return journeys }
        return journeys.filter { walkMeters($0) <= maxMeters }
    }

    /// Adds one page of „Früher“ / „Später“ to the list: a connection already listed (same id) stays as it is, the new
    /// ones join, and the list stays in departure order (realtime, else planned). Ties keep their order.
    public static func merge(_ current: [Journey], page: [Journey]) -> [Journey] {
        var seen = Set(current.map(\.id))
        var all = current
        for journey in page where seen.insert(journey.id).inserted { all.append(journey) }
        return all.enumerated().sorted { lhs, rhs in
            let a = lhs.element.departure?.effective ?? .distantPast
            let b = rhs.element.departure?.effective ?? .distantPast
            if a != b { return a < b }
            return lhs.offset < rhs.offset
        }
        .map(\.element)
    }
}

extension PlannerResults {
    /// The sort facts of a connection without a price: departure, duration, changes and CO₂. The app adds the price it shows.
    public static func sortFacts(_ journey: Journey, priceEUR: Double? = nil, factors: EmissionFactors = .fallback) -> ConnectionSortFacts {
        var duration = journey.durationSeconds
        if duration == nil, let start = journey.departure?.effective, let end = journey.arrival?.effective {
            duration = Int(end.timeIntervalSince(start))
        }
        return ConnectionSortFacts(departure: journey.departure?.effective, durationSeconds: duration, changes: journey.changes,
                                   priceEUR: priceEUR, co2Kg: PlannerEmissions.co2Kg(journey, factors: factors))
    }
}
