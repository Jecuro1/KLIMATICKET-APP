import Foundation

/// One record of the offline place database (internal; the public value is `Place`). Kept small: ~60k of them
/// live as long as the index, so rarely set fields sit in a shared, copy-on-write `Extras` box.
struct PlaceRecord: Sendable {
    var id: String
    var name: String
    var aliases: [String]
    var lat: Double
    var lon: Double
    var kind: PlaceKind
    var flags: UInt8
    private var classCode: UInt8
    var products: Int
    var importance: Double
    /// "at", "" = unknown/abroad (offline: state X), ISO code for live rows.
    var country: String
    /// Bundesland code ("T", "W", …, "X"), "" if unknown.
    var state: String
    var municipality: String
    var weight: Int
    /// Gemeindekennziffer from GEMS (0 = unknown).
    var gkz: UInt32 = 0
    /// GEMS index of the record's own file (0xFFFF = none; GTAG of places.bin is in GEMS order).
    var gemIndex: UInt16 = 0xFFFF
    /// Position in places.bin RECS for its stop records (key of every per-stop enrichment section), -1 otherwise.
    var stopIndex: Int32 = -1
    /// v1 only: the legacy „lines“ string of EXTR tag 5 ("" = none; v2 has LSTP instead).
    private var linesValue: String = ""
    private var extras: ExtrasBox?

    /// Rarely set fields. Immutable box: setters replace it (no uniqueness checks – Swift 6.4's optimizer
    /// miscompiles `isKnownUniquelyReferenced` on this field when inlined into the decoder).
    struct Extras: Sendable {
        var eva: Int?
        var hafasExtId: Int?
        var uic: Int?
        var legacyIDs: [String] = []
        var mainStopID: String?
        // live rows only
        var extIdString: String?
        var lid: String?
        var isMeta = false
        var liveRank: Int?
        var wt: Int?
        var poiCategory: String?
        var poiCategoryLabel: String?
    }

    final class ExtrasBox: Sendable {
        let fields: Extras
        init(_ fields: Extras) { self.fields = fields }
    }

    static let placeClasses: [String?] = [nil, "city", "town", "village", "suburb", "hamlet", "neighbourhood", "quarter",
                                         "isolated_dwelling"]

    init(id: String, name: String, aliases: [String], lat: Double, lon: Double, kind: PlaceKind, products: Int,
         importance: Double, country: String, state: String, municipality: String, localityClass: String?, weight: Int,
         flags: UInt8) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.lat = lat
        self.lon = lon
        self.kind = kind
        self.flags = flags
        self.classCode = UInt8(Self.placeClasses.firstIndex(of: localityClass) ?? 0)
        self.products = products
        self.importance = importance
        self.country = country
        self.state = state
        self.municipality = municipality
        self.weight = weight
    }

    var localityClass: String? {
        get { Self.placeClasses[Int(classCode)] }
        set { classCode = UInt8(Self.placeClasses.firstIndex(of: newValue) ?? 0) }
    }

    private mutating func update(_ change: (inout Extras) -> Void) {
        var f = extras?.fields ?? Extras()
        change(&f)
        extras = ExtrasBox(f)
    }

    /// Replaces all extra fields at once (decoder: one allocation per record).
    mutating func setExtras(_ f: Extras) { extras = ExtrasBox(f) }

    var eva: Int? { get { extras?.fields.eva } set { update { $0.eva = newValue } } }
    var hafasExtId: Int? { get { extras?.fields.hafasExtId } set { update { $0.hafasExtId = newValue } } }
    var uic: Int? { get { extras?.fields.uic } set { update { $0.uic = newValue } } }
    var legacyIDs: [String] { get { extras?.fields.legacyIDs ?? [] } set { update { $0.legacyIDs = newValue } } }
    var mainStopID: String? { get { extras?.fields.mainStopID } set { update { $0.mainStopID = newValue } } }
    var extIdString: String? { get { extras?.fields.extIdString } set { update { $0.extIdString = newValue } } }
    var lid: String? { get { extras?.fields.lid } set { update { $0.lid = newValue } } }
    var isMeta: Bool { get { extras?.fields.isMeta ?? false } set { update { $0.isMeta = newValue } } }
    var liveRank: Int? { get { extras?.fields.liveRank } set { update { $0.liveRank = newValue } } }
    var wt: Int? { get { extras?.fields.wt } set { update { $0.wt = newValue } } }
    var poiCategory: String? { get { extras?.fields.poiCategory } set { update { $0.poiCategory = newValue } } }
    var poiCategoryLabel: String? { get { extras?.fields.poiCategoryLabel } set { update { $0.poiCategoryLabel = newValue } } }
    /// v1 only: lines of the legacy EXTR tag 5 ("110,852"), nil if none.
    var legacyLines: String? {
        get { linesValue.isEmpty ? nil : linesValue }
        set { linesValue = newValue ?? "" }
    }

    /// HAFAS extId used by dedupe rule D1 (offline: Verbund extId hint, else EVA).
    var extId: String? {
        if let e = extras?.fields {
            if let x = e.extIdString { return x }
            if let h = e.hafasExtId { return String(h) }
            if let v = e.eva { return String(v) }
        }
        return nil
    }
}

