import Foundation

// Public value types of the place layer (docs/PLACES.md, SUGGEST_SPEC §10).

/// Transport products of a place. Bit values are identical to ÖBB HAFAS `pCls`, so offline records
/// (places.bin) and live LocMatch rows agree without mapping (OEBB_LIVE §A3.6 `ProductMask` uses the same bits).
public struct PlaceProducts: OptionSet, Hashable, Sendable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let highSpeed = PlaceProducts(rawValue: 1)        // RJX, RJ, ICE …
    public static let railReplacement = PlaceProducts(rawValue: 2)  // Schienenersatzverkehr
    public static let interCity = PlaceProducts(rawValue: 4)        // IC, EC, D
    public static let night = PlaceProducts(rawValue: 8)            // NJ, EN
    public static let regional = PlaceProducts(rawValue: 16)        // REX, R, CJX
    public static let suburban = PlaceProducts(rawValue: 32)        // S-Bahn
    public static let bus = PlaceProducts(rawValue: 64)
    public static let ship = PlaceProducts(rawValue: 128)
    public static let subway = PlaceProducts(rawValue: 256)         // U-Bahn
    public static let tram = PlaceProducts(rawValue: 512)
    public static let coach = PlaceProducts(rawValue: 1024)
    public static let onDemandOrCable = PlaceProducts(rawValue: 2048) // Seilbahn, Rufbus/AST
    public static let privateRail = PlaceProducts(rawValue: 4096)   // WESTbahn

    /// Every rail product (heavy rail incl. S-Bahn and WESTbahn).
    public static let rail: PlaceProducts = [.highSpeed, .interCity, .night, .regional, .suburban, .privateRail]
    public static let longDistance: PlaceProducts = [.highSpeed, .interCity, .night]

    public var isRail: Bool { !intersection(.rail).isEmpty }

    /// The mode a trip from/to this place most likely uses (icons, default mode in the trip editor).
    public var primaryMode: TransportMode {
        if !intersection([.highSpeed, .interCity, .night, .regional, .privateRail]).isEmpty { return .train }
        if contains(.suburban) { return .sBahn }
        if contains(.subway) { return .metro }
        if contains(.tram) { return .tram }
        if contains(.ship) { return .ferry }
        if !intersection([.bus, .railReplacement, .coach]).isEmpty { return .bus }
        if contains(.onDemandOrCable) { return .cableCar }
        return .other
    }

    /// Mode chips in display order (SUGGEST_SPEC §9): Zug · S-Bahn · U-Bahn · Bim · Bus · Seilbahn · Schiff.
    public var modes: [TransportMode] {
        var out: [TransportMode] = []
        if !intersection([.highSpeed, .interCity, .night, .regional, .privateRail]).isEmpty { out.append(.train) }
        if contains(.suburban) { out.append(.sBahn) }
        if contains(.subway) { out.append(.metro) }
        if contains(.tram) { out.append(.tram) }
        if !intersection([.bus, .railReplacement, .coach]).isEmpty { out.append(.bus) }
        if contains(.onDemandOrCable) { out.append(.cableCar) }
        if contains(.ship) { out.append(.ferry) }
        return out
    }
}

/// What a suggestion row stands for.
public enum PlaceKind: String, Hashable, Sendable, Codable {
    /// Rail station (any rail product or an ÖBB EVA number).
    case station
    /// Any other stop (bus, tram, U-Bahn, ship, cable car).
    case stop
    /// Locality („Ort“): town, village, district. Planner only – never offered in „Fahrt erfassen“.
    case town
    /// Address (live only, HAFAS `A=2`).
    case address
    /// Point of interest (live only, HAFAS `A=4`).
    case poi

    public var isStopLike: Bool { self == .station || self == .stop }
}

/// Where a row came from.
public enum PlaceSource: String, Hashable, Sendable, Codable {
    case offline, live, both
}

