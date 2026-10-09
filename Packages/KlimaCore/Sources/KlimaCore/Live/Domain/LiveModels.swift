import Foundation

// CONTRACT (Step 0) – owned by WP-A after the contracts commit.
// Provider-neutral domain model of the live journey planner. All types are value types, Codable (persisted in
// saved journeys / Live Activity snapshots), Sendable and Hashable. Times are absolute `Date`s (HAFAS local times are
// converted with their explicit TZ offsets, see SPEC §A3.4); display always uses `Calendar.vienna`.

// MARK: - Products

/// ÖBB HAFAS product-class bitmask (`prodL[].cls`, `pCls`, `jnyFltrL PROD value`). VERIFIED-LIVE (SPEC §A3.4, §A3.6).
/// Do NOT use for VAO responses – VAO uses a different bit table.
public struct ProductMask: OptionSet, Codable, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let highSpeed = ProductMask(rawValue: 1)        // RJX, RJ, ICE
    public static let railReplacement = ProductMask(rawValue: 2)  // SEV
    public static let intercity = ProductMask(rawValue: 4)        // IC, EC, IR
    public static let night = ProductMask(rawValue: 8)            // NJ, EN
    public static let regional = ProductMask(rawValue: 16)        // REX, R, CJX
    public static let suburban = ProductMask(rawValue: 32)        // S-Bahn
    public static let bus = ProductMask(rawValue: 64)             // Bus, Postbus, O-Bus, VAL
    public static let ship = ProductMask(rawValue: 128)
    public static let subway = ProductMask(rawValue: 256)         // U-Bahn
    public static let tram = ProductMask(rawValue: 512)
    public static let coach = ProductMask(rawValue: 1024)         // Flixbus, RegioJet, Slovak Lines – not KlimaTicket
    public static let onDemand = ProductMask(rawValue: 2048)      // AST, cable cars
    public static let westbahn = ProductMask(rawValue: 4096)      // WESTbahn

    public static let all = ProductMask(rawValue: 8191)
    /// 4157 = 1|4|8|16|32|4096
    public static let rail: ProductMask = [.highSpeed, .intercity, .night, .regional, .suburban, .westbahn]
    /// Everything except ship, long-distance coach and on-demand/cable car (planner filter "Nur mit KlimaTicket gültig").
    public static let klimaTicket = ProductMask(rawValue: 8191 & ~(128 | 1024 | 2048))
}

// MARK: - Locations

public struct Location: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable { case station = "S", address = "A", poi = "P" }

    /// Opaque HAFAS location id – send it back verbatim (only `A=…@L=…@` is needed for stations).
    public var lid: String
    public var kind: Kind
    /// HAFAS extId (EVA for rail stations, 6-digit for bus stops, meta ids like 1290401). Also the shop's station `number`.
    public var extId: String?
    public var name: String
    public var coordinate: GeoPoint?
    /// Products serving this stop (`pCls`).
    public var products: ProductMask
    /// Meta station grouping several stops ("Wien Hbf (U)").
    public var isMeta: Bool
    /// LocGeoPos distance in metres.
    public var distanceMeters: Int?
    /// ISO country code lower-cased ("at", "de", "it") from `countryCodeL[0]`; missing on ~30 % of objects.
    public var countryCode: String?
    /// `globalIdL type U` – 7-digit UIC code (hint only for mapping to app stations).
    public var uicCode: String?
    /// Minimum transfer time at this stop in seconds (`chgTime`).
    public var minTransferSeconds: Int?

    public var id: String { lid }

    public init(lid: String, kind: Kind = .station, extId: String? = nil, name: String, coordinate: GeoPoint? = nil,
                products: ProductMask = [], isMeta: Bool = false, distanceMeters: Int? = nil, countryCode: String? = nil,
                uicCode: String? = nil, minTransferSeconds: Int? = nil) {
        self.lid = lid
        self.kind = kind
        self.extId = extId
        self.name = name
        self.coordinate = coordinate
        self.products = products
        self.isMeta = isMeta
        self.distanceMeters = distanceMeters
        self.countryCode = countryCode
        self.uicCode = uicCode
        self.minTransferSeconds = minTransferSeconds
    }

    /// Minimal station reference from an extId (`A=1@L=<extId>@`).
    public static func station(extId: String, name: String) -> Location {
        Location(lid: "A=1@L=\(extId)@", kind: .station, extId: extId, name: name)
    }
}

