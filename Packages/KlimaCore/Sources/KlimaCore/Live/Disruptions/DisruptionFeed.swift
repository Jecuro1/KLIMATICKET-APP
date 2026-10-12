import Foundation

// Störungen: the HIM messages from HAFAS `HimSearch` (decoded by `HafasCodec.remarks`, kind `.disruption`).
// HIM messages carry no coordinates, so the filters are: transport mode (sent to the server as `himFltrL`), line
// (matched against `affectedLines`) and Bundesland (keywords in the title and text, a heuristic – see `AustrianRegion`).

/// Bundesland filter. Matching is on whole words of the normalised message text.
public enum AustrianRegion: String, CaseIterable, Sendable, Identifiable {
    case wien, niederoesterreich, burgenland, steiermark, kaernten, oberoesterreich, salzburg, tirol, vorarlberg

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .wien: "Wien"
        case .niederoesterreich: "Niederösterreich"
        case .burgenland: "Burgenland"
        case .steiermark: "Steiermark"
        case .kaernten: "Kärnten"
        case .oberoesterreich: "Oberösterreich"
        case .salzburg: "Salzburg"
        case .tirol: "Tirol"
        case .vorarlberg: "Vorarlberg"
        }
    }

    /// Normalised phrases (lower case, umlauts folded to `ae/oe/ue`, no punctuation, single spaces).
    public var keywords: [String] {
        switch self {
        case .wien: ["wien", "floridsdorf", "meidling"]
        case .niederoesterreich: ["niederoesterreich", "st poelten", "wiener neustadt", "amstetten", "mistelbach", "moedling"]
        case .burgenland: ["burgenland", "eisenstadt", "oberwart", "neusiedl"]
        case .steiermark: ["steiermark", "graz", "leoben", "bruck an der mur", "kapfenberg"]
        case .kaernten: ["kaernten", "klagenfurt", "villach", "spittal"]
        case .oberoesterreich: ["oberoesterreich", "linz", "wels", "steyr", "ried im innkreis"]
        case .salzburg: ["salzburg", "bischofshofen", "zell am see"]
        case .tirol: ["tirol", "innsbruck", "kufstein", "st anton", "landeck", "jenbach", "woergl"]
        case .vorarlberg: ["vorarlberg", "bregenz", "dornbirn", "feldkirch", "bludenz"]
        }
    }

    /// Whether the normalised `text` mentions this region.
    public func matches(normalizedText text: String) -> Bool {
        keywords.contains { text.contains(" \($0) ") }
    }
}

public extension String {
    /// Lower case, umlauts folded (ä→ae, ö→oe, ü→ue, ß→ss), every other non-letter/digit becomes a space, padded with
    /// spaces so that whole-word phrases can be found with `contains(" phrase ")`.
    var normalizedForRegion: String {
        var out = " "
        for ch in lowercased() {
            switch ch {
            case "ä": out += "ae"
            case "ö": out += "oe"
            case "ü": out += "ue"
            case "ß": out += "ss"
            default:
                if ch.isLetter || ch.isNumber { out.append(ch) } else { out.append(" ") }
            }
        }
        // Collapse runs of spaces.
        let parts = out.split(separator: " ")
        return " " + parts.joined(separator: " ") + " "
    }
}

public struct DisruptionFilter: Sendable, Hashable {
    /// Transport modes (server side, `himFltrL`). Default: every mode.
    public var products: ProductMask
    /// Free text matched against the affected line names ("S 4", "RJX"); empty = all lines.
    public var line: String
    public var region: AustrianRegion?
    /// Hide messages whose validity ended before `now`.
    public var onlyCurrent: Bool

    public init(products: ProductMask = .all, line: String = "", region: AustrianRegion? = nil, onlyCurrent: Bool = true) {
        self.products = products
        self.line = line
        self.region = region
        self.onlyCurrent = onlyCurrent
    }

    /// Request window: from now until `days` days ahead, so current and upcoming messages come back.
    public func query(now: Date, days: Int = 2, maxResults: Int = 60) -> RemarksQuery {
        RemarksQuery(from: now, to: now.addingTimeInterval(TimeInterval(max(days, 1)) * 86_400),
                     products: products == .all ? nil : products, maxResults: maxResults)
    }

    public func matches(_ remark: Remark, now: Date) -> Bool {
        guard remark.kind == .disruption else { return false }
        if onlyCurrent, let until = remark.validUntil, until < now { return false }
        if !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let hit = remark.affectedLines.contains { Self.lineMatches($0, query: line) }
            if !hit { return false }
        }
        if let region {
            let text = (remark.title ?? "").normalizedForRegion + " " + remark.text.normalizedForRegion
            if !region.matches(normalizedText: text) { return false }
        }
        return true
    }

    /// "S45" and "S 45" are the same line; "RJX" matches "RJX 66" (whole words). "S 4" does not match "S 45".
    static func lineMatches(_ affected: String, query: String) -> Bool {
        let a = affected.normalizedForRegion
        let q = query.normalizedForRegion
        if a.replacingOccurrences(of: " ", with: "") == q.replacingOccurrences(of: " ", with: "") { return true }
        return a.contains(q)
    }

    /// Filtered list, most recently changed first (`modifiedAt`, else `validFrom`).
    public func apply(_ remarks: [Remark], now: Date) -> [Remark] {
        remarks.filter { matches($0, now: now) }.sorted { a, b in
            let da = a.modifiedAt ?? a.validFrom ?? .distantPast
            let db = b.modifiedAt ?? b.validFrom ?? .distantPast
            return da != db ? da > db : (a.id ?? a.text) < (b.id ?? b.text)
        }
    }
}
