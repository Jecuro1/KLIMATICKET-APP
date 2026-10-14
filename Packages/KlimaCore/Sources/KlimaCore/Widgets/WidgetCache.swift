import Foundation

// The cache the app writes for the widgets (docs/WIDGETS.md). Widgets only read it: they never make a network call, and
// the app writes the live parts only while the user has granted live data. Every type is plain Codable with a version;
// fields added later are optional, so older caches keep decoding.

/// Keys of the App Group defaults (`AppGroup.defaults`).
public enum WidgetCacheKey {
    /// `WidgetConsent` mirrored from the app's live consent.
    public static let consent = "widgets.consent.v1"
    /// `WidgetConnectionCache`: upcoming connections per favourite route.
    public static let connections = "widgets.connections.v1"
    /// `WidgetDepartureCache`: upcoming departures per station.
    public static let departures = "widgets.departures.v1"
    /// `WidgetDisruptionCache`: disruptions that affect the lines the user rides.
    public static let disruptions = "widgets.disruptions.v1"
    /// `WidgetStationList`: the stations the widgets can choose from (written by the app, never by a widget).
    public static let stations = "widgets.stations.v1"
    /// Mirror of the live follow the app runs: `true` while a train is followed (the Live-verfolgen control reads it).
    public static let liveFollowActive = "widgets.liveFollow.active.v1"
    /// Request of the Live-verfolgen control for the app: `true` = start, `false` = stop. The app consumes and clears it.
    public static let liveFollowRequest = "widgets.liveFollow.request.v1"
}

/// Whether the user allowed live data (docs/OEBB_LIVE.md §E4). Undecided and declined keep every live cache empty.
public enum WidgetConsent: String, Codable, Sendable, Equatable {
    case undecided, granted, declined
}

/// Anything a widget lists by its due time (realtime when known, else the plan).
public protocol WidgetTimed: Sendable {
    var departureTime: Date { get }
    var isCancelled: Bool { get }
}

/// One departure of a station board.
public struct WidgetDeparture: Codable, Sendable, Hashable, Identifiable, WidgetTimed {
    public var id: String
    public var planned: Date
    /// Only present when the operator delivers realtime; equal to `planned` when on time.
    public var realtime: Date?
    /// "RJX 19960", "S 4", "Bus 750".
    public var lineName: String
    /// SF Symbol of the transport mode.
    public var modeSymbol: String
    public var direction: String?
    /// The effective platform, e.g. "Gl. 3" or "Steig 5".
    public var platform: String?
    public var platformChanged: Bool
    public var isCancelled: Bool

    public init(id: String, planned: Date, realtime: Date? = nil, lineName: String, modeSymbol: String,
                direction: String? = nil, platform: String? = nil, platformChanged: Bool = false, isCancelled: Bool = false) {
        self.id = id
        self.planned = planned
        self.realtime = realtime
        self.lineName = lineName
        self.modeSymbol = modeSymbol
        self.direction = direction
        self.platform = platform
        self.platformChanged = platformChanged
        self.isCancelled = isCancelled
    }

    public var departureTime: Date { realtime ?? planned }

    /// Minutes late (negative when early); nil without realtime.
    public var delayMinutes: Int? {
        guard let realtime else { return nil }
        return Int((realtime.timeIntervalSince(planned) / 60).rounded())
    }
}

/// The next connection of a favourite route: first departure, final arrival, changes and the first ride's details.
public struct WidgetConnection: Codable, Sendable, Hashable, Identifiable, WidgetTimed {
    public var id: String
    public var planned: Date
    public var realtime: Date?
    /// Effective arrival at the last stop.
    public var arrival: Date?
    public var changes: Int
    public var durationMinutes: Int?
    public var fromName: String
    public var toName: String
    public var lineName: String
    public var modeSymbol: String
    public var direction: String?
    /// The effective platform of the first departure, e.g. "Gl. 3".
    public var platform: String?
    public var platformChanged: Bool
    public var isCancelled: Bool
    /// SF Symbols of the equipment of the train itself (WLAN, Bordrestaurant, WC …). Not the station's.
    public var trainAttributes: [String]

