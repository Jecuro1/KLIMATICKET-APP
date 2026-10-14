import Foundation

// Zug-Radar: vehicle positions inside a map rectangle (HAFAS `JourneyGeoPos`, docs/OEBB_LIVE.md §A3.3 + §R1).
// Pure values only. The request is one user-initiated call per refresh; the app pauses it off-screen.

/// Map rectangle in WGS84 degrees.
public struct RadarBox: Sendable, Hashable, Codable {
    public var north: Double
    public var west: Double
    public var south: Double
    public var east: Double

    public init(north: Double, west: Double, south: Double, east: Double) {
        self.north = north
        self.west = west
        self.south = south
        self.east = east
    }

    /// Austria with a small margin (the initial map region).
    public static let austria = RadarBox(north: 49.10, west: 9.45, south: 46.30, east: 17.25)

    /// Finite, in range and non-degenerate (HAFAS rejects north == south and east == west).
    public var isValid: Bool {
        [north, west, south, east].allSatisfy(\.isFinite)
            && abs(north) <= 90 && abs(south) <= 90 && abs(east) <= 180 && abs(west) <= 180
            && north > south && east > west
    }

    /// Box around a point (used when the radar is opened from a trip or a station).
    public static func around(_ center: GeoPoint, halfSpan: Double = 0.6) -> RadarBox {
        RadarBox(north: center.latitude + halfSpan, west: center.longitude - halfSpan,
                 south: center.latitude - halfSpan, east: center.longitude + halfSpan)
    }

    /// Centre of the box (map camera target).
    public var center: GeoPoint {
        GeoPoint(latitude: (north + south) / 2, longitude: (east + west) / 2)
    }
}

public struct RadarQuery: Sendable, Hashable {
    public var box: RadarBox
    /// Point in time the positions are computed for (the app passes "now").
    public var when: Date
    /// Product filter (`jnyFltrL` PROD). Default: rail only, the radar's first view.
    public var products: ProductMask
    /// `maxJny`; HAFAS answers at most 256 vehicles.
    public var maxVehicles: Int
    /// `perSize` in seconds: how far ahead the frames reach.
    public var durationSeconds: Int
    /// Number of interpolated frames (`perStep` = duration / frames).
    public var frames: Int

    public init(box: RadarBox = .austria, when: Date, products: ProductMask = .rail, maxVehicles: Int = 256,
                durationSeconds: Int = 30, frames: Int = 3) {
        self.box = box
        self.when = when
        self.products = products
        self.maxVehicles = maxVehicles
        self.durationSeconds = durationSeconds
        self.frames = frames
    }
}

/// One train, bus or tram on the map. `stopovers` is the whole run in HAFAS order (`stopL`), so the UI can show the
/// next stops and the planned route; the live state of each stop lives in `Stopover.arrival/departure`.
public struct RadarVehicle: Sendable, Hashable, Identifiable {
    public var tripID: String
    public var line: Line?
    public var direction: String?
    public var coordinate: GeoPoint
    public var stopovers: [Stopover]
    /// `isCncl`: the whole run is cancelled (partial cancellations are not shown on the radar).
    public var isCancelled: Bool

    public var id: String { tripID }

    public init(tripID: String, line: Line? = nil, direction: String? = nil, coordinate: GeoPoint, stopovers: [Stopover] = [],
                isCancelled: Bool = false) {
        self.tripID = tripID
        self.line = line
        self.direction = direction
        self.coordinate = coordinate
        self.stopovers = stopovers
        self.isCancelled = isCancelled
    }
}

public struct RadarSnapshot: Sendable, Hashable {
    public var vehicles: [RadarVehicle]
    /// `planrtTS` – when the realtime data behind the positions was last updated.
    public var realtimeUpdatedAt: Date?

    public init(vehicles: [RadarVehicle] = [], realtimeUpdatedAt: Date? = nil) {
        self.vehicles = vehicles
        self.realtimeUpdatedAt = realtimeUpdatedAt
    }

    public static let empty = RadarSnapshot()
}

/// Radar provider. `HafasClient` is the production implementation; demo mode uses an in-memory one.
public protocol RadarService: Sendable {
    func radar(_ query: RadarQuery) async throws -> RadarSnapshot
}