/// Reader for the binary place files built by `scripts/build_places.py` (KBPL v1 and v2, docs/ENRICH_SPEC.md §1).
/// `places.bin` holds every Austrian stop (Verbund list + ÖBB/Wiener Linien/Steiermark open data) and, from v2 on, the
/// official enrichment sections; `stops_osm.bin` (optional, ODbL) the OSM enrichment layer tied to places.bin by its
/// `BASE` hash; `localities.bin` the OSM localities (ODbL) referencing their main stop by id. Each file may be v1 or v2
/// independently, so the app keeps working on v1 files until the data build ships v2.
public struct PlaceDataset: Sendable {
    static let stateCodes = ["X", "B", "K", "NÖ", "OÖ", "S", "ST", "T", "V", "W"]
    static let placeClasses: [String?] = [nil, "city", "town", "village", "suburb", "hamlet", "neighbourhood", "quarter",
                                         "isolated_dwelling"]

    public enum ReadError: Error, Equatable {
        case badMagic, unsupportedVersion(Int), truncated
        /// A section is out of bounds, has an unknown codec, does not inflate or fails its CRC-32 (v2).
        case corrupt(section: String)
    }

    /// Why `stops_osm.bin` is not used (the app then runs on the official layer alone, M1).
    public enum OSMLayerIssue: Error, Equatable, Sendable {
        /// An OSM file URL was given but the file does not exist.
        case missing
        /// Not a readable KBPL file (bad magic, truncated header or directory).
        case unreadable
        case unsupportedVersion(Int)
        case corrupt(section: String)
        /// places.bin is v1 or one of the files has no `BASE` section.
        case noBase
        /// The file belongs to another places.bin build.
        case baseMismatch
    }

    var stops: [PlaceRecord]
    var localities: [PlaceRecord]
    /// Decoded enrichment sections of places.bin (v2 only, nil for v1). Stop record index = position in `stops`.
    var officialLayer: PlaceLayer?
    /// Decoded sections of stops_osm.bin, only when it decoded and its BASE matched places.bin (M1).
    var osmLayer: PlaceLayer?
    public private(set) var osmLayerIssue: OSMLayerIssue?
    public private(set) var dataInfo: PlaceDataInfo

    public var stopCount: Int { stops.count }
    public var localityCount: Int { localities.count }

    init(stops: [PlaceRecord], localities: [PlaceRecord]) {
        self.stops = stops
        self.localities = localities
        dataInfo = Self.info(version: 1, stops: stops, official: nil, osm: nil, issue: nil)
    }

