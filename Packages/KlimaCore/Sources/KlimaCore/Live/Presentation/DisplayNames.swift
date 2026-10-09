import Foundation

/// Station display names (SPEC §C3.3, port of the reference `ux/client.py display_name`):
/// a trailing `(…)` becomes `sub`, `St.X` becomes `St. X`, a trailing „ Bahnhof“ is dropped and „Hauptbahnhof“
/// becomes „Hbf“. „Langen am Arlberg Bahnhof (Vorplatz)“ → name „Langen am Arlberg“, sub „Vorplatz“.
public enum DisplayNames {
    public static func make(_ raw: String) -> DisplayName {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var name = trimmed
        var sub: String?
        if let m = bracket?.firstMatch(in: name), m.count == 3, !m[1].isEmpty {
            name = m[1]
            sub = m[2].trimmingCharacters(in: .whitespaces).nilIfEmpty
        }
        if let st = saintDot { name = st.replace(in: name, with: "St. ") }
        if let bf = trailingBahnhof { name = bf.replace(in: name, with: "") }
        name = name.replacingOccurrences(of: "Hauptbahnhof", with: "Hbf").trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = trimmed }
        return DisplayName(raw: raw, name: name, sub: sub)
    }

    /// Shorthand for `make(raw).name`.
    public static func name(_ raw: String) -> String { make(raw).name }

    // `^(.*?)\s*\(([^)]+)\)$`, `\bSt\.(?=\S)`, `\s+Bahnhof$` (patterns of the reference).
    private static let bracket = PatternRegex(#"^(.*?)\s*\(([^)]+)\)$"#)
    private static let saintDot = PatternRegex(#"\bSt\.(?=\S)"#)
    private static let trailingBahnhof = PatternRegex(#"\s+Bahnhof$"#)
}

/// Small immutable regex helper for the presentation layer (thread-safe like `NSRegularExpression`).
struct PatternRegex: @unchecked Sendable {
    let regex: NSRegularExpression

    init?(_ pattern: String) {
        guard let r = try? NSRegularExpression(pattern: pattern) else { return nil }
        regex = r
    }

    /// Capture groups of the first match (index 0 = whole match; "" for a group that did not take part).
    func firstMatch(in text: String) -> [String]? {
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    func replace(in text: String, with template: String) -> String {
        let ns = text as NSString
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length),
                                              withTemplate: NSRegularExpression.escapedTemplate(for: template))
    }
}
