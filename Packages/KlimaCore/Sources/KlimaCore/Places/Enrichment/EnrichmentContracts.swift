import Foundation

// Step 0 contracts of the stop enrichment (docs/ENRICH_SPEC.md §2.1, §4.2): every public type the work packages share.
// The types are final; behaviour that belongs to a work package is marked with its id:
//   WP-C1 format reader (Places/Format/*, PlaceDataset), WP-C2 enrichment model + PlaceIndex API (Places/Enrichment/*),
//   WP-C3 presentation (Places/Presentation/*), WP-L live departures (Places/Live/*).
// Raw values and bit positions are stable (they are the on-disk values of KBPL v2, §1.8): add cases only at the end.

// MARK: - Lines

/// Transport mode of a line (`LCAT.mode`, META `modes` order).
public enum LineMode: UInt8, Sendable, Hashable, Codable, CaseIterable {
    case other = 0, rail, sBahn, subway, tram, bus, trolleybus, railReplacement, ship, cable, onDemand

    /// The app's coarse mode (icons, trip editor, fares).
    public var transportMode: TransportMode {
        switch self {
        case .rail: return .train
        case .sBahn: return .sBahn
        case .subway: return .metro
        case .tram: return .tram
        case .bus, .trolleybus, .railReplacement, .onDemand: return .bus
        case .ship: return .ferry
        case .cable: return .cableCar
        case .other: return .other
        }
    }
}

/// Verkehrsverbund / network of a line (META `nets`; index 0 = none).
public enum TransitNetwork: String, Sendable, Hashable, Codable, CaseIterable {
    case vor = "VOR", vvst = "VVSt", vkl = "VKL", ooevv = "OÖVV", svv = "SVV", vvt = "VVT", vvv = "VVV", oebb = "ÖBB",
         international = "INT"

    /// Name as text (META `netNames`); never a logo.
    public var displayName: String {
        switch self {
        case .vor: return "Verkehrsverbund Ost-Region"
        case .vvst: return "Verbund Linie (Steiermark)"
        case .vkl: return "Kärntner Linien"
        case .ooevv: return "OÖ Verkehrsverbund"
        case .svv: return "Salzburger Verkehrsverbund"
        case .vvt: return "Verkehrsverbund Tirol"
        case .vvv: return "Verkehrsverbund Vorarlberg"
        case .oebb: return "ÖBB"
        case .international: return "international"
        }
    }
}

/// Line flags (`LCAT.flags`, META `lineFlags` order).
public struct LineFlags: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let ski = LineFlags(rawValue: 1 << 0)
    public static let winter = LineFlags(rawValue: 1 << 1)
    public static let summer = LineFlags(rawValue: 1 << 2)
    public static let night = LineFlags(rawValue: 1 << 3)
    public static let schoolDays = LineFlags(rawValue: 1 << 4)
    /// Never shown (M7).
    public static let schoolDaysUncertain = LineFlags(rawValue: 1 << 5)
    public static let schoolOrSeasonal = LineFlags(rawValue: 1 << 6)
    public static let seasonal = LineFlags(rawValue: 1 << 7)
    public static let onDemand = LineFlags(rawValue: 1 << 8)
    public static let railReplacement = LineFlags(rawValue: 1 << 9)
    /// Old ÖV-GK number, replaced by `successorRef` (M4); never shown.
    public static let superseded = LineFlags(rawValue: 1 << 10)
    /// Never shown (M7).
    public static let skiCandidate = LineFlags(rawValue: 1 << 11)
    public static let trolley = LineFlags(rawValue: 1 << 12)
    public static let school = LineFlags(rawValue: 1 << 13)
}

/// Where a line is known from (`LCAT.sources`; `.live` only at runtime).
public struct LineSources: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let timetable = LineSources(rawValue: 1)
    public static let oevgk = LineSources(rawValue: 2)
    public static let stmk = LineSources(rawValue: 4)
    public static let osm = LineSources(rawValue: 8)
    public static let live = LineSources(rawValue: 16)
}

/// How sure we are that a line serves a stop (`LSTP` entry bits 0–1).
public enum LineConfidence: UInt8, Sendable, Hashable, Codable, Comparable {
    case osmOnly = 1, timetable = 2, live = 3

