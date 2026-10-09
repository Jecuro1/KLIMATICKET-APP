import Foundation

/// Decodes ÖBB HAFAS (Scotty, `fahrplan.oebb.at/gate`) `LocMatch` / `LocGeoPos` responses into live `Place` rows
/// (SUGGEST_SPEC §6.2, §6.5). Tolerant: unknown keys ignored, every field optional; HAMM / service errors → `[]`.
///
/// The request itself belongs to the HAFAS client (OEBB_LIVE §A3.3); for LocMatch it must be exactly
/// `{"meth":"LocMatch","req":{"input":{"loc":{"type":"ALL","name":"<text>?"},"maxLoc":10,"field":"S"}}}` –
/// any other key makes the server reject the whole envelope (`err:"HAMM"`). `locMatchRequest(_:)` builds it.
public enum LocMatchDecoder {
    struct Envelope: Decodable {
        var err: String?
        var svcResL: [SvcRes]?
    }
    struct SvcRes: Decodable {
        var meth: String?
        var err: String?
        var res: Res?
    }
    struct Res: Decodable {
        var common: Common?
        var match: Match?
        var locL: [Loc]?
    }
    struct Common: Decodable { var icoL: [Ico]? }
    struct Ico: Decodable {
        var res: String?
        var txtA: String?
    }
    struct Match: Decodable { var locL: [Loc]? }
    struct Crd: Decodable {
        var x: Int?
        var y: Int?
    }
    struct GlobalID: Decodable {
        var id: String?
        var type: String?
    }
    struct Loc: Decodable {
        var lid: String?
        var type: String?
        var name: String?
        var extId: String?
        var crd: Crd?
        var pCls: Int?
        var wt: Int?
        var meta: Bool?
        var icoX: Int?
        var countryCodeL: [String]?
        var dist: Int?
        var dur: Int?
        var state: String?
    }

    /// LocMatch request body (`svcReqL` element) for typed text, as Scotty expects it.
    public static func locMatchRequest(_ text: String, maxLoc: Int = 10) -> [String: Any] {
        ["meth": "LocMatch",
         "req": ["input": ["loc": ["type": "ALL", "name": text.trimmingCharacters(in: .whitespaces) + "?"],
                           "maxLoc": maxLoc, "field": "S"]]]
    }

    /// Live rows of the first `svcResL` element of a LocMatch response, in Scotty's order (`liveRank` 1…), with
    /// POI duplicates "(1)/(2)" (P1) and town/station meta pairs (C1) collapsed.
    public static func places(fromResponse data: Data) -> [Place] {
        guard let env = try? JSONDecoder().decode(Envelope.self, from: data),
              let svc = env.svcResL?.first, svc.err == "OK", let res = svc.res else { return [] }
        let icons = res.common?.icoL ?? []
        let locs = res.match?.locL ?? res.locL ?? []
        return collapse(locs.enumerated().compactMap { place(from: $0.element, rank: $0.offset + 1, icons: icons) })
    }

    /// Nearby stops of a LocGeoPos response with HAFAS' walking distance (metres), nearest first.
    public static func nearby(fromResponse data: Data) -> [(place: Place, distanceMeters: Double)] {
        guard let env = try? JSONDecoder().decode(Envelope.self, from: data),
              let svc = env.svcResL?.first, svc.err == "OK", let res = svc.res else { return [] }
        let icons = res.common?.icoL ?? []
        return (res.locL ?? res.match?.locL ?? []).enumerated().compactMap { k, l in
            guard let p = place(from: l, rank: k + 1, icons: icons) else { return nil }
            return (place: p, distanceMeters: Double(l.dist ?? 0))
        }
    }

    /// HAFAS walking time of a nearby row (`dur`), seconds – equals `Place.walkSeconds(meters: dist)` ± 0.5 s.
    static func durations(fromResponse data: Data) -> [(dist: Int, dur: Int)] {
        guard let env = try? JSONDecoder().decode(Envelope.self, from: data),
              let res = env.svcResL?.first?.res else { return [] }
        return (res.locL ?? []).compactMap { l in l.dist.flatMap { d in l.dur.map { (d, $0) } } }
    }

