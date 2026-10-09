import Foundation

/// Which Austrian Verkehrsverbund a station probably belongs to (SPEC §B4.1). A *hint* only: it decides whether the
/// VAO Verbund tariff is asked first; VAO itself is the authority (`NA` across Verbund borders → shop).
///
/// | Station id | Verbund |
/// |---|---|
/// | `at:41` Burgenland, `at:43` Niederösterreich, `at:49` Wien, `wl:` | VOR |
/// | `at:42` Kärnten | VKG |
/// | `at:44` Oberösterreich | OÖVV |
/// | `at:45` Salzburg | SVV |
/// | `at:46` Steiermark | STV |
/// | `at:47` Tirol | VVT |
/// | `at:48` Vorarlberg | VVV |
/// | `uic:`, `osm:` and others | nil (unless a VAO lid embeds `i=A×at:NN:` or an `L=NN…` IFOPT number) |
public enum VerbundArea {
    /// Verbund short names by IFOPT area code (the two digits after `at:`).
    static let byArea: [Int: String] = [41: "VOR", 42: "VKG", 43: "VOR", 44: "OÖVV", 45: "SVV", 46: "STV", 47: "VVT", 48: "VVV", 49: "VOR"]

    /// Verbund hint for an app station id ("at:47:1187" → "VVT", "wl:60201349" → "VOR"); nil when unknown.
    public static func hint(stationID: String?) -> String? {
        guard let id = stationID?.trimmingCharacters(in: .whitespaces), !id.isEmpty else { return nil }
        let parts = id.split(separator: ":", omittingEmptySubsequences: false)
        switch parts.first {
        case "wl": return "VOR"
        case "at":
            guard parts.count >= 2, let area = Int(parts[1]) else { return nil }
            return byArea[area]
        default: return nil
        }
    }

    /// Verbund hint from a VAO lid: the embedded IFOPT id (`…@i=A×at:44:42505@`) or the IFOPT-derived stop number
    /// (`A=1@L=444250500@` = area 44, stop 42505, platform 00). EVA lids (`L=8100227`) give nil.
    public static func hint(vaoLid: String?) -> String? {
        guard let lid = vaoLid else { return nil }
        for part in lid.split(separator: "@") {
            if part.hasPrefix("i="), let r = part.range(of: "at:") {
                if let h = hint(stationID: String(part[r.lowerBound...])) { return h }
            }
        }
        for part in lid.split(separator: "@") where part.hasPrefix("L=") {
            let digits = part.dropFirst(2)
            guard digits.count == 9, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let area = Int(digits.prefix(2)) else { continue }
            return byArea[area]
        }
        return nil
    }

    /// Hint for a price endpoint: station id first, then a VAO lid if one is known.
    public static func hint(_ endpoint: PriceEndpoint, vaoLid: String? = nil) -> String? {
        hint(stationID: endpoint.stationID) ?? hint(vaoLid: vaoLid)
    }

    /// Both hints known and equal.
    public static func same(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return false }
        return a == b
    }
}
