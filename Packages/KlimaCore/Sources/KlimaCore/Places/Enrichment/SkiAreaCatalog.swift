import Foundation

/// The lookup tables of the two `META` sections (docs/ENRICH_SPEC.md §1.4.1, §1.5): ski areas (curated in places.bin,
/// OSM-only and the OSM-derived statistics in stops_osm.bin), ski-pass alliances, regions and landscapes, Bezirke,
/// KlimaTicket products and defaults, operators and the enumerations the line catalogue is written in.
/// Everything is resolved **by name** (`modes`, `nets`, `lineFlags`, `railCats`), so the build may add values without
/// a format version bump. Unknown or malformed entries are skipped, never fatal.
struct SkiAreaCatalog: Sendable {
    struct Operator: Sendable, Hashable {
        var name: String
        var display: String
    }

    /// Curated + OSM-only areas and sectors, and the alliances (`kind == .alliance`), by id.
    let areas: [String: SkiArea]
    /// Areas and sectors (no alliances), sorted by name.
    let sortedAreas: [SkiArea]
    let regions: [String: Region]
    /// Tourism regions and landscapes, sorted by name.
    let sortedRegions: [Region]
    /// "802" → "Bregenz"; Vienna as a whole is "900".
    let bezirke: [String: String]
    /// "10" → "Favoriten".
    let wienBezirke: [String: String]
    /// KlimaTicket product names ("vbg-maximo" → "KlimaTicket VMOBIL MAXIMO").
    let klimaTicketProducts: [String: String]
    /// State code → regional KlimaTicket ids valid by default (`klimaticket.defaultRegional`).
    let defaultRegional: [String: [String]]
    /// Operator index space of LCAT/LPAT: places.bin `operators` ++ stops_osm.bin `operatorsExtra`.
    let operators: [Operator]
    /// Index → mode, network, flag bit and rail category of the files (META `modes`, `nets`, `lineFlags`, `railCats`).
    let modes: [LineMode?]
    let nets: [TransitNetwork?]
    let flagBits: [LineFlags]
    let railCategories: [String]
    /// `build.validUntil`, else the latest end of `build.gtfsValidity` (MVO rule, §1.10.1).
    let validUntil: Date?
    /// OSM META `lifts[k]` = [name, role, liftType] (`#lift<k>` tag values).
    let lifts: [LiftEntry]
    /// OSM META `attribution`.
    let osmAttribution: String?

    struct LiftEntry: Sendable, Hashable {
        var name: String
        var role: LiftStation.Role
        var type: String?
    }

    static let empty = SkiAreaCatalog(official: nil, osm: nil)

    /// Default META enumerations (ENRICH_SPEC §1.8), used when a file has no META.
    static let defaultModes = ["other", "rail", "sbahn", "subway", "tram", "bus", "trolleybus", "sev", "ship", "cable",
                               "ondemand"]
    static let defaultNets = ["", "VOR", "VVSt", "VKL", "OÖVV", "SVV", "VVT", "VVV", "ÖBB", "INT"]
    static let defaultLineFlags = ["ski", "winter", "summer", "night", "schooldays", "schooldays?", "school_or_seasonal",
                                   "seasonal", "ondemand", "sev", "superseded", "ski_candidate", "trolley", "school"]

    /// META flag names → `LineFlags` (§1.8 order; unknown names map to no bit).
    static let flagNames: [String: LineFlags] = [
        "ski": .ski, "winter": .winter, "summer": .summer, "night": .night, "schooldays": .schoolDays,
        "schooldays?": .schoolDaysUncertain, "school_or_seasonal": .schoolOrSeasonal, "seasonal": .seasonal,
        "ondemand": .onDemand, "sev": .railReplacement, "superseded": .superseded, "ski_candidate": .skiCandidate,
        "trolley": .trolley, "school": .school,
    ]

