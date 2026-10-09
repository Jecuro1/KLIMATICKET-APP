import Foundation

/// Journey facts for logging a trip from a connection (SPEC §C3.5): dominant mode, distance, line summary and the
/// covered part of a partially covered journey.
public enum JourneyMetrics {
    /// Mode of the ride leg with the longest (planned) duration; on a tie the „bigger“ mode wins
    /// (train > S-Bahn > U-Bahn > tram > bus > ship > cable car). `.other` without ride legs.
    public static func dominantMode(_ journey: Journey) -> TransportMode {
        var best: (mode: TransportMode, seconds: Double)?
        for leg in journey.rideLegs {
            let mode = leg.line?.mode ?? .other
            let seconds = duration(leg)
            guard let current = best else { best = (mode, seconds); continue }
            if seconds > current.seconds || (seconds == current.seconds && rank(mode) < rank(current.mode)) { best = (mode, seconds) }
        }
        return best?.mode ?? .other
    }

    /// Distance in km, rounded to 0.1:
    /// 1. the polyline lengths when every ride leg has a polyline (plus walks);
    /// 2. else haversines between consecutive stopovers of the ride legs plus walk distances;
    /// 3. else origin → destination as the crow flies × the fare model's rail detour.
    /// nil without coordinates.
    public static func distanceKm(_ journey: Journey, model: FareModel = .fallback) -> Double? {
        let rides = journey.rideLegs
        let walkKm = journey.legs.filter { $0.kind != .ride }.reduce(0.0) { sum, leg in
            if let m = leg.walkDistanceMeters { return sum + Double(m) / 1000 }
            if let line = leg.polyline, line.count >= 2 { return sum + length(line) }
            return sum
        }
        if !rides.isEmpty, rides.allSatisfy({ ($0.polyline?.count ?? 0) >= 2 }) {
            return round1(rides.reduce(0.0) { $0 + length($1.polyline ?? []) } + walkKm)
        }
        let stopLines = rides.map { $0.stopovers.compactMap(\.location.coordinate) }
        if !rides.isEmpty, stopLines.allSatisfy({ $0.count >= 2 }) {
            return round1(stopLines.reduce(0.0) { $0 + length($1) } + walkKm)
        }
        if rides.isEmpty, walkKm > 0 { return round1(walkKm) }
        guard let a = journey.origin?.coordinate, let b = journey.destination?.coordinate else { return nil }
        return round1(model.railDistance(fromStraightLineKm: a.distanceKm(to: b)))
    }

    /// „RJX 19960 · Bus 750“ (line titles of the ride legs).
    public static func lineSummary(_ journey: Journey) -> String {
        LinePresentation.lineSummary(journey.rideLegs.compactMap(\.line))
    }

    /// For a `.partial` journey: journey origin → last covered stop (the Austrian or in-scope part), used to price only
    /// that part (SPEC §E6). nil for every other result or when nothing is covered.
    public static func coveredSegment(_ journey: Journey, coverage: JourneyCoverage) -> (from: Location, to: Location)? {
        guard coverage.overall == .partial, let index = coverage.lastCoveredLegIndex, journey.legs.indices.contains(index),
              let origin = journey.origin else { return nil }
        let leg = journey.legs[index]
        let name = coverage.lastCoveredStopName ?? leg.destination.name
        let candidates = [leg.origin] + leg.stopovers.map(\.location) + [leg.destination]
        guard let last = candidates.first(where: { $0.name == name }) else { return nil }
        if last.lid == origin.lid && last.name == origin.name { return nil }
        return (origin, last)
    }

    // MARK: helpers

    static func duration(_ leg: Leg) -> Double {
        if let a = leg.departure.planned, let b = leg.arrival.planned { return b.timeIntervalSince(a) }
        if let a = leg.departure.effective, let b = leg.arrival.effective { return b.timeIntervalSince(a) }
        return 0
    }

    static func rank(_ mode: TransportMode) -> Int {
        [TransportMode.train, .sBahn, .metro, .tram, .bus, .ferry, .cableCar, .other].firstIndex(of: mode) ?? 99
    }

    static func length(_ points: [GeoPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0.0) { $0 + $1.0.distanceKm(to: $1.1) }
    }

    static func round1(_ km: Double) -> Double { (km * 10).rounded() / 10 }
}
