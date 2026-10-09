import Foundation

/// A place mark („Ortsmarke“, BADGE_SPEC §2.5) derived from a stop's tags. `kind` raw values equal the SwiftUI
/// `PlaceMarkKind` raw values (Shared/Wegzeichen), so the view maps 1:1: `PlaceMarkKind(rawValue: mark.kind.rawValue)`.
public struct StopMark: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case hauptbahnhof, bahnhof, fernverkehr, nachtzug, flughafen, bergbahn, talstation, schiff, parkAndRide, bikeAndRide
        case barrierefrei, nachtbus, skibus, wanderbus, gletscher, rufbus, saison, klimaticket, umstieg, krankenhaus
        case universitaet, einkaufszentrum, huette, nationalpark
    }

    /// What a mark says about the stop; the detail hero shows facilities, POIs and places, the eyebrow and the line
    /// list already cover station types and services.
    public enum Group: String, Sendable, Hashable {
        case station, facility, service, area, poi
    }

    public var kind: Kind
    public var confidence: Int
    public var distanceMeters: Int?
    /// Lift, hut, glacier or national park name.
    public var name: String?
    /// `barrierefrei` with wheelchair `limited` („teilweise barrierefrei“).
    public var isPartial: Bool

    public init(kind: Kind, confidence: Int, distanceMeters: Int? = nil, name: String? = nil, isPartial: Bool = false) {
        self.kind = kind
        self.confidence = confidence
        self.distanceMeters = distanceMeters
        self.name = name
        self.isPartial = isPartial
    }

    public var id: String { kind.rawValue }

    public var group: Group {
        switch kind {
        case .hauptbahnhof, .bahnhof, .fernverkehr, .nachtzug, .bergbahn, .schiff: return .station
        case .flughafen, .parkAndRide, .bikeAndRide, .barrierefrei, .umstieg, .klimaticket: return .facility
        case .nachtbus, .skibus, .wanderbus, .rufbus, .saison: return .service
        case .talstation, .gletscher, .huette, .nationalpark: return .area
        case .krankenhaus, .universitaet, .einkaufszentrum: return .poi
        }
    }

    /// Short German title („P+R“, „Talstation“, „barrierefrei“).
    public var title: String {
        switch kind {
        case .hauptbahnhof: return "Hauptbahnhof"
        case .bahnhof: return "Bahnhof"
        case .fernverkehr: return "Fernverkehr"
        case .nachtzug: return "Nachtzug"
        case .flughafen: return "Flughafen"
        case .bergbahn: return "Bergbahn"
        case .talstation: return "Talstation"
        case .schiff: return "Schiff"
        case .parkAndRide: return "P+R"
        case .bikeAndRide: return "B+R"
        case .barrierefrei: return isPartial ? "teilweise barrierefrei" : "barrierefrei"
        case .nachtbus: return "Nachtbus"
        case .skibus: return "Skibus"
        case .wanderbus: return "Wanderbus"
        case .gletscher: return "Gletscher"
        case .rufbus: return "Rufbus"
        case .saison: return "Saisonlinie"
        case .klimaticket: return "KlimaTicket"
        case .umstieg: return "Umstieg zur Bahn"
        case .krankenhaus: return "Krankenhaus"
        case .universitaet: return "Universität"
        case .einkaufszentrum: return "Einkaufszentrum"
        case .huette: return "Hütte"
        case .nationalpark: return "Nationalpark"
        }
    }

    /// Chip text: „P+R · 28 m“, „Talstation Dorfbahn Warth · 77 m“, „Lindauer Hütte · 1,2 km“.
    public var label: String {
        var t = title
        if let n = name, !n.isEmpty {
            switch kind {
            case .talstation: t += " " + n
            case .huette, .nationalpark, .gletscher: t = n
            default: break
            }
        }
        if let d = distanceMeters, d > 0 { t += " · " + Self.shortDistance(d) }
        return t
    }

    /// VoiceOver: „Park and Ride, 28 Meter“, „Talstation Dorfbahn Warth, 77 Meter“, „barrierefrei“.
    public var spoken: String {
        var t: String
        switch kind {
        case .parkAndRide: t = "Park and Ride"
        case .bikeAndRide: t = "Bike and Ride"
        default: t = label.components(separatedBy: " · ").first ?? title
        }
        if let d = distanceMeters, d > 0 { t += ", " + SpokenLabels.distance(Double(d)) }
        return t
    }

    static func shortDistance(_ m: Int) -> String {
        if m < 1_000 { return "\(m) m" }
        let km = (Double(m) / 100).rounded() / 10
        return (km == km.rounded() ? String(Int(km)) : String(format: "%.1f", km).replacingOccurrences(of: ".", with: ",")) + " km"
    }
}

/// An area mark of a row or the detail hero: an official brand from the logo pack (LOGO_SPEC §4) or the own
/// Wegzeichen fallback.
public enum AreaMark: Sendable, Hashable {
    /// Official logo, brand id of the logo pack manifest (`LogoPackManifest.Brand.id`).
    case brand(id: String)
    /// Own `SkiPassBadge` for a ski area id.
    case skiArea(id: String)
    /// Own region text chip for a region id.
    case region(id: String)
}