    public init(id: String, planned: Date, realtime: Date? = nil, arrival: Date? = nil, changes: Int = 0,
                durationMinutes: Int? = nil, fromName: String, toName: String, lineName: String, modeSymbol: String,
                direction: String? = nil, platform: String? = nil, platformChanged: Bool = false, isCancelled: Bool = false,
                trainAttributes: [String] = []) {
        self.id = id
        self.planned = planned
        self.realtime = realtime
        self.arrival = arrival
        self.changes = changes
        self.durationMinutes = durationMinutes
        self.fromName = fromName
        self.toName = toName
        self.lineName = lineName
        self.modeSymbol = modeSymbol
        self.direction = direction
        self.platform = platform
        self.platformChanged = platformChanged
        self.isCancelled = isCancelled
        self.trainAttributes = trainAttributes
    }

    public var departureTime: Date { realtime ?? planned }

    public var delayMinutes: Int? {
        guard let realtime else { return nil }
        return Int((realtime.timeIntervalSince(planned) / 60).rounded())
    }
}

/// Upcoming connections per favourite route (key: the favourite's id as `uuidString`).
public struct WidgetConnectionCache: Codable, Sendable, Equatable {
    public var version: Int
    public var fetchedAt: Date
    public var routes: [String: [WidgetConnection]]

    public init(fetchedAt: Date, routes: [String: [WidgetConnection]]) {
        self.version = 1
        self.fetchedAt = fetchedAt
        self.routes = routes
    }
}

/// Upcoming departures per station (key: the station id).
public struct WidgetDepartureCache: Codable, Sendable, Equatable {
    public var version: Int
    public var fetchedAt: Date
    public var stations: [String: [WidgetDeparture]]

    public init(fetchedAt: Date, stations: [String: [WidgetDeparture]]) {
        self.version = 1
        self.fetchedAt = fetchedAt
        self.stations = stations
    }
}

/// A disruption (HIM message) that names one of the lines the user rides.
public struct WidgetDisruption: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    /// Shortened text of the message.
    public var summary: String
    /// The affected lines that the user follows, e.g. "S 4".
    public var lines: [String]
    public var validFrom: Date?
    public var validUntil: Date?

    public init(id: String, title: String, summary: String, lines: [String], validFrom: Date? = nil, validUntil: Date? = nil) {
        self.id = id
        self.title = title
        self.summary = summary
        self.lines = lines
        self.validFrom = validFrom
        self.validUntil = validUntil
    }
}

/// Disruptions for the followed lines (`lines`), as of `fetchedAt`.
public struct WidgetDisruptionCache: Codable, Sendable, Equatable {
    public var version: Int
    public var fetchedAt: Date
    public var lines: [String]
    public var items: [WidgetDisruption]

    public init(fetchedAt: Date, lines: [String], items: [WidgetDisruption]) {
        self.version = 1
        self.fetchedAt = fetchedAt
        self.lines = lines
        self.items = items
    }
}

/// A station the Abfahrten widget can show. `facilities`: Bike+Ride, Park+Ride and barrier-free access from the place data.
/// Lifts and toilets are not in the data and are therefore not listed (docs/WIDGETS.md §3.1).
public struct WidgetStation: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var isHome: Bool
    public var facilities: [WidgetFacility]

    public init(id: String, name: String, isHome: Bool = false, facilities: [WidgetFacility] = []) {
        self.id = id
        self.name = name
        self.isHome = isHome
        self.facilities = facilities
    }
}

/// The stations the user can pick for the widgets (home station, favourite stations), at most `maxCount`.
public struct WidgetStationList: Codable, Sendable, Equatable {
    public static let maxCount = 10

    public var version: Int
    public var updatedAt: Date
    public var stations: [WidgetStation]

    public init(updatedAt: Date, stations: [WidgetStation]) {
        self.version = 1
        self.updatedAt = updatedAt
        self.stations = Array(stations.prefix(Self.maxCount))
    }
}
