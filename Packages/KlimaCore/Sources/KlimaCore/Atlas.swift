import Foundation

// "Meine Österreich-Karte": everything the travel map needs, derived purely from trips + the bundled station list.
// Routes are aggregated per station pair (both directions, round trips count as two legs), drawn as gentle,
// deterministic arcs so that routes sharing a corridor fan out instead of overlapping.

// MARK: - Places & routes

/// A station on the travel map. Stations with identical coordinates (e.g. "Wien Hauptbahnhof" as rail station and as
/// U-Bahn stop) merge into one place.
public struct AtlasPlace: Hashable, Sendable, Identifiable {
    /// Coordinate key ("47.12739,10.26699").
    public var id: String
    /// First station ID seen for this place.
    public var stationID: String
    public var name: String
    public var location: GeoPoint
    public var state: FederalState?
    /// Legs (one-way journeys) that start or end here.
    public var visits: Int
    /// Mode with the most legs at this place.
    public var dominantMode: TransportMode
    /// 1 = most visited.
    public var rank: Int

    public var isAbroad: Bool { state == .foreign }

    public init(id: String, stationID: String, name: String, location: GeoPoint, state: FederalState?, visits: Int = 0,
                dominantMode: TransportMode = .train, rank: Int = 0) {
        self.id = id
        self.stationID = stationID
        self.name = name
        self.location = location
        self.state = state
        self.visits = visits
        self.dominantMode = dominantMode
        self.rank = rank
    }
}

/// All trips between two places (both directions), ready to draw.
public struct AtlasRoute: Hashable, Sendable, Identifiable {
    /// "<placeA>|<placeB>" (sorted); with vias "<placeA>|<via>…|<placeB>" in the smaller of both directions.
    public var id: String
    /// Western end of the route.
    public var from: AtlasPlace
    /// Eastern end of the route.
    public var to: AtlasPlace
    /// One-way journeys (a round trip counts twice).
    public var legs: Int
    /// Logged entries (a round trip counts once).
    public var entries: Int
    /// Total regular-fare value of all legs, EUR.
    public var value: Double
    /// Total distance of all legs, km.
    public var distanceKm: Double
    public var dominantMode: TransportMode
    /// Modes used on this route, most legs first.
    public var modes: [TransportMode]
    /// Trip IDs, newest first.
    public var tripIDs: [UUID]
    public var firstDate: Date
    public var lastDate: Date
    /// Great-circle distance between the two places, km.
    public var straightKm: Double
    /// Signed arc bend (apex height ÷ chord length; positive = bulges to the left of west → east, i.e. northwards).
    public var bend: Double
    /// Sampled arc from `from` to `to`.
    public var path: [GeoPoint]
    /// Relative frequency 0…1 (log-scaled), drives line width and opacity.
    public var weight: Double
    /// 1 = most travelled.
    public var rank: Int
    /// Via stops from `from` to `to` (docs/VIA.md); `path` runs through them.
    public var via: [AtlasPlace] = []

    public func touches(_ placeID: String) -> Bool { from.id == placeID || to.id == placeID || via.contains { $0.id == placeID } }
}

/// Trips that cannot be drawn because at least one end has no known coordinates.
public struct AtlasUnmappedRoute: Hashable, Sendable, Identifiable {
    /// Direction-independent route key (TripRecord.routeKey).
    public var id: String
    public var fromName: String
    public var toName: String
    public var mode: TransportMode
    public var legs: Int
    public var entries: Int
    public var value: Double
    /// Trip IDs, newest first.
    public var tripIDs: [UUID]
    /// Name of the end that is known (shown as "nur … bekannt"), nil when neither end is known.
    public var knownPlaceName: String?
}