    public static func < (a: LineConfidence, b: LineConfidence) -> Bool { a.rawValue < b.rawValue }
}

public struct LineTermini: Sendable, Hashable, Codable {
    public var from: String?
    public var to: String?
    /// Set when the build resolved the terminus to a stop (`terminiKind == 2`); display then uses that stop's title.
    public var fromStopID: String?
    public var toStopID: String?

    public init(from: String? = nil, to: String? = nil, fromStopID: String? = nil, toStopID: String? = nil) {
        self.from = from
        self.to = to
        self.fromStopID = fromStopID
        self.toStopID = toStopID
    }
}

/// One line (offline dataset line, synthetic rail category, or a live-only line).
public struct LineRef: Sendable, Hashable, Codable, Identifiable {
    /// "l:<merged index>" for dataset lines (stable within one dataset build), "live:<HAFAS lineId>" for live-only.
    public var id: String
    /// Persistent key across dataset builds: "<net>|<mode>|<ref>" (e.g. "VVV|bus|852"). Store this, never `id`.
    public var key: String
    /// "852", "REX41", "Skibus", "RJ".
    public var ref: String
    public var mode: LineMode
    public var network: TransitNetwork?
    /// Display name ("Postbus"); the legal name is in `operatorLegalName`.
    public var operatorName: String?
    public var operatorLegalName: String?
    /// Route name ("Hungerburgbahn", "Bus 852: Schoppernau <=> Lech").
    public var name: String?
    public var termini: LineTermini?
    public var flags: LineFlags
    /// FederalState raw codes served by the line.
    public var states: [String]
    public var sources: LineSources
    public var successorRef: String?
    /// M6 rail category without a concrete line ("RJX" at St. Anton).
    public var isSynthetic: Bool

    public init(id: String, key: String? = nil, ref: String, mode: LineMode, network: TransitNetwork? = nil,
                operatorName: String? = nil, operatorLegalName: String? = nil, name: String? = nil,
                termini: LineTermini? = nil, flags: LineFlags = [], states: [String] = [], sources: LineSources = [],
                successorRef: String? = nil, isSynthetic: Bool = false) {
        self.id = id
        self.key = key ?? LineRef.persistentKey(network: network, mode: mode, ref: ref)
        self.ref = ref
        self.mode = mode
        self.network = network
        self.operatorName = operatorName
        self.operatorLegalName = operatorLegalName
        self.name = name
        self.termini = termini
        self.flags = flags
        self.states = states
        self.sources = sources
        self.successorRef = successorRef
        self.isSynthetic = isSynthetic
    }

    /// "<net>|<mode>|<ref>" with the META `modes` names ("VVV|bus|852", "|rail|RJX" without network).
    public static func persistentKey(network: TransitNetwork?, mode: LineMode, ref: String) -> String {
        "\(network?.rawValue ?? "")|\(mode.keyName)|\(ref)"
    }

    /// Plate family (§2.5, `LineKind.classify`).
    public var kind: LineKind { LineKind.classify(self, services: []) }
}

extension LineMode {
    /// Name in META `modes` / persistent line keys.
    public var keyName: String {
        switch self {
        case .other: return "other"
        case .rail: return "rail"
        case .sBahn: return "sbahn"
        case .subway: return "subway"
        case .tram: return "tram"
        case .bus: return "bus"
        case .trolleybus: return "trolleybus"
        case .railReplacement: return "sev"
        case .ship: return "ship"
        case .cable: return "cable"
        case .onDemand: return "ondemand"
        }
    }

    public init?(keyName: String) {
        guard let m = LineMode.allCases.first(where: { $0.keyName == keyName }) else { return nil }
        self = m
    }
}

/// A line at one stop (detail list).
public struct StopLine: Sendable, Hashable, Identifiable {
    public var line: LineRef
    /// Headsigns at this stop, ≤ 3, display-cleaned.
    public var directions: [String]
    /// ≤ 3.
    public var nextStopIDs: [String]
    public var confidence: LineConfidence
    public var id: String { line.id }

    public init(line: LineRef, directions: [String] = [], nextStopIDs: [String] = [], confidence: LineConfidence) {
        self.line = line
        self.directions = directions
        self.nextStopIDs = nextStopIDs
        self.confidence = confidence
    }
}