// MARK: - Stop events

public struct Platform: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        /// HAFAS "PL" – rail track ("Gl.")
        case track
        /// HAFAS "ST" – bus/tram bay ("Steig")
        case stand
        case unknown
    }

    public var text: String
    public var kind: Kind

    public init(text: String, kind: Kind = .unknown) {
        self.text = text
        self.kind = kind
    }
}

public struct StopEvent: Codable, Sendable, Hashable {
    public enum Prognosis: String, Codable, Sendable { case prognosed, reported, other }

    public var planned: Date?
    /// Present only when the operator delivers realtime; equal to `planned` when on time.
    public var realtime: Date?
    public var plannedPlatform: Platform?
    public var realtimePlatform: Platform?
    public var isCancelled: Bool
    public var prognosis: Prognosis?
    /// HAFAS flag dPlatfCh/aPlatfCh.
    public var platformChangeFlag: Bool

    public init(planned: Date? = nil, realtime: Date? = nil, plannedPlatform: Platform? = nil, realtimePlatform: Platform? = nil,
                isCancelled: Bool = false, prognosis: Prognosis? = nil, platformChangeFlag: Bool = false) {
        self.planned = planned
        self.realtime = realtime
        self.plannedPlatform = plannedPlatform
        self.realtimePlatform = realtimePlatform
        self.isCancelled = isCancelled
        self.prognosis = prognosis
        self.platformChangeFlag = platformChangeFlag
    }

    public var effective: Date? { realtime ?? planned }
    public var hasRealtime: Bool { realtime != nil }
    /// realtime − planned in seconds (nil without realtime).
    public var delaySeconds: Int? {
        guard let planned, let realtime else { return nil }
        return Int(realtime.timeIntervalSince(planned).rounded())
    }
    public var platform: Platform? { realtimePlatform ?? plannedPlatform }
    public var platformChanged: Bool {
        if platformChangeFlag { return true }
        guard let p = plannedPlatform?.text, let r = realtimePlatform?.text else { return false }
        return p != r
    }
}

public struct Stopover: Codable, Sendable, Hashable {
    public var location: Location
    public var arrival: StopEvent?
    public var departure: StopEvent?
    /// Position in the full run (`idx`) – matches `Leg` boundaries from TripSearch.
    public var index: Int?
    public var isAdditional: Bool
    /// dInS == false && aOutS == false
    public var passesWithoutStop: Bool
    public var isBorder: Bool
    public var remarks: [Remark]

    public init(location: Location, arrival: StopEvent? = nil, departure: StopEvent? = nil, index: Int? = nil,
                isAdditional: Bool = false, passesWithoutStop: Bool = false, isBorder: Bool = false, remarks: [Remark] = []) {
        self.location = location
        self.arrival = arrival
        self.departure = departure
        self.index = index
        self.isAdditional = isAdditional
        self.passesWithoutStop = passesWithoutStop
        self.isBorder = isBorder
        self.remarks = remarks
    }
}

// MARK: - Lines & remarks

