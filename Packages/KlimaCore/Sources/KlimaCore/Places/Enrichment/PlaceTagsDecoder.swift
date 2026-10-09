import Foundation

/// A per-stop section (`LSTP`, `TAGS`): `u8 count[nStopRecords]`, then the entries of all stops in record order.
/// The byte offset of every stop is computed once at load (prefix scan). A section whose entries do not end exactly
/// at its length is rejected (nil), so a broken layer turns its feature off instead of reading garbage.
struct PerStopSection: Sendable {
    let bytes: [UInt8]
    /// Offset of stop i's first entry; `offsets[n]` = end.
    let offsets: [Int32]
    let countMask: UInt8

    /// `width(bytes, p)` = byte width of the entry at `p` (needs ≤ 3 bytes at p to be readable).
    init?(_ bytes: [UInt8]?, stops n: Int, countMask: UInt8, minEntry: Int, width: ([UInt8], Int) -> Int) {
        guard let b = bytes, n >= 0, b.count >= n else { return nil }
        var offs = [Int32](repeating: 0, count: n + 1)
        var p = n
        for i in 0..<n {
            offs[i] = Int32(p)
            for _ in 0..<Int(b[i] & countMask) {
                guard p + minEntry <= b.count else { return nil }
                let w = width(b, p)
                guard w >= minEntry, p + w <= b.count else { return nil }
                p += w
            }
        }
        guard p == b.count else { return nil }
        offs[n] = Int32(p)
        self.bytes = b
        offsets = offs
        self.countMask = countMask
    }

    func count(_ i: Int) -> Int { Int(bytes[i] & countMask) }

    /// LSTP entry: `u16 line · u8 bits (0–1 confidence, 2–3 nTo, 4–5 nNext) · nTo × u16 LNAM · nNext × u16 stop`.
    static func lstp(_ bytes: [UInt8]?, stops n: Int) -> PerStopSection? {
        PerStopSection(bytes, stops: n, countMask: 0xFF, minEntry: 3) { b, p in
            let f = b[p + 2]
            return 3 + 2 * Int((f >> 2) & 3) + 2 * Int((f >> 4) & 3)
        }
    }

    /// TAGS entry: `u8 key (bit 7 = aux follows) · u8 confidence · u16 value · [u16 aux]`; count bit 7 = override.
    static func tags(_ bytes: [UInt8]?, stops n: Int) -> PerStopSection? {
        PerStopSection(bytes, stops: n, countMask: 0x7F, minEntry: 4) { b, p in b[p] & 0x80 != 0 ? 6 : 4 }
    }
}

/// Tag keys the reader understands (resolved by name from META `keys`, never by number).
enum TagKey: String, Sendable {
    case type, service, region, wheelchair, landscape, klimaticket, railTransfer, lift, ski, skiAlliance, nationalPark,
         glacierSki, glacier, hut
}

/// One decoded tag entry.
struct RawTag {
    var key: TagKey
    var value: String
    var confidence: Int
    var distance: Int?
}

/// Tags of one layer: the per-stop section plus the layer's own `keys` / `vals` tables.
struct TagLayer: Sendable {
    let section: PerStopSection
    let keys: [TagKey?]
    let vals: [String]

    init?(layer: PlaceLayer?, stops n: Int, meta: [String: Any]?) {
        guard let layer, let s = PerStopSection.tags(layer.section("TAGS"), stops: n) else { return nil }
        section = s
        keys = (meta?["keys"] as? [String] ?? []).map { TagKey(rawValue: $0) }
        vals = meta?["vals"] as? [String] ?? []
    }

    /// Override bit of the official layer: the stop lists its own region/landscape set (GTAG does not apply).
    func overridesGemeinde(_ i: Int) -> Bool { section.bytes[i] & 0x80 != 0 }

    /// Key, value index and confidence of every tag of stop i (no string work).
    func forEachIndex(_ i: Int, _ body: (TagKey, Int, Int) -> Void) {
        let b = section.bytes
        var p = Int(section.offsets[i])
        for _ in 0..<section.count(i) {
            let kb = b[p], v = Int(Bytes.u16(b, p + 2)), k = Int(kb & 0x7F)
            if k < keys.count, let key = keys[k], v < vals.count { body(key, v, Int(b[p + 1])) }
            p += kb & 0x80 != 0 ? 6 : 4
        }
    }

