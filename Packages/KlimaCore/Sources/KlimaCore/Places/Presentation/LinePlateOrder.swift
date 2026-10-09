import Foundation

/// Display order and selection of line plates (docs/ENRICH_SPEC.md §2.5, BADGE_SPEC §2.1 „Sortierung und Auswahl“).
public enum LinePlateOrder {
    /// Fixed order of the long-distance and night categories.
    public static let longDistanceOrder = ["RJX", "RJ", "ICE", "ECE", "EC", "IC", "D", "TGV", "EN", "NJ", "WB"]
    /// Order of the regional categories (express products first, so a mixed station shows `REX` before `R`).
    public static let regionalOrder = ["REX", "CJX", "IR", "RE", "RX", "R", "RB"]

    /// Family order (`fern < nacht < regio < sBahn < uBahn < tram < bus < nachtbus < skibus < wanderbus < rufbus <
    /// sev < seilbahn < schiff < sonst`), inside a family the fixed category order, then natural order of the plate
    /// text (4 < 13A < 110 < 852). Duplicates by (family, plate text) are dropped; the first one wins, so pass the
    /// lines in source priority (timetable before OSM before live).
    public static func sorted(_ lines: [LineRef], services: [PlaceService] = []) -> [LineRef] {
        var seen = Set<String>()
        var keyed: [(line: LineRef, key: SortKey, pos: Int)] = []
        keyed.reserveCapacity(lines.count)
        for (i, line) in lines.enumerated() {
            let kind = LineKind.classify(line, services: services)
            let plate = LinePlateText.text(for: line, kind: kind, size: .l)
            guard seen.insert(LinePlateText.dedupeKey(kind: kind, plate: plate)).inserted else { continue }
            keyed.append((line, SortKey(kind: kind, text: plate.text, ref: line.ref), i))
        }
        keyed.sort { a, b in a.key == b.key ? a.pos < b.pos : a.key < b.key }
        return keyed.map(\.line)
    }

    /// Variety before completeness (search rows, map callouts, widgets): plates are taken round-robin across the
    /// families until `maxCount` are chosen; `shown` is in display order, `overflow` = the rest („+k“).
    /// Wien Floridsdorf → `REX S U6 25` + 20.
    public static func diverse(_ lines: [LineRef], maxCount: Int, services: [PlaceService] = [])
        -> (shown: [LineRef], overflow: Int) {
        let ordered = sorted(lines, services: services)
        guard maxCount > 0 else { return ([], ordered.count) }
        guard ordered.count > maxCount else { return (ordered, 0) }
        var buckets: [[Int]] = []
        var lastFamily = -1
        for (i, line) in ordered.enumerated() {
            let f = LineKind.classify(line, services: services).familyRank
            if f != lastFamily { buckets.append([]); lastFamily = f }
            buckets[buckets.count - 1].append(i)
        }
        var picked: [Int] = []
        var round = 0
        while picked.count < maxCount {
            for b in buckets where round < b.count && picked.count < maxCount { picked.append(b[round]) }
            round += 1
        }
        picked.sort()
        return (picked.map { ordered[$0] }, ordered.count - picked.count)
    }

    /// Natural order of plate texts, identical on iOS and Linux (`localizedStandardCompare` semantics for plate
    /// texts: digit runs compare numerically, letters case-insensitively): 4 < 13A < 110 < 852, S < S1 < S45.
    public static func naturalLess(_ a: String, _ b: String) -> Bool {
        naturalCompare(a, b) < 0
    }

    static func naturalCompare(_ a: String, _ b: String) -> Int {
        let x = Array(a.lowercased()), y = Array(b.lowercased())
        var i = 0, j = 0
        while i < x.count && j < y.count {
            if x[i].isNumber && y[j].isNumber {
                var ni = i, nj = j
                while ni < x.count && x[ni].isNumber { ni += 1 }
                while nj < y.count && y[nj].isNumber { nj += 1 }
                let da = String(x[i..<ni]).drop(while: { $0 == "0" }), db = String(y[j..<nj]).drop(while: { $0 == "0" })
                if da.count != db.count { return da.count < db.count ? -1 : 1 }
                if da != db { return da < db ? -1 : 1 }
                i = ni
                j = nj
            } else {
                if x[i] != y[j] { return x[i] < y[j] ? -1 : 1 }
                i += 1
                j += 1
            }
        }
        if x.count - i != y.count - j { return (x.count - i) < (y.count - j) ? -1 : 1 }
        return 0
    }

    struct SortKey: Equatable, Comparable {
        let family: Int
        let category: Int
        let text: String
        let ref: String

        init(kind: LineKind, text: String, ref: String) {
            family = kind.familyRank
            switch kind {
            case .fern, .nacht:
                category = LinePlateOrder.longDistanceOrder.firstIndex(of: text.uppercased()) ?? 99
            case .regio:
                let cat = RailRef(text).category.uppercased()
                category = LinePlateOrder.regionalOrder.firstIndex(of: cat) ?? 99
            default:
                category = 0
            }
            self.text = text
            self.ref = ref
        }

        static func < (a: SortKey, b: SortKey) -> Bool {
            if a.family != b.family { return a.family < b.family }
            if a.category != b.category { return a.category < b.category }
            let c = LinePlateOrder.naturalCompare(a.text, b.text)
            if c != 0 { return c < 0 }
            return LinePlateOrder.naturalCompare(a.ref, b.ref) < 0
        }
    }
}