public struct Line: Codable, Sendable, Hashable {
    /// Display name: "RJX 19960" (category + train number for long distance), else `nameS` ("Bus 750", "S 4", "U6").
    public var name: String
    /// `prodL.name` verbatim ("REX 51 (Zug-Nr. 1628)", "RJX19960") – used by coverage regexes.
    public var fullName: String?
    /// `prodCtx.catOut` trimmed ("RJX", "S", "Bus", "O-Bus", "Tram", "U", "WB", "NJ").
    public var category: String?
    /// `prodCtx.catOutS` ("RJX", "s", "obu", "str", "VAL", "FBM").
    public var categoryShort: String?
    /// `prodCtx.catOutL` ("railjet xpress", "WESTbahn", "Vienna Airport Bus").
    public var categoryLong: String?
    /// `prodCtx.line` ("750", "5", "U6") – nil for long-distance trains.
    public var lineNumber: String?
    /// `prodCtx.num` (train number / internal run number).
    public var trainNumber: String?
    /// `prodCtx.lineId` ("vvt-1-270", "vor-21-U6", "at:obb:vor|CJX5:").
    public var lineId: String?
    /// `prodCtx.admin` ("81____" ÖBB, "3236__" WESTbahn, "43LAFL" Flixbus).
    public var admin: String?
    /// `opL[oprX].name`. ÖBB trains say "Nahreisezug" (data quirk).
    public var operatorName: String?
    /// `cls` (0 when absent).
    public var productClass: Int
    public var mode: TransportMode

    public init(name: String, fullName: String? = nil, category: String? = nil, categoryShort: String? = nil, categoryLong: String? = nil,
                lineNumber: String? = nil, trainNumber: String? = nil, lineId: String? = nil, admin: String? = nil,
                operatorName: String? = nil, productClass: Int = 0, mode: TransportMode = .other) {
        self.name = name
        self.fullName = fullName
        self.category = category
        self.categoryShort = categoryShort
        self.categoryLong = categoryLong
        self.lineNumber = lineNumber
        self.trainNumber = trainNumber
        self.lineId = lineId
        self.admin = admin
        self.operatorName = operatorName
        self.productClass = productClass
        self.mode = mode
    }

    public var product: ProductMask { ProductMask(rawValue: productClass) }
    // Plate/title texts ("RJX", "S 4", "T 5", "CJX 1", "U6") are presentation – see `LinePresentation` (WP-C).
}

public struct Remark: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        /// remL type A – attribute (WLAN, Bordrestaurant, Rollstuhl …)
        case attribute
        /// remL type I – info (train name)
        case info
        /// remL type H – hint ("VIA_LOCATION", arrival-date deviation)
        case hint
        /// remL type R – realtime ("Hält nur zum Einsteigen")
        case realtime
        /// remL type M or unknown
        case other
        /// himL – disruption / construction message (HIM)
        case disruption
    }

    public var kind: Kind
    /// remL code ("WV", "BR", "FK", "RO" …) – instance specific; never use for coverage decisions.
    public var code: String?
    /// HIM id (`hid`) – dismissal key for banners.
    public var id: String?
    /// HIM head.
    public var title: String?
    /// remL txtN or HIM text, HTML stripped (<br> → newline, entities decoded).
    public var text: String
    public var priority: Int?
    public var validFrom: Date?
    public var validUntil: Date?
    public var modifiedAt: Date?
    public var affectedLines: [String]

    public init(kind: Kind, code: String? = nil, id: String? = nil, title: String? = nil, text: String, priority: Int? = nil,
                validFrom: Date? = nil, validUntil: Date? = nil, modifiedAt: Date? = nil, affectedLines: [String] = []) {
        self.kind = kind
        self.code = code
        self.id = id
        self.title = title
        self.text = text
        self.priority = priority
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.modifiedAt = modifiedAt
        self.affectedLines = affectedLines
    }
}

// MARK: - Journeys