public enum AtlasCompass: String, CaseIterable, Sendable, Identifiable {
    case north, south, west, east

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .north: "Norden"
        case .south: "Süden"
        case .west: "Westen"
        case .east: "Osten"
        }
    }

    /// "Nördlichster Punkt" …
    public var superlative: String {
        switch self {
        case .north: "Nördlichster Punkt"
        case .south: "Südlichster Punkt"
        case .west: "Westlichster Punkt"
        case .east: "Östlichster Punkt"
        }
    }

    public var symbolName: String {
        switch self {
        case .north: "arrow.up"
        case .south: "arrow.down"
        case .west: "arrow.left"
        case .east: "arrow.right"
        }
    }
}

/// The four outermost places of the travel year.
public struct AtlasExtremes: Hashable, Sendable {
    public var north: AtlasPlace?
    public var south: AtlasPlace?
    public var west: AtlasPlace?
    public var east: AtlasPlace?

    public init(north: AtlasPlace? = nil, south: AtlasPlace? = nil, west: AtlasPlace? = nil, east: AtlasPlace? = nil) {
        self.north = north
        self.south = south
        self.west = west
        self.east = east
    }

    public func place(_ direction: AtlasCompass) -> AtlasPlace? {
        switch direction {
        case .north: north
        case .south: south
        case .west: west
        case .east: east
        }
    }

    public var isEmpty: Bool { north == nil }

    /// Directions in which the place is the outermost one (e.g. `[.north, .east]` for a single Vienna trip),
    /// in compass order. Empty for every other place.
    public func directions(of placeID: String) -> [AtlasCompass] {
        AtlasCompass.allCases.filter { place($0)?.id == placeID }
    }
}

/// Geographic bounding box.
public struct AtlasBounds: Hashable, Sendable {
    public var minLatitude: Double
    public var maxLatitude: Double
    public var minLongitude: Double
    public var maxLongitude: Double

    public init(minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double) {
        self.minLatitude = minLatitude
        self.maxLatitude = maxLatitude
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
    }

    public init?(points: [GeoPoint]) {
        guard let first = points.first else { return nil }
        var b = AtlasBounds(minLatitude: first.latitude, maxLatitude: first.latitude,
                            minLongitude: first.longitude, maxLongitude: first.longitude)
        for p in points.dropFirst() { b.include(p) }
        self = b
    }

    /// Austria's outline (Haugschlag in the north to Deutsch Jahrndorf in the east).
    public static let austria = AtlasBounds(minLatitude: 46.37, maxLatitude: 49.02, minLongitude: 9.53, maxLongitude: 17.16)

    public mutating func include(_ p: GeoPoint) {
        minLatitude = min(minLatitude, p.latitude)
        maxLatitude = max(maxLatitude, p.latitude)
        minLongitude = min(minLongitude, p.longitude)
        maxLongitude = max(maxLongitude, p.longitude)
    }

    public var center: GeoPoint {
        GeoPoint(latitude: (minLatitude + maxLatitude) / 2, longitude: (minLongitude + maxLongitude) / 2)
    }

    public func contains(_ p: GeoPoint) -> Bool {
        p.latitude >= minLatitude && p.latitude <= maxLatitude && p.longitude >= minLongitude && p.longitude <= maxLongitude
    }
}

/// A map region in MapKit terms (center + span in degrees).
public struct AtlasRegion: Hashable, Sendable {
    public var centerLatitude: Double
    public var centerLongitude: Double
    public var latitudeDelta: Double
    public var longitudeDelta: Double

    public init(centerLatitude: Double, centerLongitude: Double, latitudeDelta: Double, longitudeDelta: Double) {
        self.centerLatitude = centerLatitude
        self.centerLongitude = centerLongitude
        self.latitudeDelta = latitudeDelta
        self.longitudeDelta = longitudeDelta
    }

    public var center: GeoPoint { GeoPoint(latitude: centerLatitude, longitude: centerLongitude) }
}

/// Parts of the map view covered by bars or panels (points).
public struct AtlasInsets: Hashable, Sendable {
    public var top: Double
    public var leading: Double
    public var bottom: Double
    public var trailing: Double