    init(official: [String: Any]?, osm: [String: Any]?) {
        let o = official ?? [:], x = osm ?? [:]
        modes = (o["modes"] as? [String] ?? Self.defaultModes).map { LineMode(keyName: $0) }
        nets = (o["nets"] as? [String] ?? Self.defaultNets).map { TransitNetwork(rawValue: $0) }
        flagBits = (o["lineFlags"] as? [String] ?? Self.defaultLineFlags).map { Self.flagNames[$0] ?? [] }
        railCategories = o["railCats"] as? [String] ?? []

        var ops: [Operator] = []
        for list in [o["operators"], x["operatorsExtra"]] {
            for e in list as? [Any] ?? [] {
                if let d = e as? [String: Any], let name = d["name"] as? String {
                    ops.append(Operator(name: name, display: (d["display"] as? String).flatMap(Self.nonEmpty) ?? name))
                } else if let name = e as? String {
                    ops.append(Operator(name: name, display: OperatorNames.display(name)))
                }
            }
        }
        operators = ops

        // ski areas: curated (places.bin) + OSM statistics; OSM-only areas; alliances
        let stats = x["skiAreaStats"] as? [String: Any] ?? [:]
        var areas: [String: SkiArea] = [:]
        for (id, raw) in o["skiAreas"] as? [String: Any] ?? [:] {
            guard let d = raw as? [String: Any], let a = Self.skiArea(id: id, d, stats: stats[id] as? [String: Any],
                                                                       osmOnly: false) else { continue }
            areas[id] = a
        }
        for (id, raw) in x["skiAreas"] as? [String: Any] ?? [:] where areas[id] == nil {
            guard let d = raw as? [String: Any], let a = Self.skiArea(id: id, d, stats: nil, osmOnly: true) else { continue }
            areas[id] = a
        }
        for (id, raw) in o["skiAlliances"] as? [String: Any] ?? [:] where areas[id] == nil {
            guard let d = raw as? [String: Any], let name = d["name"] as? String else { continue }
            let st = stats[id] as? [String: Any]
            areas[id] = SkiArea(id: id, name: name, kind: .alliance, bbox: Self.bbox(st?["bbox"]),
                                hue: d["hue"] as? String ?? "fels", monogram: d["mono"] as? String ?? "",
                                liftCount: Self.int(st?["lifts"]), stopCount: Self.int(st?["stops"]),
                                isVerified: d["verified"] as? Bool ?? false)
        }
        self.areas = areas
        sortedAreas = areas.values.filter { $0.kind != .alliance }.sorted(by: Self.byName)

        var regions: [String: Region] = [:]
        for (id, raw) in o["regions"] as? [String: Any] ?? [:] {
            guard let d = raw as? [String: Any], let name = d["name"] as? String else { continue }
            regions[id] = Region(id: id, name: name, kind: Region.Kind(rawValue: d["kind"] as? String ?? "") ?? .tourism,
                                 stopCount: Self.int(d["stops"]))
        }
        self.regions = regions
        sortedRegions = regions.values.sorted { a, b in
            let c = a.name.compare(b.name, options: [.caseInsensitive, .diacriticInsensitive])
            return c == .orderedSame ? a.id < b.id : c == .orderedAscending
        }

        bezirke = o["bezirke"] as? [String: String] ?? [:]
        wienBezirke = o["wienBezirke"] as? [String: String] ?? [:]
        let kt = o["klimaticket"] as? [String: Any] ?? [:]
        klimaTicketProducts = kt["products"] as? [String: String] ?? [:]
        defaultRegional = kt["defaultRegional"] as? [String: [String]] ?? [:]

        let build = o["build"] as? [String: Any] ?? [:]
        if let v = (build["validUntil"] as? String).flatMap(PlaceDataset.parseDate) {
            validUntil = v
        } else {
            let ends = (build["gtfsValidity"] as? [String: String] ?? [:]).values.compactMap { range -> Date? in
                range.split(separator: "/").last.flatMap { PlaceDataset.parseDate(String($0)) }
            }
            validUntil = ends.max()
        }

        lifts = (x["lifts"] as? [Any] ?? []).map { e in
            let a = e as? [Any] ?? []
            let name = a.first as? String ?? ""
            let role = a.count > 1 ? (a[1] as? String ?? "") : ""
            let type = a.count > 2 ? (a[2] as? String ?? "") : ""
            return LiftEntry(name: name, role: LiftStation.Role(rawValue: role) ?? .unknown, type: Self.nonEmpty(type))
        }
        osmAttribution = x["attribution"] as? String
    }