public struct Leg: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        /// secL type JNY
        case ride
        /// WALK with gis.dist (footpath), also GIS/KISS/DEVI decoded as walk
        case walk
        /// WALK without distance + chg block, or TRSF – change inside a station
        case transfer
    }

    public var id: String
    public var kind: Kind
    public var origin: Location
    public var destination: Location
    public var departure: StopEvent
    public var arrival: StopEvent
    public var line: Line?
    public var direction: String?
    /// HAFAS `jid` – opaque and short-lived; refresh saved journeys via `Journey.refreshToken`.
    public var tripID: String?
    /// Full `stopL` of this leg incl. first and last stop (empty when requested without passlist).
    public var stopovers: [Stopover]
    public var walkDistanceMeters: Int?
    public var walkDurationSeconds: Int?
    public var remarks: [Remark]
    /// Concatenation of all `polyG.polyXL` segments (SPEC §A3.4); nil when not requested.
    public var polyline: [GeoPoint]?
    public var isReachable: Bool?
    public var isCancelled: Bool
    public var isPartiallyCancelled: Bool
    public var currentPosition: GeoPoint?

    public init(id: String, kind: Kind, origin: Location, destination: Location, departure: StopEvent, arrival: StopEvent,
                line: Line? = nil, direction: String? = nil, tripID: String? = nil, stopovers: [Stopover] = [],
                walkDistanceMeters: Int? = nil, walkDurationSeconds: Int? = nil, remarks: [Remark] = [], polyline: [GeoPoint]? = nil,
                isReachable: Bool? = nil, isCancelled: Bool = false, isPartiallyCancelled: Bool = false, currentPosition: GeoPoint? = nil) {
        self.id = id
        self.kind = kind
        self.origin = origin
        self.destination = destination
        self.departure = departure
        self.arrival = arrival
        self.line = line
        self.direction = direction
        self.tripID = tripID
        self.stopovers = stopovers
        self.walkDistanceMeters = walkDistanceMeters
        self.walkDurationSeconds = walkDurationSeconds
        self.remarks = remarks
        self.polyline = polyline
        self.isReachable = isReachable
        self.isCancelled = isCancelled
        self.isPartiallyCancelled = isPartiallyCancelled
        self.currentPosition = currentPosition
    }

    /// Intermediate stops (without first and last).
    public var intermediateStops: [Stopover] { stopovers.count > 2 ? Array(stopovers.dropFirst().dropLast()) : [] }
}

public struct Journey: Codable, Sendable, Hashable, Identifiable {
    public var legs: [Leg]
    /// HAFAS `dur` in seconds (elapsed real time, DST-safe).
    public var durationSeconds: Int?
    public var changes: Int
    /// `recon.ctx` – the only durable handle: Reconstruction refreshes it; persist it with logged trips.
    public var refreshToken: String?
    public var checksum: String?
    /// "täglich", "nicht täglich" (sDaysR) and detail "9. bis 14. Okt 2026" (sDaysI).
    public var serviceDays: String?
    public var serviceDaysDetail: String?
    public var remarks: [Remark]
    /// Realtime alternative ("Fahrtmöglichkeit gemäß aktueller Verkehrslage").
    public var isAlternative: Bool
    /// Base64-decoded `trfRes.extContActionBar.content.content` (or `clickout`) – ÖBB shop deep link; nil for WESTbahn.
    public var shopURL: URL?
    /// `planrtTS` of the response.
    public var realtimeUpdatedAt: Date?

    public init(legs: [Leg], durationSeconds: Int? = nil, changes: Int = 0, refreshToken: String? = nil, checksum: String? = nil,
                serviceDays: String? = nil, serviceDaysDetail: String? = nil, remarks: [Remark] = [], isAlternative: Bool = false,
                shopURL: URL? = nil, realtimeUpdatedAt: Date? = nil) {
        self.legs = legs
        self.durationSeconds = durationSeconds
        self.changes = changes
        self.refreshToken = refreshToken
        self.checksum = checksum
        self.serviceDays = serviceDays
        self.serviceDaysDetail = serviceDaysDetail
        self.remarks = remarks
        self.isAlternative = isAlternative
        self.shopURL = shopURL
        self.realtimeUpdatedAt = realtimeUpdatedAt
    }