    public init(top: Double = 0, leading: Double = 0, bottom: Double = 0, trailing: Double = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public static let zero = AtlasInsets()
}

// MARK: - Summary

/// Everything the map shows for one selection of trips.
public struct AtlasSummary: Sendable {
    /// Most travelled first.
    public var routes: [AtlasRoute]
    /// Most visited first.
    public var places: [AtlasPlace]
    /// Trips without coordinates, most legs first.
    public var unmapped: [AtlasUnmappedRoute]
    /// Austrian federal states touched (never contains `.foreign`).
    public var visitedStates: Set<FederalState>
    public var extremes: AtlasExtremes
    /// Longest single direction (km), across all trips.
    public var longestTrip: TripRecord?
    public var tripCount: Int
    /// Entries drawn as a route.
    public var mappedTripCount: Int
    /// Entries listed as "ohne Kartenposition".
    public var unmappedTripCount: Int
    public var totalValue: Double
    public var totalDistanceKm: Double
    /// Bounds of all places and arcs; nil when nothing can be drawn.
    public var bounds: AtlasBounds?

    public static let empty = AtlasSummary(routes: [], places: [], unmapped: [], visitedStates: [], extremes: AtlasExtremes(),
                                           longestTrip: nil, tripCount: 0, mappedTripCount: 0, unmappedTripCount: 0,
                                           totalValue: 0, totalDistanceKm: 0, bounds: nil)

    public var visitedStateCount: Int { visitedStates.count }
    public var isAllAustria: Bool { visitedStates.count == Atlas.austrianStates.count }
    public var topRoute: AtlasRoute? { routes.first }
    /// One-way journeys without coordinates (a round trip counts twice) – the unit the route rows use.
    public var unmappedLegCount: Int { unmapped.reduce(0) { $0 + $1.legs } }
    /// Places outside Austria (e.g. Gemeinschaftsbahnhöfe like Lindau-Reutin or Buchs SG).
    public var abroadPlaces: [AtlasPlace] { places.filter(\.isAbroad) }

    public func route(id: String) -> AtlasRoute? { routes.first { $0.id == id } }
    public func place(id: String) -> AtlasPlace? { places.first { $0.id == id } }

    /// IDs of the most visited places that get a name label on the map.
    public func labelledPlaceIDs(limit: Int = 5) -> Set<String> { Set(places.prefix(limit).map(\.id)) }
}

// MARK: - Engine

public enum Atlas {
    /// The nine federal states from west to east – reads like the map itself.
    public static let austrianStates: [FederalState] = [
        .vorarlberg, .tirol, .salzburg, .kaernten, .oberoesterreich, .steiermark, .niederoesterreich, .wien, .burgenland,
    ]

    /// Common Austrian abbreviations ("Vbg", "Stmk" …) for compact chips.
    public static func abbreviation(_ state: FederalState) -> String {
        switch state {
        case .vorarlberg: "Vbg"
        case .tirol: "T"
        case .salzburg: "Sbg"
        case .kaernten: "Ktn"
        case .oberoesterreich: "OÖ"
        case .steiermark: "Stmk"
        case .niederoesterreich: "NÖ"
        case .wien: "W"
        case .burgenland: "Bgld"
        case .foreign: "Ausl."
        }
    }

    /// Border stations abroad up to which the KlimaTicket Ö is valid
    /// (data/klimaticket_products.json → products[oe].coverage, AGB Anhang 2).
    public static let borderStations = ["Buchs SG", "St. Margrethen", "Lindau-Reutin", "Passau Hbf", "Simbach/Inn",
                                        "Tarvisio Boscoverde", "Innichen", "Brenner", "Sopron"]

    /// Summary with stations resolved via the station index (with the full stop database once it is attached):
    /// ID first, then exact name/alias, then – for free-text stops from imports or older trips – a confident search hit.
    public static func summarize(_ trips: [TripRecord], stations: StationIndex) -> AtlasSummary {
        summarize(trips) { id, name in
            if let id, let station = stations.station(id: id) { return station }
            return stations.station(named: name) ?? approximateStation(named: name, in: stations)
        }
    }