/// Plate family (design `LineKind`). Raw values = BADGE_SPEC §2.1 names; case order = display family order.
public enum LineKind: String, Sendable, Hashable, CaseIterable {
    case fern, nacht, regio, sBahn, uBahn, tram, bus, nachtbus, skibus, wanderbus, rufbus, sev, seilbahn, schiff, sonst

    /// Family order for sorting and the stop detail groups (fern 0 … sonst 14).
    public var familyRank: Int { LineKind.allCases.firstIndex(of: self) ?? LineKind.allCases.count }

    /// German noun for VoiceOver ("Bus 852", "S-Bahn S45").
    public var spokenNoun: String {
        switch self {
        case .fern: return "Fernverkehrszug"
        case .nacht: return "Nachtzug"
        case .regio: return "Regionalzug"
        case .sBahn: return "S-Bahn"
        case .uBahn: return "U-Bahn-Linie"
        case .tram: return "Straßenbahn"
        case .bus: return "Bus"
        case .nachtbus: return "Nachtbus"
        case .skibus: return "Skibus"
        case .wanderbus: return "Wanderbus"
        case .rufbus: return "Rufbus"
        case .sev: return "Schienenersatzverkehr"
        case .seilbahn: return "Seilbahn"
        case .schiff: return "Schiff"
        case .sonst: return "Linie"
        }
    }
}

// MARK: - Tags

/// A tag value with its confidence (60–100) and optional distance in metres.
public struct ScoredTag: Sendable, Hashable {
    public var id: String
    public var confidence: Int
    public var distanceMeters: Int?

    public init(id: String, confidence: Int, distanceMeters: Int? = nil) {
        self.id = id
        self.confidence = confidence
        self.distanceMeters = distanceMeters
    }
}

public enum PlaceType: String, Sendable, Hashable, CaseIterable {
    case trainStation, mainStation, longDistance, nightTrain, sBahn, uBahn, tram, privateRail, railReplacement,
         busStation, ship, cableCar, onDemand, airport, hospital, university, mall, parkAndRide, bikeAndRide
}

public enum PlaceService: String, Sendable, Hashable, CaseIterable {
    case nightBus, skiBus, hikingBus, onDemand, seasonal, airportLink
}

public struct PlaceTypeTag: Sendable, Hashable {
    public var type: PlaceType
    public var confidence: Int
    public var distanceMeters: Int?

    public init(type: PlaceType, confidence: Int, distanceMeters: Int? = nil) {
        self.type = type
        self.confidence = confidence
        self.distanceMeters = distanceMeters
    }
}

/// Nearest lift station (OSM layer).
public struct LiftStation: Sendable, Hashable {
    public enum Role: String, Sendable { case valley, middle, top, unknown }
    public var name: String
    public var role: Role
    /// "gondola", "chair_lift", …
    public var liftType: String?
    public var distanceMeters: Int?
    public var confidence: Int

    public init(name: String, role: Role, liftType: String? = nil, distanceMeters: Int? = nil, confidence: Int) {
        self.name = name
        self.role = role
        self.liftType = liftType
        self.distanceMeters = distanceMeters
        self.confidence = confidence
    }

    /// ⌈d / 80 m/min⌉ (BADGE_SPEC §2.3); nil without a distance.
    public var walkMinutes: Int? {
        guard let d = distanceMeters else { return nil }
        return max(1, Int((Double(max(0, d)) / 80).rounded(.up)))
    }
}

public enum Accessibility: String, Sendable, Hashable { case yes, limited, no }

public struct KlimaTicketValidity: Sendable, Hashable {
    public enum Status: String, Sendable { case valid, check, notIncluded, border }
    public var status: Status
    /// e.g. ["vbg-maximo"]; default = the state's list (META `klimaticket.defaultRegional`).
    public var regionalTicketIDs: [String]
    /// „Übergangsbereich“ (`+id`).
    public var extendedTicketIDs: [String]
    public var reason: String?