    /// Stable across realtime refreshes: planned departure (epoch minutes) + ride-leg trip numbers + destination extId.
    public var id: String {
        let dep = legs.first?.departure.planned.map { String(Int($0.timeIntervalSince1970 / 60)) } ?? "?"
        let rides = rideLegs.map { $0.line?.trainNumber ?? $0.line?.name ?? "?" }.joined(separator: "+")
        return "\(dep)|\(rides)|\(destination?.extId ?? destination?.name ?? "?")"
    }

    public var rideLegs: [Leg] { legs.filter { $0.kind == .ride } }
    public var origin: Location? { legs.first?.origin }
    public var destination: Location? { legs.last?.destination }
    public var departure: StopEvent? { legs.first?.departure }
    public var arrival: StopEvent? { legs.last?.arrival }
}

extension Journey {
    /// True when the journey stops at `location`: a leg boundary or a stopover of a ride leg (not one it passes without
    /// stopping). Matched by extId, else by lid, else by a coordinate within 300 m (meta stations group member stops).
    /// Used to verify via stops (SPEC §A3.3).
    public func passes(_ location: Location) -> Bool {
        func same(_ other: Location) -> Bool {
            if let a = location.extId, let b = other.extId, a == b { return true }
            if !location.lid.isEmpty, location.lid == other.lid { return true }
            if let p = location.coordinate, let q = other.coordinate { return p.distanceKm(to: q) <= 0.3 }
            return false
        }
        for leg in legs {
            if same(leg.origin) || same(leg.destination) { return true }
            if leg.kind == .ride, leg.stopovers.contains(where: { !$0.passesWithoutStop && same($0.location) }) { return true }
        }
        return false
    }
}

public struct JourneyPage: Codable, Sendable, Hashable {
    public var journeys: [Journey]
    /// `outCtxScrB` / `outCtxScrF` – pass to `JourneyQuery.pageContext` for earlier/later results.
    public var earlierContext: String?
    public var laterContext: String?
    public var realtimeUpdatedAt: Date?

    public init(journeys: [Journey], earlierContext: String? = nil, laterContext: String? = nil, realtimeUpdatedAt: Date? = nil) {
        self.journeys = journeys
        self.earlierContext = earlierContext
        self.laterContext = laterContext
        self.realtimeUpdatedAt = realtimeUpdatedAt
    }
}

/// A stop the journey must pass ("Über", HAFAS `viaLocL`). Owner request 2026-10-09: up to two via stops, each with an
/// optional minimum stay (SPEC §A3.3).
public struct ViaStop: Codable, Sendable, Hashable {
    public var location: Location
    /// Minimum dwell at the via stop in minutes (HAFAS `min`); nil = only pass through / change there.
    public var minimumDwellMinutes: Int?

    public init(location: Location, minimumDwellMinutes: Int? = nil) {
        self.location = location
        self.minimumDwellMinutes = minimumDwellMinutes
    }
}

public struct JourneyQuery: Codable, Sendable, Hashable {
    public enum Accessibility: String, Codable, Sendable { case complete = "completeBarrierfree", limited = "limitedBarrierfree" }

    /// The planner offers at most this many via stops (owner requirement); encoders send only the first `maxViaStops`.
    public static let maxViaStops = 2

    public var origin: Location
    public var destination: Location
    /// Via stops in travel order (at most `maxViaStops` are sent). Empty = direct search.
    public var via: [ViaStop]
    /// Departure time, or latest arrival when `isArrival`.
    public var date: Date
    public var isArrival: Bool
    /// nil = any (-1). 0 = direct only.
    public var maxChanges: Int?
    /// nil = HAFAS default (-1).
    public var minTransferMinutes: Int?
    public var products: ProductMask
    public var bikeCarriage: Bool
    public var accessibility: Accessibility?
    public var results: Int
    public var includeStopovers: Bool
    public var includePolyline: Bool
    /// Paging context; when set, `date`/`isArrival` are NOT sent (SPEC §A3.3).
    public var pageContext: String?