    /// Best-effort position for a stop name without an exact entry ("Lech" → "Lech am Arlberg Rüfiplatz",
    /// "Innsbruck Congress" → "Innsbruck Congress/Hofburg"): one of the top search hits, accepted only when its words
    /// contain the name's words in order (as word prefixes). A single word must be the first word of the hit's full
    /// name (not of an alias – "Messe-Prater" is an alias of "Wien Messe-Prater") or its municipality, so a bare
    /// "Messe" or "Hauptplatz" never lands in a random city. Only for the map; fares never use it.
    public static func approximateStation(named name: String, in stations: StationIndex) -> Station? {
        let query = words(name)
        guard let head = query.first, query.joined().count >= 3 else { return nil }
        for candidate in stations.search(name, limit: 3) {
            if query.count == 1 {
                if words(candidate.name).first == head || candidate.municipality.map({ words($0) == query }) == true {
                    return candidate
                }
            } else if ([candidate.name] + (candidate.aliases ?? [])).contains(where: { containsInOrder(query, in: words($0)) }) {
                return candidate
            }
        }
        return nil
    }

    static func words(_ text: String) -> [String] {
        StationIndex.normalize(text).split(separator: " ").map(String.init)
    }

    /// Every query word starts one of `words`, in the same order.
    static func containsInOrder(_ query: [String], in words: [String]) -> Bool {
        var start = words.startIndex
        for q in query {
            guard let i = words[start...].firstIndex(where: { $0.hasPrefix(q) }) else { return false }
            start = words.index(after: i)
        }
        return true
    }