    public init(status: Status, regionalTicketIDs: [String] = [], extendedTicketIDs: [String] = [], reason: String? = nil) {
        self.status = status
        self.regionalTicketIDs = regionalTicketIDs
        self.extendedTicketIDs = extendedTicketIDs
        self.reason = reason
    }

    /// KlimaTicket Ö only (no regional default known).
    public static let valid = KlimaTicketValidity(status: .valid)
}

/// Every tag of a stop (official + Gemeinde defaults + OSM layer, M5).
public struct PlaceTags: Sendable, Hashable {
    public var gkz: Int?
    public var bezirk: Int?
    public var wienBezirk: Int?
    /// Sorted by confidence desc.
    public var skiAreas: [ScoredTag]
    /// Only `verified` alliances surface in the UI (E5).
    public var skiAlliances: [String]
    public var glacierSkiArea: String?
    public var regions: [ScoredTag]
    public var landscapes: [ScoredTag]
    public var types: [PlaceTypeTag]
    public var services: [PlaceService]
    public var lift: LiftStation?
    public var accessibility: Accessibility?
    public var klimaTicket: KlimaTicketValidity
    public var nationalPark: ScoredTag?
    public var glacier: ScoredTag?
    public var hut: ScoredTag?
    /// id = target stop id.
    public var railTransfer: ScoredTag?

    public init(gkz: Int? = nil, bezirk: Int? = nil, wienBezirk: Int? = nil, skiAreas: [ScoredTag] = [],
                skiAlliances: [String] = [], glacierSkiArea: String? = nil, regions: [ScoredTag] = [],
                landscapes: [ScoredTag] = [], types: [PlaceTypeTag] = [], services: [PlaceService] = [],
                lift: LiftStation? = nil, accessibility: Accessibility? = nil, klimaTicket: KlimaTicketValidity = .valid,
                nationalPark: ScoredTag? = nil, glacier: ScoredTag? = nil, hut: ScoredTag? = nil,
                railTransfer: ScoredTag? = nil) {
        self.gkz = gkz
        self.bezirk = bezirk
        self.wienBezirk = wienBezirk
        self.skiAreas = skiAreas
        self.skiAlliances = skiAlliances
        self.glacierSkiArea = glacierSkiArea
        self.regions = regions
        self.landscapes = landscapes
        self.types = types
        self.services = services
        self.lift = lift
        self.accessibility = accessibility
        self.klimaTicket = klimaTicket
        self.nationalPark = nationalPark
        self.glacier = glacier
        self.hut = hut
        self.railTransfer = railTransfer
    }

    /// Badge threshold (`display.minConf`).
    public static let badgeMinConfidence = 70
    /// Region chip threshold (BADGE_SPEC §2.4).
    public static let regionMinConfidence = 80

    /// The ski area a badge shows: the first with confidence ≥ 70.
    public var primarySkiArea: ScoredTag? {
        skiAreas.first { $0.confidence >= Self.badgeMinConfidence }
    }

    /// Snowcap on tiles and pins: confidence ≥ 90 (the build gives ≥ 90 only for an area outline, a valley lift
    /// ≤ 400 m or a resort centre ≤ 1.5 km).
    public var showsSnowcap: Bool { (primarySkiArea?.confidence ?? 0) >= 90 }

    public func has(_ type: PlaceType, minConfidence: Int = PlaceTags.badgeMinConfidence) -> Bool {
        types.contains { $0.type == type && $0.confidence >= minConfidence }
    }

    public static let empty = PlaceTags()
}

// MARK: - Lookups

public struct GeoBox: Sendable, Hashable {
    public var minLat: Double
    public var minLon: Double
    public var maxLat: Double
    public var maxLon: Double

    public init(minLat: Double, minLon: Double, maxLat: Double, maxLon: Double) {
        self.minLat = minLat
        self.minLon = minLon
        self.maxLat = maxLat
        self.maxLon = maxLon
    }

    public func contains(_ p: GeoPoint) -> Bool {
        (minLat...maxLat).contains(p.latitude) && (minLon...maxLon).contains(p.longitude)
    }
}

