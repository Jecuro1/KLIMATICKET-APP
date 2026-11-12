import Foundation

// Which known stop is a place? The detector accepts a ride only when its start and its end lie within a few hundred
// metres of a station or stop of the bundled data (stations.json, plus the complete place database once attached).

/// A station near a point.
public struct StationMatch: Hashable, Sendable {
    public var station: Station
    public var distanceMeters: Double

    public init(station: Station, distanceMeters: Double) {
        self.station = station
        self.distanceMeters = distanceMeters
    }

    /// A rail or metro station (not a bus stop): the only kind a coarse track can tell apart from a car park.
    public var isRailLike: Bool { StationMatcher.isRailLike(station) }
}

/// Nearby stations of a coordinate. `StationIndex` conforms (every stop once a place index is attached); tests and demo
/// scenes use a fixed list.
public protocol StationLookup: Sendable {
    /// Stations within `meters` of `point`, nearest first, at most `limit`.
    func stations(near point: GeoPoint, withinMeters meters: Double, limit: Int) -> [StationMatch]
}

extension StationIndex: StationLookup {
    public func stations(near point: GeoPoint, withinMeters meters: Double, limit: Int) -> [StationMatch] {
        nearest(to: point, limit: limit, maxKm: meters / 1000)
            .map { StationMatch(station: $0.station, distanceMeters: $0.distanceKm * 1000) }
            .filter { $0.distanceMeters <= meters }
    }
}

/// A plain list of stations (tests, scenes, a small catalogue).
public struct StationList: StationLookup {
    public var stations: [Station]

    public init(_ stations: [Station]) { self.stations = stations }

    public func stations(near point: GeoPoint, withinMeters meters: Double, limit: Int) -> [StationMatch] {
        let hits = stations.compactMap { station -> StationMatch? in
            let d = DetectionGeo.meters(point, station.location)
            return d <= meters ? StationMatch(station: station, distanceMeters: d) : nil
        }
        return Array(hits.sorted { $0.distanceMeters < $1.distanceMeters }.prefix(limit))
    }
}

/// Picks the station a place most likely is. A rail station within reach wins over a bus stop that happens to be nearer:
/// at a main station a dozen stops lie within 100 m, and the ride is the train's.
public struct StationMatcher: Sendable {
    public var lookup: any StationLookup
    /// Largest distance between a place and its station.
    public var maxDistanceMeters: Double

    public init(lookup: any StationLookup, maxDistanceMeters: Double = 500) {
        self.lookup = lookup
        self.maxDistanceMeters = maxDistanceMeters
    }

    /// Rail (heavy rail, S-Bahn) and metro stations; stops of the place database count by their products.
    public static func isRailLike(_ station: Station) -> Bool {
        switch station.kind {
        case .rail, .metro: return true
        case .tramHub: return false
        case .stop:
            if let products = station.products, products != 0 { return PlaceProducts(rawValue: products).isRail || products & PlaceProducts.subway.rawValue != 0 }
            return false
        }
    }

    /// The best station within `maxDistanceMeters` (nil when there is none).
    public func best(near point: GeoPoint) -> StationMatch? { candidates(near: point).first }

    /// All stations within reach, best first: rail-like before others unless the other one is much nearer, then by
    /// distance, then by importance. Used for the edit sheet's "andere Haltestellen in der Nähe".
    public func candidates(near point: GeoPoint, limit: Int = 8) -> [StationMatch] {
        let hits = lookup.stations(near: point, withinMeters: maxDistanceMeters, limit: 40)
        return Array(hits.sorted { rank($0) > rank($1) }.prefix(limit))
    }

    /// Higher is better: closeness (0…1 over the range) plus a bonus for rail-like stations and for important ones.
    private func rank(_ match: StationMatch) -> Double {
        let closeness = 1 - min(match.distanceMeters, maxDistanceMeters) / max(maxDistanceMeters, 1)
        let kind = StationMatcher.isRailLike(match.station) ? 0.6 : 0
        let importance = min(Double(match.station.importance), 10) * 0.02
        return closeness + kind + importance
    }
}