    func forEach(_ i: Int, _ body: (RawTag) -> Void) {
        let b = section.bytes
        var p = Int(section.offsets[i])
        for _ in 0..<section.count(i) {
            let kb = b[p], conf = Int(b[p + 1]), v = Int(Bytes.u16(b, p + 2))
            let hasAux = kb & 0x80 != 0
            let k = Int(kb & 0x7F)
            if k < keys.count, let key = keys[k], v < vals.count {
                body(RawTag(key: key, value: vals[v], confidence: conf, distance: hasAux ? Int(Bytes.u16(b, p + 4)) : nil))
            }
            p += hasAux ? 6 : 4
        }
    }
}

/// `GTAG`: Gemeinde tag defaults in GEMS order (`u8 count`, count × `u8 key · u8 conf · u16 value`).
struct GemeindeTags: Sendable {
    let bytes: [UInt8]
    let offsets: [Int32]
    let keys: [TagKey?]
    let vals: [String]

    init?(_ bytes: [UInt8]?, gemeinden: Int, meta: [String: Any]?) {
        guard let b = bytes else { return nil }
        var offs: [Int32] = []
        offs.reserveCapacity(gemeinden)
        var p = 0
        while p < b.count {
            offs.append(Int32(p))
            p += 1 + 4 * Int(b[p])
        }
        guard p == b.count, offs.count == gemeinden || gemeinden == 0 else { return nil }
        self.bytes = b
        offsets = offs
        keys = (meta?["keys"] as? [String] ?? []).map { TagKey(rawValue: $0) }
        vals = meta?["vals"] as? [String] ?? []
    }

    func forEachIndex(gemeinde g: Int, _ body: (TagKey, Int, Int) -> Void) {
        guard g >= 0, g < offsets.count else { return }
        let p = Int(offsets[g])
        for k in 0..<Int(bytes[p]) {
            let o = p + 1 + 4 * k
            let key = Int(bytes[o] & 0x7F), v = Int(Bytes.u16(bytes, o + 2))
            if key < keys.count, let tk = keys[key], v < vals.count { body(tk, v, Int(bytes[o + 1])) }
        }
    }

    func forEach(gemeinde g: Int, _ body: (RawTag) -> Void) {
        guard g >= 0, g < offsets.count else { return }
        let p = Int(offsets[g])
        for k in 0..<Int(bytes[p]) {
            let o = p + 1 + 4 * k
            let key = Int(bytes[o] & 0x7F), conf = Int(bytes[o + 1]), v = Int(Bytes.u16(bytes, o + 2))
            if key < keys.count, let tk = keys[key], v < vals.count {
                body(RawTag(key: tk, value: vals[v], confidence: conf, distance: nil))
            }
        }
    }
}

/// Builds `PlaceTags` from the raw tags of a stop (M5): official per-stop tags, the Gemeinde defaults unless the stop
/// overrides them, the OSM layer; state, Gemeinde and Bezirk from the record. Duplicates keep the highest confidence.
struct PlaceTagsBuilder {
    var tags = PlaceTags()
    // small per-stop lists (a stop has a handful of tags): arrays with linear search beat dictionaries here
    private var ski: [ScoredTag] = []
    private var regions: [ScoredTag] = []
    private var landscapes: [ScoredTag] = []
    private var types: [PlaceTypeTag] = []
    private var wheelchairConf = -1
    private var liftConf = -1
    private var klimaTicket: String?

    init() {}