/// Curated (places.bin META) or OSM-only (stops_osm.bin META) ski area.
public struct SkiArea: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable { case area, sector, alliance }
    public enum Glyph: String, Sendable { case peaks3, peaks2, peaks1, glacier }
    public var id: String
    public var name: String
    public var shortName: String?
    public var kind: Kind
    public var parentID: String?
    public var allianceIDs: [String]
    public var resorts: [String]
    public var states: [String]
    public var bbox: GeoBox
    public var glyph: Glyph
    /// SummitHue raw value ("enzian", "gletscher", …).
    public var hue: String
    public var monogram: String
    public var liftCount: Int
    public var stopCount: Int
    public var isOSMOnly: Bool
    public var isVerified: Bool

    public init(id: String, name: String, shortName: String? = nil, kind: Kind = .area, parentID: String? = nil,
                allianceIDs: [String] = [], resorts: [String] = [], states: [String] = [],
                bbox: GeoBox = GeoBox(minLat: 0, minLon: 0, maxLat: 0, maxLon: 0), glyph: Glyph = .peaks2,
                hue: String = "fels", monogram: String = "", liftCount: Int = 0, stopCount: Int = 0,
                isOSMOnly: Bool = false, isVerified: Bool = false) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.kind = kind
        self.parentID = parentID
        self.allianceIDs = allianceIDs
        self.resorts = resorts
        self.states = states
        self.bbox = bbox
        self.glyph = glyph
        self.hue = hue
        self.monogram = monogram
        self.liftCount = liftCount
        self.stopCount = stopCount
        self.isOSMOnly = isOSMOnly
        self.isVerified = isVerified
    }
}

public struct Region: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable { case tourism, landscape }
    public var id: String
    public var name: String
    public var kind: Kind
    public var stopCount: Int

    public init(id: String, name: String, kind: Kind = .tourism, stopCount: Int = 0) {
        self.id = id
        self.name = name
        self.kind = kind
        self.stopCount = stopCount
    }
}

/// Everything the stop detail screen shows (WP-C2 `PlaceIndex.details(for:)`).
public struct StopDetails: Sendable {
    public var place: Place
    /// All lines (M3–M7), display-sorted, superseded replaced.
    public var lines: [StopLine]
    /// M8 subset (compact rows).
    public var compactLines: [LineRef]
    public var tags: PlaceTags
    public var skiArea: SkiArea?
    public var regions: [Region]
    public var bezirkName: String?
    public var wienBezirkName: String?
    /// ≤ 8 within 600 m (map hero).
    public var neighbours: [(place: Place, distanceMeters: Double)]
    /// Resolved KlimaTicket Ö + regional + extended products.
    public var klimaTicketProducts: [(id: String, name: String)]
    /// §1.10.2 footer parts for the layers present.
    public var attribution: [String]
    /// META `build.gtfsValidity` (MVO rule: hide lines after it).
    public var dataValidUntil: Date?

    public init(place: Place, lines: [StopLine] = [], compactLines: [LineRef] = [], tags: PlaceTags = .empty,
                skiArea: SkiArea? = nil, regions: [Region] = [], bezirkName: String? = nil, wienBezirkName: String? = nil,
                neighbours: [(place: Place, distanceMeters: Double)] = [],
                klimaTicketProducts: [(id: String, name: String)] = [], attribution: [String] = [],
                dataValidUntil: Date? = nil) {
        self.place = place
        self.lines = lines
        self.compactLines = compactLines
        self.tags = tags
        self.skiArea = skiArea
        self.regions = regions
        self.bezirkName = bezirkName
        self.wienBezirkName = wienBezirkName
        self.neighbours = neighbours
        self.klimaTicketProducts = klimaTicketProducts
        self.attribution = attribution
        self.dataValidUntil = dataValidUntil
    }
}

/// What the loaded place files contain (WP-C1 fills it from the files, `PlaceIndex.dataInfo`).
public struct PlaceDataInfo: Sendable, Hashable {
    /// KBPL version of places.bin (1 = legacy, 2 = sections).
    public var formatVersion: Int
    public var buildDate: Date?
    /// stops_osm.bin loaded, decoded and its BASE matched places.bin (M1).
    public var hasOSMLayer: Bool
    public var timetableReferenceDays: [String]
    /// Lines in the merged catalogue (official + OSM-only).
    public var lineCount: Int
    /// Stops with at least one line (official or OSM).
    public var stopsWithLines: Int
    /// Why the OSM layer is off ("stops_osm.bin: baseMismatch"), for the app log; nil when loaded or not requested.
    public var osmLayerNote: String?