    /// Decodes `places.bin`, optionally `localities.bin` and the OSM layer `stops_osm.bin`. A broken places.bin or
    /// localities.bin throws; a missing, broken or foreign OSM layer only sets `osmLayerIssue`.
    public init(places: Data, localities: Data?, osm: Data? = nil) throws {
        let placesFile = try Self.decodeFile(places, keepLayer: true)
        var stops = placesFile.records.filter { $0.kind != .town }
        var locs = placesFile.records.filter { $0.kind == .town }
        if let localities { locs += try Self.decodeFile(localities, keepLayer: false).records.filter { $0.kind == .town } }
        Self.computeImportance(stops: &stops, localities: &locs)
        self.stops = stops
        self.localities = locs
        officialLayer = placesFile.layer
        if let osm {
            switch Self.loadOSMLayer(osm, official: placesFile.layer) {
            case .success(let layer): osmLayer = layer
            case .failure(let issue): osmLayerIssue = issue
            }
        }
        dataInfo = Self.info(version: placesFile.version, stops: stops, official: officialLayer, osm: osmLayer,
                             issue: osmLayerIssue)
    }

    /// `osmURL` pointing to a missing file is not an error (`osmLayerIssue == .missing`).
    public init(placesURL: URL, localitiesURL: URL?, osmURL: URL? = nil) throws {
        let p = try Data(contentsOf: placesURL, options: .mappedIfSafe)
        let l = try localitiesURL.map { try Data(contentsOf: $0, options: .mappedIfSafe) }
        let o = osmURL.flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }
        try self.init(places: p, localities: l, osm: o)
        if osmURL != nil, o == nil {
            osmLayerIssue = .missing
            dataInfo.osmLayerNote = "stops_osm.bin: missing"
        }
    }

    // MARK: importance (SUGGEST_SPEC §4.2, fitted to HAFAS wt)

    static func modeClass(_ m: Int) -> Double {
        if m & (1 | 4 | 8) != 0 { return 1.0 }
        if m & 4096 != 0 { return 0.9 }
        if m & (16 | 32) != 0 { return 0.6 }
        if m & 256 != 0 { return 0.55 }
        if m & 512 != 0 { return 0.45 }
        if m & (128 | 2048) != 0 { return 0.3 }
        if m & (64 | 2) != 0 { return 0.25 }
        return 0
    }

    static func importance(departures: Int, modes: Int) -> Double {
        let d = min(1.0, log1p(Double(max(0, departures))) / log1p(3000))
        return min(1.0, 0.30 + 0.35 * d + 0.35 * modeClass(modes))
    }

    static func importance(wt: Int) -> Double { log1p(Double(max(0, min(wt, 32767)))) / log1p(32767) }

    static func importanceDefault(products: Int) -> Double {
        if products & (1 | 4 | 8) != 0 { return 0.80 }
        if products & (16 | 32 | 4096) != 0 { return 0.72 }
        if products & 256 != 0 { return 0.75 }
        if products & 512 != 0 { return 0.70 }
        if products & (64 | 2) != 0 { return 0.55 }
        return 0.45
    }

    static func computeImportance(stops: inout [PlaceRecord], localities: inout [PlaceRecord]) {
        var byID: [String: Int] = [:]
        byID.reserveCapacity(stops.count)
        for i in stops.indices {
            stops[i].importance = importance(departures: stops[i].weight, modes: stops[i].products)
            byID[stops[i].id] = i
        }
        for i in localities.indices {
            let main = localities[i].mainStopID.flatMap { byID[$0] }.map { stops[$0] }
            let delta: Double
            switch localities[i].localityClass {
            case "city", "town": delta = 0.01
            case "village", "suburb": delta = -0.02
            default: delta = -0.10
            }
            localities[i].importance = max(0, min(1, (main?.importance ?? 0.5) + delta))
            localities[i].products = main?.products ?? 0
            if localities[i].municipality.isEmpty, let m = main { localities[i].municipality = m.municipality }
        }
    }

    // MARK: binary decoding

    struct DecodedFile {
        var version: Int
        var records: [PlaceRecord]
        var layer: PlaceLayer?
    }

    /// Records of a v1 or v2 file; with `keepLayer` the enrichment sections of a v2 file are decoded too.
    static func decodeFile(_ data: Data, keepLayer: Bool) throws -> DecodedFile {
        let c = try KBPLContainer(data: data)
        if c.version == 1 {
            let records: [PlaceRecord] = try data.withUnsafeBytes { raw in
                func part(_ i: Int) -> UnsafeRawBufferPointer {
                    let e = c.entries[i]
                    return UnsafeRawBufferPointer(rebasing: raw[e.offset..<(e.offset + e.storedLength)])
                }
                return try decodeRecords(recs: part(0), strs: part(1), gems: part(2), extr: part(3), n: c.nRecords,
                                         nGem: c.nGemeinden, exactGems: false) { _ in ReadError.truncated }
            }
            return DecodedFile(version: 1, records: records, layer: nil)
        }
        let recs = try c.required("RECS"), strs = try c.required("STRS"), gems = try c.required("GEMS")
        let extr = try c.section("EXTR") ?? []
        let records = try recs.withUnsafeBytes { r in
            try strs.withUnsafeBytes { s in
                try gems.withUnsafeBytes { g in
                    try extr.withUnsafeBytes { x in
                        try decodeRecords(recs: r, strs: s, gems: g, extr: x, n: c.nRecords, nGem: c.nGemeinden,
                                          exactGems: true) { ReadError.corrupt(section: $0) }
                    }
                }
            }
        }
        guard c.nStopRecords <= c.nRecords else { throw ReadError.corrupt(section: "RECS") }
        let layer = keepLayer ? try PlaceLayer(container: c, strings: strs) : nil
        var decoded = records
        if layer != nil {
            for i in 0..<min(c.nStopRecords, decoded.count) where decoded[i].kind != .town { decoded[i].stopIndex = Int32(i) }
        }
        return DecodedFile(version: 2, records: decoded, layer: layer)
    }

    /// v1 entry point kept for tools and tests: the records of one file.
    static func decode(_ data: Data) throws -> [PlaceRecord] {
        try decodeFile(data, keepLayer: false).records
    }

    /// M1: the OSM layer is used only if it is a valid v2 file whose BASE equals places.bin's.
    static func loadOSMLayer(_ data: Data, official: PlaceLayer?) -> Result<PlaceLayer, OSMLayerIssue> {
        let c: KBPLContainer
        do {
            c = try KBPLContainer(data: data)
        } catch ReadError.unsupportedVersion(let v) {
            return .failure(.unsupportedVersion(v))
        } catch {
            return .failure(.unreadable)
        }
        guard c.version == 2 else { return .failure(.unsupportedVersion(c.version)) }
        guard let official, let base = official.section("BASE") else { return .failure(.noBase) }
        let layer: PlaceLayer
        do {
            layer = try PlaceLayer(container: c, strings: nil)
        } catch ReadError.corrupt(let section) {
            return .failure(.corrupt(section: section))
        } catch {
            return .failure(.unreadable)
        }
        guard let osmBase = layer.section("BASE") else { return .failure(.noBase) }
        guard osmBase == base, c.nStopRecords == official.nStopRecords else { return .failure(.baseMismatch) }
        return .success(layer)
    }

    static func info(version: Int, stops: [PlaceRecord], official: PlaceLayer?, osm: PlaceLayer?,
                     issue: OSMLayerIssue?) -> PlaceDataInfo {
        var info = PlaceDataInfo(formatVersion: version, hasOSMLayer: osm != nil)
        if let official {
            let meta = official.metaJSON
            let build = meta?["build"] as? [String: Any]
            info.buildDate = (build?["date"] as? String).flatMap(Self.parseDate)
            info.timetableReferenceDays = build?["timetableDays"] as? [String] ?? []
            info.lineCount = official.lineCount + (osm?.lineCount ?? 0)
            let a = official.stopsWithLines(), b = osm?.stopsWithLines() ?? []
            info.stopsWithLines = (0..<max(a.count, b.count)).reduce(0) { n, i in
                n + ((i < a.count && a[i]) || (i < b.count && b[i]) ? 1 : 0)
            }
        } else {
            info.stopsWithLines = stops.reduce(0) { $0 + ($1.legacyLines == nil ? 0 : 1) }   // v1: the „lines“ string
        }
        if let issue { info.osmLayerNote = "stops_osm.bin: \(issue)" }
        return info
    }

    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withFullDate]
        return f.date(from: String(s.prefix(10)))
    }

    /// Record sections (identical in v1 and v2): `n` × 28-byte RECS, NUL-terminated STRS, (GKZ, str) GEMS, tagged EXTR.
    static func decodeRecords(recs: UnsafeRawBufferPointer, strs: UnsafeRawBufferPointer, gems: UnsafeRawBufferPointer,
                              extr: UnsafeRawBufferPointer, n: Int, nGem: Int, exactGems: Bool,
                              error: (String) -> ReadError) throws -> [PlaceRecord] {
        func u32(_ b: UnsafeRawBufferPointer, _ o: Int) -> UInt32 { b.loadUnaligned(fromByteOffset: o, as: UInt32.self).littleEndian }
        func u16(_ b: UnsafeRawBufferPointer, _ o: Int) -> UInt16 { b.loadUnaligned(fromByteOffset: o, as: UInt16.self).littleEndian }
        func i32(_ b: UnsafeRawBufferPointer, _ o: Int) -> Int32 { b.loadUnaligned(fromByteOffset: o, as: Int32.self).littleEndian }
        guard n <= recs.count / 28, recs.count == n * 28 else { throw error("RECS") }
        guard nGem <= gems.count / 8, exactGems ? gems.count == nGem * 8 : gems.count >= nGem * 8 else { throw error("GEMS") }

        func string(_ o: Int) -> String {
            guard o < strs.count else { return "" }
            var end = o
            while end < strs.count && strs[end] != 0 { end += 1 }
            return String(decoding: UnsafeRawBufferPointer(rebasing: strs[o..<end]), as: UTF8.self)
        }
        var gemeinden: [String] = []
        gemeinden.reserveCapacity(nGem)
        for g in 0..<nGem { gemeinden.append(string(Int(u32(gems, 8 * g + 4)))) }
        let gkz = (0..<nGem).map { u32(gems, 8 * $0) }

        var out: [PlaceRecord] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            let o = 28 * i
            let lat = Double(i32(recs, o)) / 1e6, lon = Double(i32(recs, o + 4)) / 1e6
            let parts = string(Int(u32(recs, o + 8))).split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
            let extraOff = u32(recs, o + 12)
            let modes = Int(u16(recs, o + 16)), weight = Int(u16(recs, o + 18)), gem = Int(u16(recs, o + 20))
            let stateCode = Int(recs[o + 22]), kindCode = recs[o + 23], flags = recs[o + 24], pclass = Int(recs[o + 25])
            guard parts.count >= 2 else { throw error("RECS") }
            let state = stateCode < stateCodes.count ? stateCodes[stateCode] : ""
            var rec = PlaceRecord(id: parts[0], name: parts[1], aliases: Array(parts.dropFirst(2)), lat: lat, lon: lon,
                                  kind: kindCode == 1 ? .town : .stop, products: modes, importance: 0.5,
                                  country: state == "X" ? "" : "at", state: state,
                                  municipality: gem != 0xFFFF && gem < gemeinden.count ? gemeinden[gem] : "",
                                  localityClass: kindCode == 1 && pclass < placeClasses.count ? placeClasses[pclass] : nil,
                                  weight: weight, flags: flags)
            if gem != 0xFFFF && gem < nGem {
                rec.gemIndex = UInt16(gem)
                rec.gkz = gkz[gem]
            }
            if extraOff != 0xFFFF_FFFF {
                let e = Int(extraOff)
                guard e < extr.count else { throw error("EXTR") }
                let count = Int(extr[e])
                guard e + 1 + 5 * count <= extr.count else { throw error("EXTR") }
                var ex = PlaceRecord.Extras()
                var hasExtras = false
                for j in 0..<count {
                    let tag = extr[e + 1 + 5 * j]
                    let v = u32(extr, e + 2 + 5 * j)
                    switch tag {
                    case 1: ex.eva = Int(v); hasExtras = true
                    case 2: ex.hafasExtId = Int(v); hasExtras = true
                    case 3: ex.legacyIDs.append(string(Int(v))); hasExtras = true
                    case 5: rec.legacyLines = string(Int(v))    // v1 only (v2: LSTP)
                    case 6: ex.uic = Int(v); hasExtras = true
                    case 7: ex.mainStopID = string(Int(v)); hasExtras = true
                    default: break     // 4 = main stop record index (merged files): resolved by id instead
                    }
                }
                if hasExtras { rec.setExtras(ex) }
            }
            if rec.kind != .town, modes & 4157 != 0 || rec.eva != nil { rec.kind = .station }
            out.append(rec)
        }
        return out
    }
}