    static func skiArea(id: String, _ d: [String: Any], stats: [String: Any]?, osmOnly: Bool) -> SkiArea? {
        guard let name = d["name"] as? String, !name.isEmpty else { return nil }
        let s = stats ?? d
        return SkiArea(id: id, name: name, shortName: (d["short"] as? String).flatMap(nonEmpty),
                       kind: SkiArea.Kind(rawValue: d["kind"] as? String ?? "") ?? .area,
                       parentID: (d["parent"] as? String).flatMap(nonEmpty),
                       allianceIDs: d["alliances"] as? [String] ?? [], resorts: d["resorts"] as? [String] ?? [],
                       states: d["states"] as? [String] ?? [], bbox: bbox(s["bbox"] ?? d["bbox"]),
                       glyph: SkiArea.Glyph(rawValue: d["glyph"] as? String ?? "") ?? .peaks2,
                       hue: (d["hue"] as? String).flatMap(nonEmpty) ?? "fels", monogram: d["mono"] as? String ?? "",
                       liftCount: int(s["lifts"] ?? d["lifts"]), stopCount: int(s["stops"] ?? d["stops"]),
                       isOSMOnly: osmOnly || (d["source"] as? String) == "osm",
                       isVerified: d["verified"] as? Bool ?? false)
    }

    static func bbox(_ v: Any?) -> GeoBox {
        guard let a = v as? [Any], a.count == 4 else { return GeoBox(minLat: 0, minLon: 0, maxLat: 0, maxLon: 0) }
        let d = a.map { ($0 as? NSNumber)?.doubleValue ?? 0 }
        return GeoBox(minLat: d[0], minLon: d[1], maxLat: d[2], maxLon: d[3])
    }

    static func int(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? 0 }

    static func nonEmpty(_ s: String) -> String? { s.isEmpty ? nil : s }

    static func byName(_ a: SkiArea, _ b: SkiArea) -> Bool {
        let c = a.name.compare(b.name, options: [.caseInsensitive, .diacriticInsensitive])
        return c == .orderedSame ? a.id < b.id : c == .orderedAscending
    }

    // MARK: lookups

    /// Display name of an operator legal name (E4): the build's table first, then the live mapping.
    func operatorDisplay(_ legal: String) -> String {
        if let o = operators.first(where: { $0.name == legal }) { return o.display }
        return OperatorNames.display(legal)
    }

    /// "Bezirk" key of a GKZ: GKZ / 100, Vienna as a whole 900 (ENRICH_SPEC M5).
    static func bezirk(gkz: Int) -> Int { gkz / 10000 == 9 ? 900 : gkz / 100 }

    /// Wiener Gemeindebezirk (1…23) of a Vienna GKZ, else nil.
    static func wienBezirk(gkz: Int) -> Int? { gkz / 10000 == 9 ? gkz / 100 % 100 : nil }

    func bezirkName(_ bezirk: Int?) -> String? {
        guard let bezirk else { return nil }
        return bezirke[String(bezirk)] ?? bezirke[String(format: "%03d", bezirk)]
    }

    func wienBezirkName(_ n: Int?) -> String? { n.flatMap { wienBezirke[String($0)] } }

    /// KlimaTicket Ö + regional + extended products of a validity, with names (`oe` first).
    func products(for kt: KlimaTicketValidity) -> [(id: String, name: String)] {
        guard kt.status == .valid || kt.status == .border else { return [] }
        var ids = ["oe"]
        for id in kt.regionalTicketIDs + kt.extendedTicketIDs where !ids.contains(id) { ids.append(id) }
        return ids.map { id in (id: id, name: klimaTicketProducts[id] ?? (id == "oe" ? "KlimaTicket Ö" : id)) }
    }
}