    /// Aggregates trips into routes, places, states and extreme points.
    /// - Parameter resolve: maps (stationID, name) to a station with coordinates, or nil.
    public static func summarize(_ trips: [TripRecord], resolve: (String?, String) -> Station?) -> AtlasSummary {
        guard !trips.isEmpty else { return .empty }

        var cache: [String: Station?] = [:]
        func station(_ id: String?, _ name: String) -> Station? {
            let key = "\(id ?? "")|\(name)"
            if let hit = cache[key] { return hit }
            let resolved = resolve(id, name)
            cache[key] = resolved
            return resolved
        }

        var places: [String: AtlasPlace] = [:]
        var placeModeLegs: [String: [TransportMode: Int]] = [:]
        var placeModeValue: [String: [TransportMode: Double]] = [:]
        var routeAcc: [String: RouteAccumulator] = [:]
        var unmappedAcc: [String: UnmappedAccumulator] = [:]
        var states = Set<FederalState>()
        var mapped = 0, unmappedCount = 0
        var totalValue = 0.0, totalKm = 0.0

        func register(_ s: Station, legs: Int, mode: TransportMode, value: Double) -> String {
            let key = placeKey(s)
            if places[key] == nil {
                places[key] = AtlasPlace(id: key, stationID: s.id, name: s.name, location: s.location, state: s.federalState)
            }
            places[key]?.visits += legs
            placeModeLegs[key, default: [:]][mode, default: 0] += legs
            placeModeValue[key, default: [:]][mode, default: 0] += value
            if let st = s.federalState, st != .foreign { states.insert(st) }
            return key
        }

        for trip in trips {
            totalValue += trip.totalValue
            totalKm += trip.totalDistanceKm
            for raw in trip.states {
                if let st = FederalState(rawValue: raw), st != .foreign { states.insert(st) }
            }
            let a = station(trip.fromStationID, trip.fromName)
            let b = station(trip.toStationID, trip.toName)
            let keyA = a.map { register($0, legs: trip.legs, mode: trip.mode, value: trip.totalValue) }
            let keyB = b.map { register($0, legs: trip.legs, mode: trip.mode, value: trip.totalValue) }
            // Via stops are places the trip passed; the route is drawn through them.
            let viaKeys = trip.via.compactMap { station($0.stationID, $0.name) }
                .map { register($0, legs: trip.legs, mode: trip.mode, value: trip.totalValue) }

            if let keyA, let keyB {
                mapped += 1
                guard keyA != keyB else { continue }   // same place: a visit, but nothing to draw
                var stops = [keyA]
                for key in viaKeys where key != stops.last && key != keyB { stops.append(key) }
                stops.append(keyB)
                let reversed = Array(stops.reversed())
                let canonical = stops.joined(separator: "|") <= reversed.joined(separator: "|") ? stops : reversed
                let id = canonical.joined(separator: "|")
                routeAcc[id, default: RouteAccumulator(a: canonical[0], b: canonical[canonical.count - 1],
                                                       via: Array(canonical.dropFirst().dropLast()))].add(trip)
            } else {
                unmappedCount += 1
                let known = a?.name ?? b?.name
                unmappedAcc[trip.routeKey, default: UnmappedAccumulator(fromName: trip.fromName, toName: trip.toName, known: known)]
                    .add(trip)
            }
        }

        // Places: dominant mode + rank.
        var placeList = Array(places.values)
        for i in placeList.indices {
            let id = placeList[i].id
            placeList[i].dominantMode = dominant(placeModeLegs[id] ?? [:], values: placeModeValue[id] ?? [:])
        }
        placeList.sort { ($0.visits, $1.name) > ($1.visits, $0.name) }
        for i in placeList.indices { placeList[i].rank = i + 1 }
        let finalPlaces = Dictionary(uniqueKeysWithValues: placeList.map { ($0.id, $0) })

        // Routes: canonical west → east orientation, rank, weight, arcs with fan-out.
        var routes: [AtlasRoute] = routeAcc.compactMap { id, acc in
            guard var p = finalPlaces[acc.a], var q = finalPlaces[acc.b] else { return nil }
            var via = acc.via.compactMap { finalPlaces[$0] }
            if (q.location.longitude, q.location.latitude) < (p.location.longitude, p.location.latitude) {
                swap(&p, &q)
                via.reverse()
            }
            let modes = acc.modeLegs.sorted { ($0.value, acc.modeValue[$0.key] ?? 0, $1.key.rawValue) > ($1.value, acc.modeValue[$1.key] ?? 0, $0.key.rawValue) }
                .map(\.key)
            return AtlasRoute(id: id, from: p, to: q, legs: acc.legs, entries: acc.entries, value: acc.value,
                              distanceKm: acc.distanceKm, dominantMode: modes.first ?? .train, modes: modes,
                              tripIDs: acc.trips.sorted { $0.date > $1.date }.map(\.id),
                              firstDate: acc.firstDate, lastDate: acc.lastDate,
                              straightKm: p.location.distanceKm(to: q.location), bend: 0, path: [], weight: 0, rank: 0, via: via)
        }
        routes.sort { ($0.legs, $0.value, $1.id) > ($1.legs, $1.value, $0.id) }
        let maxLegs = routes.first?.legs ?? 1
        for i in routes.indices {
            routes[i].rank = i + 1
            routes[i].weight = weight(legs: routes[i].legs, maxLegs: maxLegs)
            let fan = routes[..<i].filter { nearParallel(routes[i], $0) }.count
            let magnitude = baseBend(chordKm: routes[i].straightKm) + fanStep(chordKm: routes[i].straightKm) * Double(fan / 2)
            routes[i].bend = fan % 2 == 1 ? -magnitude : magnitude
            routes[i].path = routes[i].via.isEmpty
                ? arc(from: routes[i].from.location, to: routes[i].to.location, bend: routes[i].bend,
                      samples: sampleCount(chordKm: routes[i].straightKm))
                : path(through: [routes[i].from.location] + routes[i].via.map(\.location) + [routes[i].to.location],
                       bendSign: routes[i].bend < 0 ? -1 : 1)
        }

        // Unmapped.
        let unmapped = unmappedAcc.map { key, acc in
            AtlasUnmappedRoute(id: key, fromName: acc.fromName, toName: acc.toName,
                               mode: dominant(acc.modeLegs, values: acc.modeValue), legs: acc.legs, entries: acc.entries,
                               value: acc.value, tripIDs: acc.trips.sorted { $0.date > $1.date }.map(\.id), knownPlaceName: acc.known)
        }
        .sorted { ($0.legs, $0.value, $1.id) > ($1.legs, $1.value, $0.id) }

        // Bounds over places and arcs (arcs bulge beyond their end points).
        var bounds = AtlasBounds(points: placeList.map(\.location))
        if bounds != nil {
            for r in routes { for p in r.path { bounds?.include(p) } }
        }

        return AtlasSummary(routes: routes, places: placeList, unmapped: unmapped, visitedStates: states,
                            extremes: extremes(of: placeList),
                            longestTrip: trips.max { ($0.distanceKm, $0.date) < ($1.distanceKm, $1.date) },
                            tripCount: trips.count, mappedTripCount: mapped, unmappedTripCount: unmappedCount,
                            totalValue: totalValue, totalDistanceKm: totalKm, bounds: bounds)
    }