/// What a brand resolver needs to know about a stop (LOGO_SPEC §4.1 inputs, = `StopBrandInput`).
public struct AreaBrandQuery: Sendable, Hashable {
    /// Gemeindekennziffer as text ("80239").
    public var gkz: String?
    /// State code (B, K, NÖ, OÖ, S, ST, T, V, W).
    public var state: String?
    /// Official name + aliases (locality rules of local brands).
    public var names: [String]
    /// Primary ski area (confidence ≥ 70) or nil.
    public var skiArea: ScoredTag?
    public var skiAlliance: String?
    /// Region tags, any confidence (the resolver applies its own threshold, 80).
    public var regions: [ScoredTag]

    public init(gkz: String? = nil, state: String? = nil, names: [String] = [], skiArea: ScoredTag? = nil,
                skiAlliance: String? = nil, regions: [ScoredTag] = []) {
        self.gkz = gkz
        self.state = state
        self.names = names
        self.skiArea = skiArea
        self.skiAlliance = skiAlliance
        self.regions = regions
    }
}

/// Seam for official brand marks (LOGO_SPEC §4.1). The logo-pack layer adopts it (an adapter over
/// `BrandResolver.resolve(_:)` → `StopBrands.rowBrand` / `heroCells`, already honouring `revoked`, held brands and the
/// user's „Offizielle Logos & Wappen“ switch). Without a provider – or when it returns nothing – the own Wegzeichen
/// show, in the same size.
public protocol AreaBrandProviding: Sendable {
    /// Brand id of the single area mark of a list row (ski area before region); nil → own badge.
    func rowBrandID(for query: AreaBrandQuery) -> String?
    /// Brand ids of the hero „Gebietsleiste“ (≤ 2: ski area + most local tourism board).
    func heroBrandIDs(for query: AreaBrandQuery) -> [String]
}

/// Which marks a stop shows where (docs/ENRICH_SPEC.md §2.5, BADGE_SPEC §2.5 / §3, LOGO_SPEC §4.3).
public enum PlaceMarkSelection {
    /// The one place mark of a row, by priority: airport > main station > valley station (lift role valley,
    /// d ≤ 400 m) > ship > night train > P+R > barrier-free. Badges need confidence ≥ 70.
    public static func rowMark(tags: PlaceTags) -> StopMark? {
        let min = PlaceTags.badgeMinConfidence
        func typed(_ t: PlaceType, _ k: StopMark.Kind) -> StopMark? {
            tags.types.first { $0.type == t && $0.confidence >= min }
                .map { StopMark(kind: k, confidence: $0.confidence, distanceMeters: $0.distanceMeters) }
        }
        if let m = typed(.airport, .flughafen) { return m }
        if let m = typed(.mainStation, .hauptbahnhof) { return m }
        if let m = valleyStation(tags) { return m }
        if let m = typed(.ship, .schiff) { return m }
        if let m = typed(.nightTrain, .nachtzug) { return m }
        if let m = typed(.parkAndRide, .parkAndRide) { return m }
        if tags.accessibility == .yes { return StopMark(kind: .barrierefrei, confidence: min) }
        return nil
    }

    /// Every mark of the stop for the detail, in BADGE_SPEC §2.5 order (KlimaTicket has its own chip and is not
    /// included; `airportLink` counts as Flughafen only here, never in rows).
    public static func detailMarks(tags: PlaceTags) -> [StopMark] {
        let min = PlaceTags.badgeMinConfidence
        var byKind: [StopMark.Kind: StopMark] = [:]
        func add(_ m: StopMark) {
            if let old = byKind[m.kind], old.confidence >= m.confidence { return }
            byKind[m.kind] = m
        }
        let typeMap: [PlaceType: StopMark.Kind] = [
            .mainStation: .hauptbahnhof, .trainStation: .bahnhof, .longDistance: .fernverkehr, .nightTrain: .nachtzug,
            .airport: .flughafen, .cableCar: .bergbahn, .ship: .schiff, .parkAndRide: .parkAndRide,
            .bikeAndRide: .bikeAndRide, .onDemand: .rufbus, .hospital: .krankenhaus, .university: .universitaet,
            .mall: .einkaufszentrum,
        ]
        for t in tags.types where t.confidence >= min {
            if let k = typeMap[t.type] { add(StopMark(kind: k, confidence: t.confidence, distanceMeters: t.distanceMeters)) }
        }
        if byKind[.hauptbahnhof] != nil { byKind[.bahnhof] = nil }
        let serviceMap: [PlaceService: StopMark.Kind] = [.nightBus: .nachtbus, .skiBus: .skibus, .hikingBus: .wanderbus,
                                                        .onDemand: .rufbus, .seasonal: .saison, .airportLink: .flughafen]
        for s in tags.services { if let k = serviceMap[s], byKind[k] == nil { add(StopMark(kind: k, confidence: min)) } }
        if let v = valleyStation(tags) { add(v) }
        if let g = tags.glacier, g.confidence >= min {
            add(StopMark(kind: .gletscher, confidence: g.confidence, distanceMeters: g.distanceMeters, name: g.id))
        } else if tags.glacierSkiArea != nil {
            add(StopMark(kind: .gletscher, confidence: min))
        }
        if let h = tags.hut, h.confidence >= min {
            add(StopMark(kind: .huette, confidence: h.confidence, distanceMeters: h.distanceMeters, name: h.id))
        }
        if let n = tags.nationalPark, n.confidence >= min {
            add(StopMark(kind: .nationalpark, confidence: n.confidence, distanceMeters: n.distanceMeters, name: n.id))
        }
        if let r = tags.railTransfer, r.confidence >= min {
            add(StopMark(kind: .umstieg, confidence: r.confidence, distanceMeters: r.distanceMeters))
        }
        switch tags.accessibility {
        case .yes?: add(StopMark(kind: .barrierefrei, confidence: min))
        case .limited?: add(StopMark(kind: .barrierefrei, confidence: min, isPartial: true))
        default: break
        }
        return StopMark.Kind.allCases.compactMap { byKind[$0] }
    }