/// One selectable place: an offline record (stop/station/locality from places.bin/localities.bin) or a live
/// LocMatch row (stop, town meta, address, POI). Values are copies – mutating them never touches the index.
public struct Place: Identifiable, Hashable, Sendable {
    /// Stable id. Offline stops: IFOPT `at:47:1187` (or the kept legacy id for 2 hubs); localities `osm:n…`;
    /// live rows `live:<type>:<extId|lid>`. Persist `stationID` for trips, `id` for favourites/recents.
    public var id: String
    public var kind: PlaceKind
    /// Official name as in the data source ("St.Anton am Arlberg Bahnhof", "6020 Innsbruck, Maria-Theresien-Straße 1").
    public var name: String
    public var aliases: [String]
    public var coordinate: GeoPoint
    public var products: PlaceProducts
    /// 0…1 (SUGGEST_SPEC §4.2): weekday departures + modes offline, HAFAS `wt` live.
    public var importance: Double
    /// Bundesland code as in `FederalState` ("T", "W", …, "X" abroad); nil if unknown (live rows without hint).
    public var state: String?
    /// Gemeinde (Statistik Austria) of offline records.
    public var municipality: String?
    /// ISO country code if known ("at"); empty for unknown.
    public var country: String
    /// HAFAS extId (EVA for ÖBB rail stations, 6-digit Verbund id, 98… POI id) when known.
    public var extId: String?
    /// HAFAS location id (`A=1@…@L=…@`) of live rows – pass unchanged to TripSearch.
    public var lid: String?
    public var isMeta: Bool
    /// HAFAS weight (`wt`) of live rows.
    public var weight: Int?
    /// 1-based position in Scotty's LocMatch answer.
    public var liveRank: Int?
    /// HAFAS icon resource of POIs (`STA_TOURISM`, `STA_RESTAURANT`, …) and its German label.
    public var poiCategory: String?
    public var poiCategoryLabel: String?
    /// Locality class of towns (city, town, village, suburb, hamlet, neighbourhood, quarter).
    public var localityClass: String?
    /// Towns: id of the main stop (most departures, name starts with the locality name).
    public var mainStopID: String?
    /// Ids of the app's previous station list (stations.json) that map to this record.
    public var legacyStationIDs: [String]
    /// Departures on the reference weekday (offline stops) / population (localities).
    public var departures: Int
    /// Lines serving the place (docs/ENRICH_SPEC.md §2.2): offline stops carry the compact set (M8: timetable lines,
    /// special services, OSM-only lines only when nothing else is known), display-sorted; towns the lines of their
    /// main stop; live-only rows `[]`. The full list of a stop is `PlaceIndex.stopLines(for:)`.
    public var lines: [LineRef]
    /// Ski area, regions, special types, services, lift, accessibility, KlimaTicket validity, Gemeinde/Bezirk
    /// (`.empty` for live-only rows; towns: ski area and regions of the main stop plus their own state).
    public var tags: PlaceTags
    /// Ranking score of the last search/merge (higher is better). 0 for unscored values.
    public var score: Double
    public var source: PlaceSource
    /// Names of rows that were merged into this one (dedupe), for debugging and VoiceOver hints.
    public var mergedNames: [String]

    public init(id: String, kind: PlaceKind, name: String, aliases: [String] = [], coordinate: GeoPoint,
                products: PlaceProducts = [], importance: Double = 0.5, state: String? = nil, municipality: String? = nil,
                country: String = "at", extId: String? = nil, lid: String? = nil, isMeta: Bool = false, weight: Int? = nil,
                liveRank: Int? = nil, poiCategory: String? = nil, poiCategoryLabel: String? = nil,
                localityClass: String? = nil, mainStopID: String? = nil, legacyStationIDs: [String] = [],
                departures: Int = 0, lines: [LineRef] = [], tags: PlaceTags = .empty, score: Double = 0,
                source: PlaceSource = .offline, mergedNames: [String] = []) {
        self.id = id
        self.kind = kind
        self.name = name
        self.aliases = aliases
        self.coordinate = coordinate
        self.products = products
        self.importance = importance
        self.state = state
        self.municipality = municipality
        self.country = country
        self.extId = extId
        self.lid = lid
        self.isMeta = isMeta
        self.weight = weight
        self.liveRank = liveRank
        self.poiCategory = poiCategory
        self.poiCategoryLabel = poiCategoryLabel
        self.localityClass = localityClass
        self.mainStopID = mainStopID
        self.legacyStationIDs = legacyStationIDs
        self.departures = departures
        self.lines = lines
        self.tags = tags
        self.score = score
        self.source = source
        self.mergedNames = mergedNames
    }

    /// The plates as text ("110,852,Skibus"), nil without lines (the former `lines: String?`).
    public var linesText: String? { lines.isEmpty ? nil : lines.map(\.ref).joined(separator: ",") }

    public var federalState: FederalState? { state.flatMap(FederalState.init(rawValue:)) }
    public var isForeign: Bool { state == FederalState.foreign.rawValue || (!country.isEmpty && country != "at") }

    /// Row title (SUGGEST_SPEC §9): "St.Anton" → "St. Anton"; addresses show "Straße Nr", POIs their name.
    public var title: String {
        switch kind {
        case .address:
            if let comma = name.firstIndex(of: ","), name.prefix(4).allSatisfy(\.isNumber) {
                return name[name.index(after: comma)...].trimmingCharacters(in: .whitespaces)
            }
            return name
        case .poi:
            let head = name.split(separator: ",", maxSplits: 1).first.map(String.init) ?? name
            return PlaceNames.display(PlaceNames.strippingPOICounter(head))
        default:
            return PlaceNames.display(name)
        }
    }