    // MARK: Geometry

    /// Stable place key from coordinates (merges e.g. rail + U-Bahn "Wien Hauptbahnhof").
    public static func placeKey(_ station: Station) -> String {
        String(format: "%.4f,%.4f", station.lat, station.lon)
    }

    /// Relative frequency, log-scaled so that one commute route doesn't drown everything else.
    public static func weight(legs: Int, maxLegs: Int) -> Double {
        guard maxLegs > 1 else { return 0.6 }
        let w = log(Double(1 + max(legs, 0))) / log(Double(1 + maxLegs))
        return min(max(w, 0), 1)
    }

    /// Apex height ÷ chord: short hops curve a little more, long routes stay elegant and flat.
    public static func baseBend(chordKm: Double) -> Double {
        let raw = 0.20 - 0.035 * log2(max(chordKm, 1) / 25)
        return min(max(raw, 0.07), 0.24)
    }

    /// Extra bend per fan-out step; long routes need less (their different lengths already keep them apart).
    public static func fanStep(chordKm: Double) -> Double {
        0.08 * min(max(120 / max(chordKm, 1), 0.3), 1)
    }

    static func sampleCount(chordKm: Double) -> Int {
        min(max(Int(chordKm / 5), 16), 72)
    }

    /// A route with via stops: one gentle arc per leg (flatter than a direct route, so the line visibly passes the stops),
    /// joined at the stops.
    public static func path(through stops: [GeoPoint], bendSign: Double = 1) -> [GeoPoint] {
        guard stops.count >= 2 else { return stops }
        var points: [GeoPoint] = [stops[0]]
        for (a, b) in zip(stops, stops.dropFirst()) {
            let chord = a.distanceKm(to: b)
            let leg = arc(from: a, to: b, bend: bendSign * baseBend(chordKm: chord) * 0.5, samples: max(sampleCount(chordKm: chord) / 2, 8))
            points.append(contentsOf: leg.dropFirst())
        }
        return points
    }

    /// Quadratic Bézier arc between two points in a local equirectangular projection, sampled into `samples + 1` points.
    /// `bend` is the apex height relative to the chord; positive bends to the left of a → b.
    public static func arc(from a: GeoPoint, to b: GeoPoint, bend: Double, samples: Int = 32) -> [GeoPoint] {
        let n = max(samples, 2)
        let k = cos((a.latitude + b.latitude) / 2 * .pi / 180)
        let ax = a.longitude * k, ay = a.latitude
        let bx = b.longitude * k, by = b.latitude
        let dx = bx - ax, dy = by - ay
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 1e-9 else { return [a, b] }
        // Left normal of a → b; control point twice the apex height away from the chord midpoint.
        let nx = -dy / length, ny = dx / length
        let cx = (ax + bx) / 2 + nx * 2 * bend * length
        let cy = (ay + by) / 2 + ny * 2 * bend * length
        var points: [GeoPoint] = []
        points.reserveCapacity(n + 1)
        for i in 0...n {
            let t = Double(i) / Double(n)
            let u = 1 - t
            let x = u * u * ax + 2 * u * t * cx + t * t * bx
            let y = u * u * ay + 2 * u * t * cy + t * t * by
            points.append(GeoPoint(latitude: y, longitude: x / k))
        }
        points[0] = a
        points[n] = b
        return points
    }