    /// The chips of the detail hero badge flow (ENRICH_SPEC §3.2): facilities, POIs and places. Station types are in
    /// the eyebrow, services in the line list, the valley station in the ski-pass card when the stop has a ski area.
    /// St. Anton am Arlberg Bahnhof → P+R · 28 m, barrierefrei.
    public static func heroChips(tags: PlaceTags) -> [StopMark] {
        detailMarks(tags: tags).filter { m in
            switch m.group {
            case .station, .service: return false
            case .area: return !(m.kind == .talstation && tags.primarySkiArea != nil)
            case .facility, .poi: return true
            }
        }
    }

    /// Valley station of a lift within 400 m (BADGE_SPEC §2.5 „Talstation (Lift)“).
    static func valleyStation(_ tags: PlaceTags) -> StopMark? {
        guard let l = tags.lift, l.role == .valley, l.confidence >= PlaceTags.badgeMinConfidence,
              (l.distanceMeters ?? Int.max) <= 400 else { return nil }
        return StopMark(kind: .talstation, confidence: l.confidence, distanceMeters: l.distanceMeters, name: l.name)
    }

    // MARK: area marks (ski area / region / official brand)

    /// The inputs of the brand resolver for a stop.
    public static func areaBrandQuery(place: Place, tags: PlaceTags) -> AreaBrandQuery {
        AreaBrandQuery(gkz: tags.gkz.map(String.init), state: place.state, names: [place.name] + place.aliases,
                       skiArea: tags.primarySkiArea, skiAlliance: tags.skiAlliances.first, regions: tags.regions)
    }

    /// The single area mark of a list row (LOGO_SPEC §4.3: at most one; ski area before region): the official brand
    /// when `brands` has one, else the own ski-pass badge (ski area ≥ 70), else the own region chip (first region
    /// ≥ 80 by confidence), else nil.
    public static func rowAreaMark(place: Place, tags: PlaceTags, brands: (any AreaBrandProviding)? = nil) -> AreaMark? {
        if let brands, let id = brands.rowBrandID(for: areaBrandQuery(place: place, tags: tags)), !id.isEmpty {
            return .brand(id: id)
        }
        if let ski = tags.primarySkiArea { return .skiArea(id: ski.id) }
        if let r = rowRegions(tags).first { return .region(id: r.id) }
        return nil
    }

    /// Cells of the hero „Gebietsleiste“ (LOGO_SPEC §4.4, ≤ 2). Empty without official brands: the hero then shows
    /// the own SkiPassBadge and region chips in its badge flow.
    public static func heroAreaCells(place: Place, tags: PlaceTags, brands: (any AreaBrandProviding)?) -> [AreaMark] {
        guard let brands else { return [] }
        var seen = Set<String>()
        return brands.heroBrandIDs(for: areaBrandQuery(place: place, tags: tags))
            .filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(2).map { .brand(id: $0) }
    }

    /// Region chips of the detail (all regions ≥ 80 by confidence), without one whose name equals the ski area's
    /// short name or name (BADGE_SPEC §2.4: Arlberg next to Ski Arlberg).
    public static func detailRegions(tags: PlaceTags, skiArea: SkiArea?, regionName: (String) -> String?) -> [ScoredTag] {
        let ski = [skiArea?.shortName, skiArea?.name].compactMap { $0.map(PlaceNormalizer.fold) }
        return rowRegions(tags).filter { r in
            guard let n = regionName(r.id) else { return true }
            return !ski.contains(PlaceNormalizer.fold(n))
        }
    }

    static func rowRegions(_ tags: PlaceTags) -> [ScoredTag] {
        tags.regions.filter { $0.confidence >= PlaceTags.regionMinConfidence }
            .enumerated().sorted { a, b in
                a.element.confidence != b.element.confidence ? a.element.confidence > b.element.confidence
                    : a.offset < b.offset
            }.map(\.element)
    }
}