    mutating func add(_ t: RawTag, catalog: SkiAreaCatalog) {
        switch t.key {
        case .type:
            guard let pt = PlaceType(rawValue: t.value) else { return }
            if let k = types.firstIndex(where: { $0.type == pt }) {
                if t.confidence > types[k].confidence {
                    types[k] = PlaceTypeTag(type: pt, confidence: t.confidence, distanceMeters: t.distance)
                }
            } else {
                types.append(PlaceTypeTag(type: pt, confidence: t.confidence, distanceMeters: t.distance))
            }
        case .service:
            if let s = PlaceService(rawValue: t.value), !tags.services.contains(s) { tags.services.append(s) }
        case .region:
            Self.keepBest(t, in: &regions)
        case .landscape:
            Self.keepBest(t, in: &landscapes)
        case .ski:
            Self.keepBest(t, in: &ski)
        case .skiAlliance:
            // E5: only verified alliances surface
            if catalog.areas[t.value]?.isVerified == true, !tags.skiAlliances.contains(t.value) { tags.skiAlliances.append(t.value) }
        case .glacierSki:
            if tags.glacierSkiArea == nil { tags.glacierSkiArea = t.value }
        case .wheelchair:
            if t.confidence > wheelchairConf, let a = Accessibility(rawValue: t.value) {
                tags.accessibility = a
                wheelchairConf = t.confidence
            }
        case .klimaticket:
            if klimaTicket == nil { klimaTicket = t.value }
        case .railTransfer:
            if (tags.railTransfer?.confidence ?? -1) < t.confidence { tags.railTransfer = Self.scored(t) }
        case .lift:
            guard t.confidence > liftConf || (t.confidence == liftConf
                                               && (t.distance ?? .max) < (tags.lift?.distanceMeters ?? .max)) else { return }
            var name = t.value, role = LiftStation.Role.unknown, type: String?
            if t.value.hasPrefix("#lift") {
                guard let k = Int(t.value.dropFirst(5)), k >= 0, k < catalog.lifts.count else { return }
                let e = catalog.lifts[k]
                (name, role, type) = (e.name, e.role, e.type)
            }
            guard !name.isEmpty else { return }
            tags.lift = LiftStation(name: name, role: role, liftType: type, distanceMeters: t.distance, confidence: t.confidence)
            liftConf = t.confidence
        case .nationalPark:
            if (tags.nationalPark?.confidence ?? -1) < t.confidence { tags.nationalPark = Self.scored(t) }
        case .glacier:
            if (tags.glacier?.confidence ?? -1) < t.confidence { tags.glacier = Self.scored(t) }
        case .hut:
            if (tags.hut?.confidence ?? -1) < t.confidence { tags.hut = Self.scored(t) }
        }
    }

    private static func scored(_ t: RawTag) -> ScoredTag {
        ScoredTag(id: t.value, confidence: t.confidence, distanceMeters: t.distance)
    }

    private static func keepBest(_ t: RawTag, in list: inout [ScoredTag]) {
        if let k = list.firstIndex(where: { $0.id == t.value }) {
            if t.confidence > list[k].confidence { list[k] = scored(t) }
        } else {
            list.append(scored(t))
        }
    }

    /// Stable sort by confidence desc (first-seen order on ties).
    private static func byConfidence<T>(_ list: [T], _ conf: (T) -> Int) -> [T] {
        guard list.count > 1 else { return list }
        return list.enumerated().sorted { conf($0.1) != conf($1.1) ? conf($0.1) > conf($1.1) : $0.0 < $1.0 }.map(\.1)
    }

    mutating func finish(state: String?, gkz: Int?, catalog: SkiAreaCatalog) -> PlaceTags {
        tags.skiAreas = Self.byConfidence(ski, \.confidence)
        tags.regions = Self.byConfidence(regions, \.confidence)
        tags.landscapes = Self.byConfidence(landscapes, \.confidence)
        tags.types = Self.byConfidence(types, \.confidence)
        if let g = gkz, g > 0 {
            tags.gkz = g
            tags.bezirk = SkiAreaCatalog.bezirk(gkz: g)
            tags.wienBezirk = SkiAreaCatalog.wienBezirk(gkz: g)
        }
        tags.klimaTicket = Self.klimaTicket(klimaTicket, state: state, catalog: catalog)
        return tags
    }

    /// `yes|<ids>` (`+id` = Übergangsbereich), `check|<reason>`, `no|<reason>`, `border`; absent = KlimaTicket Ö +
    /// the state's default regional tickets.
    static func klimaTicket(_ v: String?, state: String?, catalog: SkiAreaCatalog) -> KlimaTicketValidity {
        guard let v, !v.isEmpty else {
            return KlimaTicketValidity(status: .valid, regionalTicketIDs: state.flatMap { catalog.defaultRegional[$0] } ?? [])
        }
        let parts = v.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let head = parts[0], rest = parts.count > 1 ? parts[1] : ""
        switch head {
        case "yes":
            let ids = rest.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return KlimaTicketValidity(status: .valid, regionalTicketIDs: ids.filter { !$0.hasPrefix("+") },
                                       extendedTicketIDs: ids.filter { $0.hasPrefix("+") }.map { String($0.dropFirst()) })
        case "check": return KlimaTicketValidity(status: .check, reason: rest.isEmpty ? nil : rest)
        case "no": return KlimaTicketValidity(status: .notIncluded, reason: rest.isEmpty ? nil : rest)
        case "border": return KlimaTicketValidity(status: .border, reason: rest.isEmpty ? nil : rest)
        default:
            return KlimaTicketValidity(status: .valid, regionalTicketIDs: state.flatMap { catalog.defaultRegional[$0] } ?? [])
        }
    }
}
