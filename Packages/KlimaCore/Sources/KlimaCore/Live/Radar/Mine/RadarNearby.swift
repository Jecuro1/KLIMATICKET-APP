import Foundation

// MARK: radar2-radarmine – „In der Nähe“ (docs/RADAR_MINE.md §3): the vehicles the radar already holds around one location fix, with the minutes to
// their next stop. No request of its own: the rows are read from the radar's markers. The fix stays in memory while the panel is open and is
// never stored, logged or sent.

/// A vehicle as the radar draws it now: the vehicle and the coordinate of its marker (an answer's position or the estimate between two).
public struct RadarMineSighting: Sendable, Hashable {
    public var vehicle: RadarVehicle
    public var coordinate: GeoPoint
    public var isEstimate: Bool

    public init(vehicle: RadarVehicle, coordinate: GeoPoint, isEstimate: Bool = false) {
        self.vehicle = vehicle
        self.coordinate = coordinate
        self.isEstimate = isEstimate
    }
}

/// When a vehicle gets to a stop: the time (realtime when known, else planned), whether it is a forecast, its delay, a cancellation.
public struct RadarMineETA: Sendable, Hashable {
    public var time: Date
    public var isRealtime: Bool
    /// realtime − planned in seconds; nil without realtime.
    public var delaySeconds: Int?
    public var isCancelled: Bool

    public init(time: Date, isRealtime: Bool, delaySeconds: Int?, isCancelled: Bool) {
        self.time = time
        self.isRealtime = isRealtime
        self.delaySeconds = delaySeconds
        self.isCancelled = isCancelled
    }

    /// The next stop of a radar vehicle: its arrival there (else its departure). nil without a planned time.
    public init?(stop: Stopover, vehicleCancelled: Bool) {
        guard let event = stop.arrival?.planned != nil ? stop.arrival : stop.departure, let planned = event.planned else { return nil }
        self.init(time: event.realtime ?? planned, isRealtime: event.realtime != nil, delaySeconds: event.delaySeconds,
                  isCancelled: vehicleCancelled || event.isCancelled)
    }

    /// The board's departure of one entry.
    public init?(event: StopEvent) {
        guard let planned = event.planned else { return nil }
        self.init(time: event.realtime ?? planned, isRealtime: event.realtime != nil, delaySeconds: event.delaySeconds,
                  isCancelled: event.isCancelled)
    }

    /// Whole minutes from `now`, rounded up (59 s is „in 1 Min“); 0 or less is „jetzt“.
    public func minutes(from now: Date) -> Int {
        let seconds = time.timeIntervalSince(now)
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int((seconds / 60).rounded(.up))
    }

    /// The delay in whole minutes (rounded); nil without realtime.
    public var delayMinutes: Int? {
        delaySeconds.map { Int((Double($0) / 60).rounded()) }
    }
}

public struct RadarNearbyRow: Sendable, Hashable, Identifiable {
    public var tripID: String
    public var line: Line?
    /// „Bus 13A“.
    public var title: String
    public var direction: String?
    public var distanceKm: Double
    public var nextStop: String
    public var eta: RadarMineETA
    public var isEstimate: Bool
    public var coordinate: GeoPoint

    public var id: String { tripID }
}

public enum RadarNearby {
    /// The radius around the fix.
    public static let radiusKm = 1.5
    /// The view around the fix: about 3 km, so the whole circle is on the map.
    public static let viewSpanKm = 3.0

    /// Every sighting within `radiusKm` of `from` that has a next stop, nearest first (ties by trip id).
    public static func rows(_ sightings: [RadarMineSighting], from: GeoPoint, now: Date, radiusKm: Double = radiusKm) -> [RadarNearbyRow] {
        guard from.latitude.isFinite, from.longitude.isFinite else { return [] }
        return sightings.compactMap { sighting -> RadarNearbyRow? in
            let distance = sighting.coordinate.distanceKm(to: from)
            guard distance.isFinite, distance <= radiusKm,
                  let stop = RadarRun.nextStop(of: sighting.vehicle, now: now),
                  let eta = RadarMineETA(stop: stop, vehicleCancelled: sighting.vehicle.isCancelled) else { return nil }
            let line = sighting.vehicle.line
            return RadarNearbyRow(tripID: sighting.vehicle.tripID, line: line, title: line.map(LinePresentation.title) ?? "Fahrzeug",
                                  direction: sighting.vehicle.direction, distanceKm: distance, nextStop: stop.location.name, eta: eta,
                                  isEstimate: sighting.isEstimate, coordinate: sighting.coordinate)
        }
        .sorted { $0.distanceKm != $1.distanceKm ? $0.distanceKm < $1.distanceKm : $0.tripID < $1.tripID }
    }

    // MARK: radar2-review-radarmine – what the list can honestly say. The rows come from the radar's markers, and those are only the vehicles in
    // the map's view whose tiles have answered. „Die Auskunft kennt im Umkreis von 1,5 km gerade kein Fahrzeug“ is true only when the whole circle
    // is in the view, its tiles have answered and the radar is loading; before, the page said it while the map had moved away from the circle,
    // while the city lane was out of zoom, before the first answer of the new tiles, and with the train layer off or the radar paused.

    /// How much of the circle around the fix the radar's markers cover right now.
    public enum Coverage: Equatable, Sendable {
        /// The whole circle is in view and answered: an empty list means the Auskunft knows no vehicle there.
        case complete
        /// Tiles of the view are still waiting for their first answer.
        case loading
        /// The map no longer shows the whole circle (moved or zoomed in): the list holds only what is in view.
        case offMap
        /// Bus, Bim or U-Bahn are on, but the map is too far out for them.
        case cityOutOfZoom
        /// The radar does not load now (train layer off, no live data, Zeitreise away, Cockpit, Low Power Mode, paused after errors).
        case notLoading
    }

    /// The coverage of the circle around `fix` by the markers of the view `box`. `loads`: the radar asks for tiles now; `pending`: a visible tile
    /// still waits for its first answer.
    public static func coverage(fix: GeoPoint, box: RadarBox, loads: Bool, pending: Bool, cityModesOn: Bool, cityOutOfZoom: Bool,
                                radiusKm: Double = radiusKm) -> Coverage {
        guard loads else { return .notLoading }
        guard circleShown(fix, in: box, radiusKm: radiusKm) else { return .offMap }
        if cityModesOn && cityOutOfZoom { return .cityOutOfZoom }
        return pending ? .loading : .complete
    }

    /// The circle (to 90 % of its radius, so the view MapKit fits around it counts) lies in `box`.
    public static func circleShown(_ fix: GeoPoint, in box: RadarBox, radiusKm: Double = radiusKm) -> Bool {
        guard fix.latitude.isFinite, fix.longitude.isFinite, radiusKm.isFinite, radiusKm >= 0 else { return false }
        let dLat = radiusKm * 0.9 / RadarLanePlan.kmPerDegreeLatitude
        let dLon = radiusKm * 0.9 / (RadarLanePlan.kmPerDegreeLatitude * max(cos(fix.latitude * .pi / 180), 0.01))
        return box.north >= fix.latitude + dLat && box.south <= fix.latitude - dLat
            && box.east >= fix.longitude + dLon && box.west <= fix.longitude - dLon
    }
}
