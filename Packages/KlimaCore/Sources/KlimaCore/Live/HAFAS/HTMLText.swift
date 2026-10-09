import Foundation

/// HIM / remark HTML → plain text (SPEC §A3.4): `<br>` → newline, every other tag removed, named and numeric
/// entities decoded, runs of more than two newlines collapsed, trimmed.
public enum HTMLText {
    static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "Ouml": "Ö", "ouml": "ö", "Auml": "Ä", "auml": "ä", "Uuml": "Ü", "uuml": "ü", "szlig": "ß",
        "eacute": "é", "egrave": "è", "agrave": "à", "ndash": "–", "mdash": "—", "euro": "€", "bdquo": "„", "ldquo": "“",
        "rdquo": "”", "hellip": "…",
    ]

    public static func plain(_ html: String?) -> String {
        guard let html, !html.isEmpty else { return "" }
        let chars = Array(html)
        // A "<" after the last ">" can never open a tag: skip the search (keeps garbage like "<<<<…" linear).
        let lastClose = chars.lastIndex(of: ">") ?? -1
        var out = ""
        out.reserveCapacity(chars.count)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "<", i < lastClose, let close = chars[(i + 1)...].firstIndex(of: ">") {
                let tag = String(chars[(i + 1)..<close]).lowercased().trimmingCharacters(in: .whitespaces)
                if tag == "br" || tag.hasPrefix("br/") || tag.hasPrefix("br ") { out.append("\n") }
                i = close + 1
                continue
            }
            if c == "&", let semi = chars[(i + 1)...].prefix(10).firstIndex(of: ";"), let decoded = entity(String(chars[(i + 1)..<semi])) {
                out.append(decoded)
                i = semi + 1
                continue
            }
            out.append(c)
            i += 1
        }
        return collapseNewlines(out).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func entity(_ name: String) -> String? {
        if name.hasPrefix("#x") || name.hasPrefix("#X") {
            guard let v = UInt32(name.dropFirst(2), radix: 16), let u = Unicode.Scalar(v) else { return nil }
            return String(Character(u))
        }
        if name.hasPrefix("#") {
            guard let v = UInt32(name.dropFirst()), let u = Unicode.Scalar(v) else { return nil }
            return String(Character(u))
        }
        return named[name]
    }

    /// "a\n \n\n\nb" → "a\n\nb": trailing spaces on lines are dropped and at most two consecutive newlines kept.
    private static func collapseNewlines(_ s: String) -> String {
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
            var l = line
            while let last = l.last, last == " " || last == "\t" { l = l.dropLast() }
            return l
        }
        var out: [Substring] = []
        var blank = 0
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                blank += 1
                if blank > 1 { continue }
                out.append("")
            } else {
                blank = 0
                out.append(line)
            }
        }
        return out.joined(separator: "\n")
    }
}