    /// Bundesland hint of a HAFAS extId: 6-digit Verbund stops → 1st digit, 7-digit metas 11/12/13/14 → 3rd digit.
    public static func stateFromExtId(_ ext: String?) -> String? {
        guard let ext else { return nil }
        let m: [Character: String] = ["1": "B", "2": "K", "3": "NÖ", "4": "OÖ", "5": "S", "6": "ST", "7": "T", "8": "V", "9": "W"]
        let c = Array(ext)
        if c.count == 6 { return m[c[0]] }
        if c.count == 7, ["11", "12", "13", "14"].contains(String(c[0...1])) { return m[c[2]] }
        return nil
    }

    static func place(from l: Loc, rank: Int, icons: [Ico]) -> Place? {
        guard let name = l.name, !name.isEmpty, let x = l.crd?.x, let y = l.crd?.y else { return nil }
        let type = l.type ?? "S"
        var kind: PlaceKind = type == "A" ? .address : (type == "P" ? .poi : .stop)
        let products = l.pCls ?? 0
        var country = l.countryCodeL?.first ?? (type != "S" ? "at" : "")
        var importance = 0.6
        var state: String?
        var category: String?, label: String?
        if type == "S" {
            importance = l.wt.map { PlaceDataset.importance(wt: $0) } ?? PlaceDataset.importanceDefault(products: products)
            if l.meta == true, let e = l.extId, e.hasPrefix("11") { kind = .town }
            state = stateFromExtId(l.extId)
            if country.isEmpty { country = state != nil ? "at" : "" }
        } else if let i = l.icoX, i >= 0, i < icons.count {
            category = icons[i].res
            label = icons[i].txtA
        }
        return Place(id: "live:\(type):\(l.extId ?? l.lid ?? name)", kind: kind, name: name,
                     coordinate: GeoPoint(latitude: Double(y) / 1e6, longitude: Double(x) / 1e6),
                     products: PlaceProducts(rawValue: products), importance: importance, state: state, country: country,
                     extId: l.extId, lid: l.lid, isMeta: l.meta == true, weight: l.wt, liveRank: rank,
                     poiCategory: category, poiCategoryLabel: label, source: .live)
    }

    /// P1: POIs "Name (1)", "Name (2)" within 150 m are one place. C1: HAFAS publishes the locality meta and the
    /// station meta of a place with identical coordinates, products and weight → keep the station meta (12…/13…),
    /// add the other name as alias, rank = min.
    static func collapse(_ input: [Place]) -> [Place] {
        var pois: [Place] = []
        var rest: [Place] = []
        for var r in input {
            if r.kind == .poi {
                let base = PlaceNames.strippingPOICounter(r.name)
                if pois.contains(where: { $0.name == base && distance($0, r) <= 150 }) { continue }
                r.name = base
                pois.append(r)
            }
            rest.append(r)
        }
        var keep: [Place] = []
        for r in rest {
            let dupIndex = keep.firstIndex { k in
                (r.kind == .stop || r.kind == .town) && (k.kind == .stop || k.kind == .town) && r.isMeta && k.isMeta
                    && r.products == k.products && r.weight == k.weight && distance(r, k) <= 60
            }
            guard let di = dupIndex else { keep.append(r); continue }
            let dup = keep[di]
            let rIsStation = (r.extId ?? "").hasPrefix("12") || (r.extId ?? "").hasPrefix("13")
            var station = rIsStation ? r : dup
            let other = rIsStation ? dup : r
            station.aliases.append(other.name)
            station.liveRank = min(r.liveRank ?? 99, dup.liveRank ?? 99)
            station.kind = .station
            keep[di] = station
        }
        return keep
    }

    private static func distance(_ a: Place, _ b: Place) -> Double {
        PlaceTable.haversine(a.coordinate.latitude, a.coordinate.longitude, b.coordinate.latitude, b.coordinate.longitude)
    }
}