    /// Two routes run alongside each other when they share an end (within 4 km) and leave it in nearly the same direction.
    static func nearParallel(_ r: AtlasRoute, _ s: AtlasRoute) -> Bool {
        let pairs: [(GeoPoint, GeoPoint, GeoPoint, GeoPoint)] = [
            (r.from.location, r.to.location, s.from.location, s.to.location),
            (r.from.location, r.to.location, s.to.location, s.from.location),
            (r.to.location, r.from.location, s.from.location, s.to.location),
            (r.to.location, r.from.location, s.to.location, s.from.location),
        ]
        for (rShared, rOther, sShared, sOther) in pairs where rShared.distanceKm(to: sShared) <= 4 {
            let diff = abs(angleDifference(bearing(rShared, rOther), bearing(sShared, sOther)))
            if diff < 15 { return true }
        }
        return false
    }

    /// Planar bearing in degrees (0 = east, counter-clockwise) in the local projection.
    static func bearing(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let k = cos((a.latitude + b.latitude) / 2 * .pi / 180)
        return atan2(b.latitude - a.latitude, (b.longitude - a.longitude) * k) * 180 / .pi
    }

    static func angleDifference(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    static func extremes(of places: [AtlasPlace]) -> AtlasExtremes {
        // Ties resolve by name so the result is stable.
        AtlasExtremes(
            north: places.max { ($0.location.latitude, $1.name) < ($1.location.latitude, $0.name) },
            south: places.min { ($0.location.latitude, $0.name) < ($1.location.latitude, $1.name) },
            west: places.min { ($0.location.longitude, $0.name) < ($1.location.longitude, $1.name) },
            east: places.max { ($0.location.longitude, $1.name) < ($1.location.longitude, $0.name) }
        )
    }

    static func dominant(_ legs: [TransportMode: Int], values: [TransportMode: Double]) -> TransportMode {
        legs.max { ($0.value, values[$0.key] ?? 0, $1.key.rawValue) < ($1.value, values[$1.key] ?? 0, $0.key.rawValue) }?.key ?? .train
    }

    // MARK: Viewport

    /// Region that shows `bounds` inside the visible part of a map view (`insets` = areas covered by bars/panels),
    /// in Web-Mercator so the aspect ratio matches the view exactly.
    public static func region(fitting bounds: AtlasBounds, width: Double, height: Double, insets: AtlasInsets = .zero,
                              padding: Double = 0.1, minimumSpanKm: Double = 8) -> AtlasRegion {
        let w = max(width, 1), h = max(height, 1)
        let x0 = radians(bounds.minLongitude), x1 = radians(bounds.maxLongitude)
        let y0 = mercatorY(bounds.minLatitude), y1 = mercatorY(bounds.maxLatitude)
        let midLat = radians(bounds.center.latitude)
        let minSpan = minimumSpanKm / (6371.0088 * max(cos(midLat), 0.1))
        let spanX = max(x1 - x0, minSpan), spanY = max(y1 - y0, minSpan)
        let visibleW = max(w - insets.leading - insets.trailing, w * 0.25)
        let visibleH = max(h - insets.top - insets.bottom, h * 0.25)
        let scale = max(spanX / visibleW, spanY / visibleH) * (1 + 2 * padding)   // radians per point
        // Center of the visible band relative to the view center (screen y grows downwards, mercator y upwards).
        let dx = (insets.leading - insets.trailing) / 2
        let dy = (insets.top - insets.bottom) / 2
        let centerX = (x0 + x1) / 2 - dx * scale
        let centerY = (y0 + y1) / 2 + dy * scale
        let top = inverseMercatorY(centerY + scale * h / 2)
        let bottom = inverseMercatorY(centerY - scale * h / 2)
        return AtlasRegion(centerLatitude: (top + bottom) / 2, centerLongitude: degrees(centerX),
                           latitudeDelta: top - bottom, longitudeDelta: degrees(scale * w))
    }

    /// Position of a coordinate in a view of `width` × `height` points showing `region` (north up, Web-Mercator).
    public static func project(_ point: GeoPoint, in region: AtlasRegion, width: Double, height: Double) -> (x: Double, y: Double) {
        let top = mercatorY(region.centerLatitude + region.latitudeDelta / 2)
        let bottom = mercatorY(region.centerLatitude - region.latitudeDelta / 2)
        let left = region.centerLongitude - region.longitudeDelta / 2
        let x = (point.longitude - left) / max(region.longitudeDelta, 1e-9) * width
        let y = (top - mercatorY(point.latitude)) / max(top - bottom, 1e-12) * height
        return (x, y)
    }

    /// MapKit reports a visible region with the *Mercator* centre (the coordinate in the middle of the view) and the
    /// latitude span top − bottom. Converts it to the arithmetic-centre convention used by `region(fitting:)` / `project`.
    public static func regionFromMapCenter(latitude: Double, longitude: Double, latitudeDelta: Double,
                                           longitudeDelta: Double) -> AtlasRegion {
        let yc = mercatorY(latitude)
        var low = 0.0, high = 3.0
        for _ in 0..<60 {
            let mid = (low + high) / 2
            let span = inverseMercatorY(yc + mid) - inverseMercatorY(yc - mid)
            if span < latitudeDelta { low = mid } else { high = mid }
        }
        let half = (low + high) / 2
        let top = inverseMercatorY(yc + half), bottom = inverseMercatorY(yc - half)
        return AtlasRegion(centerLatitude: (top + bottom) / 2, centerLongitude: longitude,
                           latitudeDelta: top - bottom, longitudeDelta: longitudeDelta)
    }

    static func radians(_ deg: Double) -> Double { deg * .pi / 180 }
    static func degrees(_ rad: Double) -> Double { rad * 180 / .pi }
    static func mercatorY(_ latitude: Double) -> Double { log(tan(.pi / 4 + radians(latitude) / 2)) }
    static func inverseMercatorY(_ y: Double) -> Double { degrees(2 * atan(exp(y)) - .pi / 2) }
}

// MARK: - Accumulators

private struct RouteAccumulator {
    let a: String
    let b: String
    /// Via place keys from `a` to `b`.
    var via: [String] = []
    var legs = 0
    var entries = 0
    var value = 0.0
    var distanceKm = 0.0
    var modeLegs: [TransportMode: Int] = [:]
    var modeValue: [TransportMode: Double] = [:]
    var trips: [(id: UUID, date: Date)] = []
    var firstDate = Date.distantFuture
    var lastDate = Date.distantPast

    init(a: String, b: String, via: [String] = []) {
        self.a = a
        self.b = b
        self.via = via
    }

    mutating func add(_ t: TripRecord) {
        legs += t.legs
        entries += 1
        value += t.totalValue
        distanceKm += t.totalDistanceKm
        modeLegs[t.mode, default: 0] += t.legs
        modeValue[t.mode, default: 0] += t.totalValue
        trips.append((t.id, t.date))
        firstDate = min(firstDate, t.date)
        lastDate = max(lastDate, t.date)
    }
}

private struct UnmappedAccumulator {
    let fromName: String
    let toName: String
    let known: String?
    var legs = 0
    var entries = 0
    var value = 0.0
    var modeLegs: [TransportMode: Int] = [:]
    var modeValue: [TransportMode: Double] = [:]
    var trips: [(id: UUID, date: Date)] = []

    init(fromName: String, toName: String, known: String?) {
        self.fromName = fromName
        self.toName = toName
        self.known = known
    }

    mutating func add(_ t: TripRecord) {
        legs += t.legs
        entries += 1
        value += t.totalValue
        modeLegs[t.mode, default: 0] += t.legs
        modeValue[t.mode, default: 0] += t.totalValue
        trips.append((t.id, t.date))
    }
}