    public init(origin: Location, destination: Location, via: [ViaStop] = [], date: Date, isArrival: Bool = false,
                maxChanges: Int? = nil, minTransferMinutes: Int? = nil, products: ProductMask = .all, bikeCarriage: Bool = false,
                accessibility: Accessibility? = nil, results: Int = 5, includeStopovers: Bool = true, includePolyline: Bool = false,
                pageContext: String? = nil) {
        self.origin = origin
        self.destination = destination
        self.via = via
        self.date = date
        self.isArrival = isArrival
        self.maxChanges = maxChanges
        self.minTransferMinutes = minTransferMinutes
        self.products = products
        self.bikeCarriage = bikeCarriage
        self.accessibility = accessibility
        self.results = results
        self.includeStopovers = includeStopovers
        self.includePolyline = includePolyline
        self.pageContext = pageContext
    }

    private enum CodingKeys: String, CodingKey {
        case origin, destination, via, date, isArrival, maxChanges, minTransferMinutes, products, bikeCarriage, accessibility, results,
             includeStopovers, includePolyline, pageContext
    }

    /// Tolerant decoding: `via` may be missing (older saved queries) or a single `Location` (pre-2026-10-09 contract).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        origin = try c.decode(Location.self, forKey: .origin)
        destination = try c.decode(Location.self, forKey: .destination)
        if let list = try? c.decodeIfPresent([ViaStop].self, forKey: .via) {
            via = list
        } else if let single = try? c.decodeIfPresent(Location.self, forKey: .via) {
            via = [ViaStop(location: single)]
        } else {
            via = []
        }
        date = try c.decode(Date.self, forKey: .date)
        isArrival = try c.decodeIfPresent(Bool.self, forKey: .isArrival) ?? false
        maxChanges = try c.decodeIfPresent(Int.self, forKey: .maxChanges)
        minTransferMinutes = try c.decodeIfPresent(Int.self, forKey: .minTransferMinutes)
        products = try c.decodeIfPresent(ProductMask.self, forKey: .products) ?? .all
        bikeCarriage = try c.decodeIfPresent(Bool.self, forKey: .bikeCarriage) ?? false
        accessibility = try c.decodeIfPresent(Accessibility.self, forKey: .accessibility)
        results = try c.decodeIfPresent(Int.self, forKey: .results) ?? 5
        includeStopovers = try c.decodeIfPresent(Bool.self, forKey: .includeStopovers) ?? true
        includePolyline = try c.decodeIfPresent(Bool.self, forKey: .includePolyline) ?? false
        pageContext = try c.decodeIfPresent(String.self, forKey: .pageContext)
    }
}

public struct TripDetails: Codable, Sendable, Hashable {
    public var tripID: String
    public var line: Line?
    public var direction: String?
    public var stopovers: [Stopover]
    public var polyline: [GeoPoint]?
    public var currentPosition: GeoPoint?
    public var remarks: [Remark]
    public var isCancelled: Bool
    public var isPartiallyCancelled: Bool
    public var realtimeUpdatedAt: Date?

    public init(tripID: String, line: Line? = nil, direction: String? = nil, stopovers: [Stopover] = [], polyline: [GeoPoint]? = nil,
                currentPosition: GeoPoint? = nil, remarks: [Remark] = [], isCancelled: Bool = false, isPartiallyCancelled: Bool = false,
                realtimeUpdatedAt: Date? = nil) {
        self.tripID = tripID
        self.line = line
        self.direction = direction
        self.stopovers = stopovers
        self.polyline = polyline
        self.currentPosition = currentPosition
        self.remarks = remarks
        self.isCancelled = isCancelled
        self.isPartiallyCancelled = isPartiallyCancelled
        self.realtimeUpdatedAt = realtimeUpdatedAt
    }
}

public enum BoardKind: String, Codable, Sendable { case departures = "DEP", arrivals = "ARR" }

public struct BoardQuery: Codable, Sendable, Hashable {
    public var station: Location
    public var kind: BoardKind
    public var date: Date
    /// Minutes covered (`dur`).
    public var durationMinutes: Int
    public var maxResults: Int
    public var products: ProductMask

