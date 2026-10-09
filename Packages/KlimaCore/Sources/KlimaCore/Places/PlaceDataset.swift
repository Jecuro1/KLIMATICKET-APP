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
    /// Lines serving the stop ("" = none); usually ≤ 15 bytes, so stored inline.
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
    var lines: String? {
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

/// Reader for the binary place files built by `scripts/build_places.py` (format: see its docstring).
/// `places.bin` holds every Austrian stop (Verbund list + ÖBB/Wiener Linien/Steiermark open data),
/// `localities.bin` the OSM localities (ODbL) referencing their main stop by id.
public struct PlaceDataset: Sendable {
    static let stateCodes = ["X", "B", "K", "NÖ", "OÖ", "S", "ST", "T", "V", "W"]
    static let placeClasses: [String?] = [nil, "city", "town", "village", "suburb", "hamlet", "neighbourhood", "quarter",
                                         "isolated_dwelling"]

    public enum ReadError: Error, Equatable {
        case badMagic, unsupportedVersion(Int), truncated
    }

    var stops: [PlaceRecord]
    var localities: [PlaceRecord]

    public var stopCount: Int { stops.count }
    public var localityCount: Int { localities.count }

    init(stops: [PlaceRecord], localities: [PlaceRecord]) {
        self.stops = stops
        self.localities = localities
    }

    /// Decodes `places.bin` and (optionally) `localities.bin`.
    public init(places: Data, localities: Data?) throws {
        let p = try Self.decode(places)
        var stops = p.filter { $0.kind != .town }
        var locs = p.filter { $0.kind == .town }
        if let localities { locs += try Self.decode(localities).filter { $0.kind == .town } }
        Self.computeImportance(stops: &stops, localities: &locs)
        self.stops = stops
        self.localities = locs
    }

    public init(placesURL: URL, localitiesURL: URL?) throws {
        let p = try Data(contentsOf: placesURL, options: .mappedIfSafe)
        let l = try localitiesURL.map { try Data(contentsOf: $0, options: .mappedIfSafe) }
        try self.init(places: p, localities: l)
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

    static func decode(_ data: Data) throws -> [PlaceRecord] {
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> [PlaceRecord] in
            guard raw.count >= 64 else { throw ReadError.truncated }
            func u32(_ o: Int) -> UInt32 { raw.loadUnaligned(fromByteOffset: o, as: UInt32.self).littleEndian }
            func u16(_ o: Int) -> UInt16 { raw.loadUnaligned(fromByteOffset: o, as: UInt16.self).littleEndian }
            func i32(_ o: Int) -> Int32 { raw.loadUnaligned(fromByteOffset: o, as: Int32.self).littleEndian }
            guard raw[0] == 0x4B, raw[1] == 0x42, raw[2] == 0x50, raw[3] == 0x4C else { throw ReadError.badMagic }  // "KBPL"
            let version = Int(u16(4))
            guard version == 1 else { throw ReadError.unsupportedVersion(version) }
            let n = Int(u32(8)), nGem = Int(u32(12))
            let offRec = Int(u32(16)), lenRec = Int(u32(20)), offStr = Int(u32(24)), lenStr = Int(u32(28))
            let offGem = Int(u32(32)), lenGem = Int(u32(36)), offEx = Int(u32(40)), lenEx = Int(u32(44))
            guard lenRec == n * 28, offRec + lenRec <= raw.count, offStr + lenStr <= raw.count,
                  offGem + lenGem <= raw.count, offEx + lenEx <= raw.count, lenGem >= nGem * 8 else { throw ReadError.truncated }

            func string(_ o: Int) -> String {
                let start = offStr + o
                guard start < offStr + lenStr else { return "" }
                var end = start
                while end < offStr + lenStr && raw[end] != 0 { end += 1 }
                return String(decoding: UnsafeRawBufferPointer(rebasing: raw[start..<end]), as: UTF8.self)
            }
            var gemeinden: [String] = []
            gemeinden.reserveCapacity(nGem)
            for g in 0..<nGem { gemeinden.append(string(Int(u32(offGem + 8 * g + 4)))) }

            var out: [PlaceRecord] = []
            out.reserveCapacity(n)
            for i in 0..<n {
                let o = offRec + 28 * i
                let lat = Double(i32(o)) / 1e6, lon = Double(i32(o + 4)) / 1e6
                let parts = string(Int(u32(o + 8))).split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
                let extraOff = u32(o + 12)
                let modes = Int(u16(o + 16)), weight = Int(u16(o + 18)), gem = Int(u16(o + 20))
                let stateCode = Int(raw[o + 22]), kindCode = raw[o + 23], flags = raw[o + 24], pclass = Int(raw[o + 25])
                guard parts.count >= 2 else { throw ReadError.truncated }
                let state = stateCode < stateCodes.count ? stateCodes[stateCode] : ""
                var rec = PlaceRecord(id: parts[0], name: parts[1], aliases: Array(parts.dropFirst(2)), lat: lat, lon: lon,
                                      kind: kindCode == 1 ? .town : .stop, products: modes, importance: 0.5,
                                      country: state == "X" ? "" : "at", state: state,
                                      municipality: gem != 0xFFFF && gem < gemeinden.count ? gemeinden[gem] : "",
                                      localityClass: kindCode == 1 && pclass < placeClasses.count ? placeClasses[pclass] : nil,
                                      weight: weight, flags: flags)
                if extraOff != 0xFFFF_FFFF {
                    let e = offEx + Int(extraOff)
                    guard e < offEx + lenEx else { throw ReadError.truncated }
                    let count = Int(raw[e])
                    guard e + 1 + 5 * count <= offEx + lenEx else { throw ReadError.truncated }
                    var ex = PlaceRecord.Extras()
                    var hasExtras = false
                    for j in 0..<count {
                        let tag = raw[e + 1 + 5 * j]
                        let v = u32(e + 2 + 5 * j)
                        switch tag {
                        case 1: ex.eva = Int(v); hasExtras = true
                        case 2: ex.hafasExtId = Int(v); hasExtras = true
                        case 3: ex.legacyIDs.append(string(Int(v))); hasExtras = true
                        case 5: rec.lines = string(Int(v))
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

}