    public init(formatVersion: Int, buildDate: Date? = nil, hasOSMLayer: Bool = false,
                timetableReferenceDays: [String] = [], lineCount: Int = 0, stopsWithLines: Int = 0,
                osmLayerNote: String? = nil) {
        self.formatVersion = formatVersion
        self.buildDate = buildDate
        self.hasOSMLayer = hasOSMLayer
        self.timetableReferenceDays = timetableReferenceDays
        self.lineCount = lineCount
        self.stopsWithLines = stopsWithLines
        self.osmLayerNote = osmLayerNote
    }
}

// MARK: - Live departures (§4.2; implementation WP-L after OEBB WP-A)

public protocol StopDepartureProviding: Sendable {
    /// One StationBoard (DEP) for the stop, `minutes` ahead. Throws LiveError (OEBB_LIVE contract) on failure.
    func departures(for place: Place, lines: [StopLine], at date: Date, minutes: Int) async throws -> StopDepartures
}

public struct StopDepartures: Sendable {
    /// Sorted by effective time.
    public var entries: [StopDeparture]
    /// Offline lines confirmed (sources ∪ .live) + live-only lines.
    public var observedLines: [StopLine]
    public var realtimeUpdatedAt: Date?

    public init(entries: [StopDeparture] = [], observedLines: [StopLine] = [], realtimeUpdatedAt: Date? = nil) {
        self.entries = entries
        self.observedLines = observedLines
        self.realtimeUpdatedAt = realtimeUpdatedAt
    }
}

public struct StopDeparture: Sendable, Hashable, Identifiable {
    public var id: String
    /// Matched offline line, or a live-only LineRef.
    public var line: LineRef
    /// Display-cleaned dirTxt.
    public var direction: String
    /// Next stop name if known.
    public var via: String?
    public var planned: Date
    public var realtime: Date?
    public var platform: String?
    public var platformChanged: Bool
    public var isCancelled: Bool
    /// Mini Landesmarke when ≠ the stop's state.
    public var destinationState: String?

    public init(id: String, line: LineRef, direction: String, via: String? = nil, planned: Date, realtime: Date? = nil,
                platform: String? = nil, platformChanged: Bool = false, isCancelled: Bool = false,
                destinationState: String? = nil) {
        self.id = id
        self.line = line
        self.direction = direction
        self.via = via
        self.planned = planned
        self.realtime = realtime
        self.platform = platform
        self.platformChanged = platformChanged
        self.isCancelled = isCancelled
        self.destinationState = destinationState
    }

    /// Realtime if known, else planned.
    public var effectiveTime: Date { realtime ?? planned }
}

// MARK: - PlaceIndex API (§2.3) – stubs until WP-C2

// WP-C2 replaces these stubs with the real implementation (Enrichment/*, PlaceIndex.swift) and deletes this block.
// They compile and answer "no enrichment data", so UI work packages can build against the final signatures now.
extension PlaceIndex {
    public var skiAreas: [SkiArea] { [] }
    public func skiArea(id: String) -> SkiArea? { nil }
    public var regions: [Region] { [] }
    public func region(id: String) -> Region? { nil }
    /// Display name of an operator (E4); live names are mapped by `OperatorNames.display`.
    public func operatorName(_ legal: String) -> String { OperatorNames.display(legal) }

    /// Full line list of a stop (detail); place id or legacy id.
    public func stopLines(for placeID: String) -> [StopLine] { [] }
    /// M8 subset for compact rows.
    public func compactLines(for placeID: String) -> [LineRef] { [] }
    public func tags(for placeID: String) -> PlaceTags { .empty }
    public func details(for placeID: String) -> StopDetails? {
        place(id: placeID).map { StopDetails(place: $0) }
    }
    /// Persistent key → current dataset line (first match).
    public func line(key: String) -> LineRef? { nil }
    public func stops(inSkiArea id: String, minConfidence: Int = 70, limit: Int = 500) -> [Place] { [] }
    public func stops(inRegion id: String, limit: Int = 500) -> [Place] { [] }
}