    public init(station: Location, kind: BoardKind = .departures, date: Date, durationMinutes: Int = 60, maxResults: Int = 40,
                products: ProductMask = .all) {
        self.station = station
        self.kind = kind
        self.date = date
        self.durationMinutes = durationMinutes
        self.maxResults = maxResults
        self.products = products
    }
}

public struct BoardEntry: Codable, Sendable, Hashable, Identifiable {
    public var tripID: String
    public var line: Line?
    /// `dirTxt` – the run's final destination, also on arrival boards.
    public var direction: String?
    /// The (member) stop this entry belongs to – meta stations return entries of several stops.
    public var stop: Location
    public var event: StopEvent
    /// Departures: terminus (`prodL[0].tLocX`); arrivals: origin of the run (`prodL[0].fLocX`).
    public var terminusOrOrigin: Location?
    public var remarks: [Remark]
    public var isRedirected: Bool
    public var currentPosition: GeoPoint?

    public init(tripID: String, line: Line? = nil, direction: String? = nil, stop: Location, event: StopEvent,
                terminusOrOrigin: Location? = nil, remarks: [Remark] = [], isRedirected: Bool = false, currentPosition: GeoPoint? = nil) {
        self.tripID = tripID
        self.line = line
        self.direction = direction
        self.stop = stop
        self.event = event
        self.terminusOrOrigin = terminusOrOrigin
        self.remarks = remarks
        self.isRedirected = isRedirected
        self.currentPosition = currentPosition
    }

    public var id: String { "\(tripID)|\(stop.lid)|\(event.planned?.timeIntervalSince1970 ?? 0)" }
}

public struct Board: Codable, Sendable, Hashable {
    public var kind: BoardKind
    /// Sorted by effective time (realtime else planned) – HAFAS order is NOT realtime-sorted.
    public var entries: [BoardEntry]
    public var realtimeUpdatedAt: Date?

    public init(kind: BoardKind, entries: [BoardEntry], realtimeUpdatedAt: Date? = nil) {
        self.kind = kind
        self.entries = entries
        self.realtimeUpdatedAt = realtimeUpdatedAt
    }
}

public struct RemarksQuery: Codable, Sendable, Hashable {
    public var from: Date
    public var to: Date
    public var products: ProductMask?
    public var maxResults: Int

    public init(from: Date, to: Date, products: ProductMask? = nil, maxResults: Int = 30) {
        self.from = from
        self.to = to
        self.products = products
        self.maxResults = maxResults
    }
}

public enum LocationTypes: String, Codable, Sendable { case all = "ALL", stations = "S", addresses = "A", pois = "P", stationsAndPOIs = "SP" }

// MARK: - Service protocol

/// Journey-planner API used by the app. `HafasClient` (WP-A) is the production implementation; the app's demo/screenshot
/// mode and SwiftUI previews use an in-memory implementation built from domain values.
public protocol TimetableService: Sendable {
    func locations(_ query: String, types: LocationTypes, maxResults: Int) async throws -> [Location]
    /// Coordinates are rounded to 3 decimals (≈ 100 m) before they leave the device.
    func nearby(_ point: GeoPoint, maxDistanceMeters: Int, maxResults: Int, products: ProductMask) async throws -> [Location]
    func journeys(_ query: JourneyQuery) async throws -> JourneyPage
    /// One HTTP request, N TripSearch service requests; errors are isolated per element.
    func journeys(batch queries: [JourneyQuery]) async throws -> [Result<JourneyPage, LiveError>]
    func refresh(_ refreshToken: String, includeStopovers: Bool, includePolyline: Bool) async throws -> Journey
    func refresh(batch refreshTokens: [String]) async throws -> [Result<Journey, LiveError>]
    func trip(_ tripID: String, includePolyline: Bool) async throws -> TripDetails
    func board(_ query: BoardQuery) async throws -> Board
    func remarks(_ query: RemarksQuery) async throws -> [Remark]
}