/// The decoded sections of one KBPL v2 layer file (places.bin official layer or stops_osm.bin), CRC-checked, for the
/// enrichment parser (WP-C2). Record sections (RECS, GEMS, EXTR) are not kept; STRS is (line refs and names point
/// into it).
struct PlaceLayer: Sendable {
    /// Sections the enrichment reads; unknown fourccs are skipped (ENRICH_SPEC §1.2).
    static let enrichmentSections = ["STRS", "LCAT", "LNAM", "LPAT", "LSTP", "RPRD", "GTAG", "TAGS", "META", "BASE"]

    let version: Int
    let nRecords: Int
    let nGemeinden: Int
    let nStopRecords: Int
    let sections: [String: [UInt8]]

    /// `strings`: the already decoded STRS of the records pass (not decoded twice).
    init(container c: KBPLContainer, strings: [UInt8]?) throws {
        version = c.version
        nRecords = c.nRecords
        nGemeinden = c.nGemeinden
        nStopRecords = c.nStopRecords
        var s: [String: [UInt8]] = [:]
        for tag in Self.enrichmentSections {
            if tag == "STRS", let strings { s[tag] = strings; continue }
            if let bytes = try c.section(tag) { s[tag] = bytes }
        }
        sections = s
    }

    init(version: Int = 2, nRecords: Int, nGemeinden: Int = 0, nStopRecords: Int, sections: [String: [UInt8]]) {
        self.version = version
        self.nRecords = nRecords
        self.nGemeinden = nGemeinden
        self.nStopRecords = nStopRecords
        self.sections = sections
    }

    func section(_ fourcc: String) -> [UInt8]? { sections[fourcc] }

    /// Lines of this layer's catalogue (`LCAT` × 24 B).
    var lineCount: Int { (sections["LCAT"]?.count ?? 0) / 24 }

    /// Per stop record: does `LSTP` list at least one line (`u8 count[nStopRecords]` prefix)?
    func stopsWithLines() -> [Bool] {
        guard let l = sections["LSTP"], l.count >= nStopRecords else { return [] }
        return (0..<nStopRecords).map { l[$0] > 0 }
    }

    /// `META` as JSON (nil if absent or not an object).
    var metaJSON: [String: Any]? {
        guard let m = sections["META"] else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(m))) as? [String: Any]
    }
}