    /// Row subtitle (German): modes · Bundesland for stops, „Ort · alle Haltestellen“ for towns, „6020 Innsbruck“
    /// for addresses, category · rest of the address for POIs.
    public var subtitle: String {
        switch kind {
        case .station, .stop:
            var parts: [String] = []
            let modes = products.modes.map(\.displayName)
            if !modes.isEmpty { parts.append(modes.joined(separator: " · ")) }
            if let m = municipality, kind == .stop, !PlaceNormalizer.fold(name).hasPrefix(PlaceNormalizer.fold(m)) {
                parts.append(m)
            } else if let fs = federalState, fs != .foreign {
                parts.append(fs.displayName)
            }
            if isForeign, parts.count < 3 { parts.append(country.isEmpty ? "Ausland" : country.uppercased()) }
            return parts.joined(separator: " · ")
        case .town:
            var parts = ["Ort · alle Haltestellen"]
            if let fs = federalState, fs != .foreign { parts.append(fs.displayName) }
            return parts.joined(separator: " · ")
        case .address:
            if let comma = name.firstIndex(of: ","), name.prefix(4).allSatisfy(\.isNumber) {
                return String(name[..<comma])
            }
            return "Adresse"
        case .poi:
            let rest = name.split(separator: ",", maxSplits: 1).dropFirst().first.map { $0.trimmingCharacters(in: .whitespaces) }
            return [poiCategoryLabel, rest].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
        }
    }

    /// The id to store in a trip (`Trip.fromStationID`): the previous stations.json id when this place replaced
    /// one (so relation prices, recents and existing trips keep working), else the place id.
    public var stationID: String {
        if legacyStationIDs.contains(id) { return id }
        return legacyStationIDs.first ?? id
    }

    /// Bridge to the legacy `Station` model (FareEstimator, trip editor, geofences). Kind: rail products → `.rail`,
    /// U-Bahn → `.metro`, everything else → `.tramHub` (use `products.primaryMode` for the precise mode).
    public var station: Station {
        let kind: Station.Kind = products.isRail || self.kind == .station ? .rail : (products.contains(.subway) ? .metro : .stop)
        return Station(id: stationID, name: PlaceNames.display(name), lat: coordinate.latitude, lon: coordinate.longitude,
                       state: state ?? FederalState.foreign.rawValue, kind: kind,
                       importance: Int((importance * 100).rounded()),
                       aliases: aliases.isEmpty ? nil : aliases, products: products.rawValue, municipality: municipality)
    }

    /// Walking time HAFAS uses for nearby stops (SUGGEST_SPEC §2.6, fitted on 37 LocGeoPos rows, max error 0.5 s).
    public static func walkSeconds(meters: Double) -> Double { 120 + 1.2 * meters }
}

/// Personal usage of a place (boosts it in search; SUGGEST_SPEC §5).
public struct PlaceRecentUse: Hashable, Sendable {
    public var ageDays: Double
    public var uses: Int
    public init(ageDays: Double, uses: Int) {
        self.ageDays = ageDays
        self.uses = uses
    }
    public init(lastUsed: Date, uses: Int, now: Date = Date()) {
        self.init(ageDays: max(0, now.timeIntervalSince(lastUsed) / 86_400), uses: uses)
    }
}

/// Search context: where the picker is used, the user's location and personal places.
public struct PlaceSearchContext: Sendable {
    public enum Mode: Sendable, Hashable {
        /// Fahrplan / Verbindungssuche: towns, addresses and POIs are allowed.
        case planner
        /// „Fahrt erfassen“: only stops and stations (towns are excluded, typing a town ranks its main station first).
        case tripLog
    }
    public var mode: Mode
    public var near: GeoPoint?
    /// Place ids (offline `Place.id` or legacy station ids) the user starred.
    public var favourites: Set<String>
    /// Place ids → recent use.
    public var recents: [String: PlaceRecentUse]

    public init(mode: Mode = .planner, near: GeoPoint? = nil, favourites: Set<String> = [], recents: [String: PlaceRecentUse] = [:]) {
        self.mode = mode
        self.near = near
        self.favourites = favourites
        self.recents = recents
    }

    public static let planner = PlaceSearchContext(mode: .planner)
    public static let tripLog = PlaceSearchContext(mode: .tripLog)
}

/// Display helpers shared by Place and the merger.
public enum PlaceNames {
    /// "St.Anton am Arlberg" → "St. Anton am Arlberg"; collapses double spaces.
    public static func display(_ raw: String) -> String {
        let chars = Array(raw)
        var out = String()
        out.reserveCapacity(raw.utf8.count + 4)
        var lastWasSpace = false
        for (i, c) in chars.enumerated() {
            if c == " " {
                if lastWasSpace { continue }
                lastWasSpace = true
            } else {
                lastWasSpace = false
            }
            out.append(c)
            if c == ".", i >= 2, chars[i - 2] == "S", chars[i - 1] == "t", i == 2 || !chars[i - 3].isLetter,
               i + 1 < chars.count, chars[i + 1].isLetter {
                out.append(" ")
                lastWasSpace = true
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// "Hofburg, Rennweg 1, 6020 Innsbruck (2)" → "Hofburg, Rennweg 1, 6020 Innsbruck".
    public static func strippingPOICounter(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.hasSuffix(")"), let open = t.lastIndex(of: "(") else { return t }
        let inner = t[t.index(after: open)..<t.index(before: t.endIndex)]
        guard !inner.isEmpty, inner.allSatisfy({ $0.isASCII && $0.isNumber }) else { return t }
        return t[..<open].trimmingCharacters(in: .whitespaces)
    }
}
