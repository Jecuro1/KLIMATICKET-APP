import Foundation
@testable import KlimaCore

/// Reads app sources the Appearance tests compare against (Theme.swift, Haptics.swift, AppIconStore.swift).
enum AppearanceRepo {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Appearance
        .deletingLastPathComponent()   // KlimaCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // KlimaCore
        .deletingLastPathComponent()   // Packages
        .deletingLastPathComponent()   // repo

    static func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// The `case` names of `enum <name>` in `source` (single-line case lists, comments ignored).
    static func enumCases(_ name: String, in source: String) -> [String] {
        guard let start = source.range(of: "enum \(name)") else { return [] }
        var depth = 0, body = ""
        var started = false
        for ch in source[start.upperBound...] {
            if ch == "{" { depth += 1; started = true; if depth == 1 { continue } }
            if ch == "}" { depth -= 1; if started && depth == 0 { break } }
            if started && depth == 1 { body.append(ch) }
        }
        var cases: [String] = []
        for raw in body.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("case ") else { continue }
            let list = line.dropFirst(5).split(separator: "/").first ?? ""
            for name in list.split(separator: ",") {
                let id = name.trimmingCharacters(in: .whitespaces).prefix { $0.isLetter || $0.isNumber || $0 == "_" }
                if !id.isEmpty { cases.append(String(id)) }
            }
        }
        return cases
    }
}

extension String {
    /// Formatter output uses a no-break space between "€" and the number.
    var plainSpaces: String { replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ") }
}
