import Foundation

/// Bullet-proof CSV import for trips (Excel AT, Numbers, Google Sheets, the "KlimaTicket Tracker" app and our own export).
///
/// Everything here is pure and Linux-testable:
/// - `decode(_:)`: UTF-8 (with/without BOM), UTF-16 (BOM), fallback Windows-1252 / ISO 8859-1
/// - `sniffDelimiter(_:)` + `parse(_:delimiter:)`: RFC 4180 (quoted fields with delimiters, newlines and `""`)
/// - `number(_:style:)`: de-AT and English numbers ("1.234,50", "13,40", "13.40", "€ 13,40") – "1,50" is always 1.5, never 150
/// - `date(_:time:)`: dd.MM.yyyy, d.M.yy, yyyy-MM-dd, ISO 8601 with time/offset, "9. Okt. 2026", Excel serials
/// - `guessMapping(header:rows:)`: German + English header synonyms and content sniffing
/// - `parseRows(_:)`: typed rows with German validation messages
public enum CSVImport {
    // MARK: - Text decoding

    public enum TextEncoding: String, Sendable, Hashable {
        case utf8, utf8BOM, utf16LE, utf16BE, windows1252, latin1

        /// German label for the UI ("UTF-8", "Windows-1252").
        public var title: String {
            switch self {
            case .utf8: "UTF-8"
            case .utf8BOM: "UTF-8 (mit BOM)"
            case .utf16LE, .utf16BE: "UTF-16"
            case .windows1252: "Windows-1252"
            case .latin1: "ISO 8859-1"
            }
        }
    }

    /// Decodes file bytes into text. Never fails: invalid UTF-8 falls back to Windows-1252 (a superset of Latin-1).
    public static func decode(_ data: Data) -> (text: String, encoding: TextEncoding) {
        let bytes = [UInt8](data)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            let body = Data(bytes.dropFirst(3))
            if let s = String(data: body, encoding: .utf8) { return (s, .utf8BOM) }
            return (windows1252(Array(bytes.dropFirst(3))), .windows1252)
        }
        if bytes.starts(with: [0xFF, 0xFE]), let s = String(data: Data(bytes.dropFirst(2)), encoding: .utf16LittleEndian) {
            return (s, .utf16LE)
        }
        if bytes.starts(with: [0xFE, 0xFF]), let s = String(data: Data(bytes.dropFirst(2)), encoding: .utf16BigEndian) {
            return (s, .utf16BE)
        }
        if let s = String(data: data, encoding: .utf8) { return (s, .utf8) }
        let hasCP1252Specials = bytes.contains { (0x80...0x9F).contains($0) }
        return (windows1252(bytes), hasCP1252Specials ? .windows1252 : .latin1)
    }

    /// Windows-1252 code points for 0x80–0x9F (undefined bytes map to their Latin-1 control code).
    private static let cp1252High: [UInt32] = [
        0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
        0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
    ]

    static func windows1252(_ bytes: [UInt8]) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(bytes.count)
        for b in bytes {
            let value = (0x80...0x9F).contains(b) ? cp1252High[Int(b) - 0x80] : UInt32(b)
            if let scalar = Unicode.Scalar(value) { scalars.append(scalar) }
        }
        return String(scalars)
    }

    // MARK: - Delimiter & RFC 4180 parsing

    public enum Delimiter: String, CaseIterable, Sendable, Hashable, Identifiable {
        case semicolon = ";"
        case comma = ","
        case tab = "\t"

        public var id: String { rawValue }
        public var character: Character { Character(rawValue) }
        public var title: String {
            switch self {
            case .semicolon: "Semikolon"
            case .comma: "Komma"
            case .tab: "Tabulator"
            }
        }
    }

    /// Excel's "sep=;" hint line, if present.
    static func explicitSeparator(_ text: String) -> (Delimiter, String)? {
        let firstLine = text.prefix { $0 != "\n" && $0 != "\r" }
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.hasPrefix("sep="), trimmed.count == 5 else { return nil }
        let value = String(firstLine.trimmingCharacters(in: .whitespaces).dropFirst(4))
        let delimiter: Delimiter? = value == "\t" ? .tab : Delimiter(rawValue: value)
        guard let delimiter else { return nil }
        var rest = text.dropFirst(firstLine.count)
        if rest.hasPrefix("\r\n") { rest = rest.dropFirst(2) } else if rest.hasPrefix("\n") || rest.hasPrefix("\r") { rest = rest.dropFirst() }
        return (delimiter, String(rest))
    }

    /// Picks the delimiter that splits the first lines most consistently (quotes respected).
    /// Ties prefer `;` (Excel AT), then tab, then `,` – a de-AT decimal comma never wins over a consistent semicolon.
    public static func sniffDelimiter(_ text: String) -> Delimiter {
        if let (explicit, _) = explicitSeparator(text) { return explicit }
        func consistency(_ candidate: Delimiter) -> (share: Double, columns: Int)? {
            let rows = parse(text, delimiter: candidate, limit: 25)
            guard !rows.isEmpty else { return nil }
            let counts = rows.map(\.count)
            let mode = Dictionary(grouping: counts, by: { $0 })
                .max { a, b in a.value.count == b.value.count ? a.key < b.key : a.value.count < b.value.count }?.key ?? 1
            guard mode > 1 else { return nil }
            return (Double(counts.filter { $0 == mode }.count) / Double(counts.count), mode)
        }
        // Semicolons and tabs practically never occur inside values – if they split consistently, they are the delimiter.
        // (A semicolon file full of decimal commas "13,40" also splits consistently on commas; it must not win.)
        for candidate in [Delimiter.semicolon, .tab] {
            if let c = consistency(candidate), c.share >= 0.9 { return candidate }
        }
        var best: (Delimiter, Double) = (.semicolon, -1)
        for candidate in [Delimiter.semicolon, .tab, .comma] {
            guard let c = consistency(candidate) else { continue }
            let score = c.share * 100 + Double(min(c.columns, 20)) * 0.5
            if score > best.1 + 0.001 { best = (candidate, score) }
        }
        return best.1 < 0 ? .semicolon : best.0
    }

    /// RFC 4180 parser: quoted fields may contain delimiters, line breaks and doubled quotes; CRLF, LF and CR line endings.
    /// Whitespace-only lines are dropped. `limit` stops after that many records (used for sniffing).
    public static func parse(_ text: String, delimiter: Delimiter, limit: Int? = nil) -> [[String]] {
        let source = explicitSeparator(text)?.1 ?? text
        let sep = delimiter.character
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var fieldWasQuoted = false
        var iterator = source.makeIterator()
        var pending: Character? = nil

        func endField() {
            row.append(fieldWasQuoted ? field : field.trimmingCharacters(in: .whitespaces))
            field = ""
            fieldWasQuoted = false
        }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].trimmingCharacters(in: .whitespaces).isEmpty) || fieldWasQuoted {
                rows.append(row)
            }
            row = []
        }

        while let c = pending ?? iterator.next() {
            pending = nil
            if let limit, rows.count >= limit { break }
            if inQuotes {
                if c == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
                continue
            }
            switch c {
            case "\"":
                if field.trimmingCharacters(in: .whitespaces).isEmpty {
                    field = ""
                    inQuotes = true
                    fieldWasQuoted = true
                } else {
                    field.append(c)   // stray quote inside an unquoted field: keep literally
                }
            case sep:
                endField()
            case "\r\n", "\n", "\r":
                endRow()
            default:
                if fieldWasQuoted { continue }   // text after a closing quote (malformed) is ignored
                field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty || fieldWasQuoted { endRow() }
        return rows
    }

    // MARK: - Numbers

    public enum DecimalStyle: String, Sendable, Hashable {
        /// "1.234,50" (de-AT)
        case comma
        /// "1,234.50" (English)
        case dot
        case unknown
    }

    /// Removes currency/unit tokens and spaces ("€ 1.234,50", "13,40 EUR", "12 km").
    static func cleanNumber(_ raw: String) -> (body: String, negative: Bool)? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        var negative = false
        if s.hasPrefix("(") && s.hasSuffix(")") { negative = true; s = String(s.dropFirst().dropLast()) }
        let lower = s.lowercased().replacingOccurrences(of: ",–", with: ",-").replacingOccurrences(of: ",—", with: ",-")
            .replacingOccurrences(of: ".–", with: ".-")
        var cleaned = ""
        var letters = ""
        for ch in lower {
            if ch.isNumber || ch == "." || ch == "," || ch == "-" || ch == "−" || ch == "+" {
                cleaned.append(ch)
            } else if ch.isLetter {
                letters.append(ch)
            } else if ch == "€" || ch == "'" || ch == "’" || ch.isWhitespace || ch == "\u{00A0}" || ch == "\u{202F}" {
                continue
            } else {
                return nil
            }
        }
        guard letters.isEmpty || ["eur", "euro", "km", "kilometer"].contains(letters) else { return nil }
        // "13,–" / "13,-" = whole euros (Austrian price notation), not a negative number.
        for suffix in [",-", ".-", ",−"] where cleaned.hasSuffix(suffix) { cleaned.removeLast(2) }
        if cleaned.hasPrefix("-") || cleaned.hasPrefix("−") { negative.toggle(); cleaned.removeFirst() }
        else if cleaned.hasPrefix("+") { cleaned.removeFirst() }
        if cleaned.hasSuffix("-") { negative.toggle(); cleaned.removeLast() }   // SAP style "12,00-"
        guard !cleaned.isEmpty, cleaned.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }),
              cleaned.contains(where: \.isNumber) else { return nil }
        return (cleaned, negative)
    }

    /// Parses a de-AT or English number. A lone comma is a decimal comma ("1,50" → 1.5 – never 150), unless the column is
    /// proven English (`style == .dot`) and the comma is followed by exactly three digits ("1,234" → 1234).
    /// A lone dot is a decimal point ("13.40"), except "1.234" (exactly three digits) outside proven-English columns,
    /// which is a de-AT thousands group.
    public static func number(_ raw: String, style: DecimalStyle = .unknown) -> Double? {
        guard let (body, negative) = cleanNumber(raw) else { return nil }
        let dots = body.filter { $0 == "." }.count
        let commas = body.filter { $0 == "," }.count
        var normalized: String?

        func grouped(_ s: String, separator: Character) -> String? {
            let parts = s.split(separator: separator, omittingEmptySubsequences: false)
            guard let first = parts.first, (1...3).contains(first.count), parts.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
            return parts.joined()
        }

        if dots > 0 && commas > 0 {
            let lastDot = body.lastIndex(of: ".")!, lastComma = body.lastIndex(of: ",")!
            let (decimal, group): (Character, Character) = lastComma > lastDot ? (",", ".") : (".", ",")
            guard body.filter({ $0 == decimal }).count == 1 else { return nil }
            let pieces = body.split(separator: decimal, omittingEmptySubsequences: false)
            guard pieces.count == 2, !pieces[1].contains(group), let intPart = grouped(String(pieces[0]), separator: group) else { return nil }
            normalized = intPart + "." + pieces[1]
        } else if commas > 0 {
            if commas == 1 {
                let pieces = body.split(separator: ",", omittingEmptySubsequences: false)
                if style == .dot && pieces[1].count == 3 && !pieces[0].isEmpty && pieces[0] != "0" {
                    normalized = String(pieces[0]) + String(pieces[1])        // English thousands "1,234"
                } else {
                    normalized = (pieces[0].isEmpty ? "0" : String(pieces[0])) + "." + pieces[1]
                }
            } else {
                normalized = grouped(body, separator: ",")
            }
        } else if dots > 0 {
            if dots == 1 {
                let pieces = body.split(separator: ".", omittingEmptySubsequences: false)
                let threeDigitGroup = pieces[1].count == 3 && (1...3).contains(pieces[0].count) && pieces[0] != "0"
                if threeDigitGroup && style != .dot {
                    normalized = String(pieces[0]) + String(pieces[1])        // de-AT thousands "1.234"
                } else {
                    normalized = (pieces[0].isEmpty ? "0" : String(pieces[0])) + "." + pieces[1]
                }
            } else {
                normalized = grouped(body, separator: ".")
            }
        } else {
            normalized = body
        }
        guard let normalized, !normalized.hasSuffix("."), let value = Double(normalized), value.isFinite else { return nil }
        return negative ? -value : value
    }

    /// Infers the decimal style of a whole column from its values (majority of unambiguous samples).
    public static func inferDecimalStyle<S: Sequence>(_ samples: S) -> DecimalStyle where S.Element == String {
        var comma = 0, dot = 0
        for raw in samples {
            guard let (body, _) = cleanNumber(raw) else { continue }
            let dots = body.filter { $0 == "." }.count, commas = body.filter { $0 == "," }.count
            if dots > 0 && commas > 0 {
                if body.lastIndex(of: ",")! > body.lastIndex(of: ".")! { comma += 2 } else { dot += 2 }
            } else if commas == 1 {
                let after = body.split(separator: ",", omittingEmptySubsequences: false)[1].count
                if after != 3 { comma += 2 } else { comma += 1 }
            } else if commas > 1 {
                dot += 2
            } else if dots == 1 {
                let after = body.split(separator: ".", omittingEmptySubsequences: false)[1].count
                if after != 3 { dot += 2 }
            } else if dots > 1 {
                comma += 2
            }
        }
        if comma == 0 && dot == 0 { return .unknown }
        return comma >= dot ? .comma : .dot
    }

    // MARK: - Dates & times

    private static let monthNames: [(String, Int)] = [
        ("jänner", 1), ("jaenner", 1), ("januar", 1), ("january", 1), ("jän", 1), ("jan", 1),
        ("februar", 2), ("february", 2), ("feber", 2), ("feb", 2),
        ("märz", 3), ("maerz", 3), ("march", 3), ("mär", 3), ("mrz", 3), ("mar", 3),
        ("april", 4), ("apr", 4),
        ("mai", 5), ("may", 5),
        ("juni", 6), ("june", 6), ("jun", 6),
        ("juli", 7), ("july", 7), ("jul", 7),
        ("august", 8), ("aug", 8),
        ("september", 9), ("sept", 9), ("sep", 9),
        ("oktober", 10), ("october", 10), ("okt", 10), ("oct", 10),
        ("november", 11), ("nov", 11),
        ("dezember", 12), ("december", 12), ("dez", 12), ("dec", 12),
    ]

    /// Parses "HH:mm", "H:mm", "HH:mm:ss" (optionally followed by "Uhr") → (hour, minute, second).
    public static func time(_ raw: String) -> (hour: Int, minute: Int, second: Int)? {
        var s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasSuffix("uhr") { s = String(s.dropLast(3)).trimmingCharacters(in: .whitespaces) }
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.count <= 2 && $0.allSatisfy(\.isNumber) }),
              let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        let sec = parts.count == 3 ? Int(parts[2]) ?? 0 : 0
        guard (0...23).contains(h), (0...59).contains(m), (0...59).contains(sec) else { return nil }
        return (h, m, sec)
    }

    /// Parses a date (and optional time, either inside `raw` or in a separate `time` column) in Europe/Vienna.
    /// Without any time the trip is placed at 12:00 so it never slips to a neighbouring day.
    public static func date(_ raw: String, time timeRaw: String? = nil, calendar: Calendar = .vienna) -> Date? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        var offsetSeconds: Int?
        var y = 0, m = 0, d = 0
        var clock: (hour: Int, minute: Int, second: Int)?

        // Excel serial day numbers (1900 date system), e.g. 46304 → 9 Oct 2026.
        if s.count == 5, s.allSatisfy(\.isNumber), let serial = Int(s), (20_000...80_000).contains(serial) {
            var base = DateComponents()
            base.year = 1899; base.month = 12; base.day = 30
            guard let origin = calendar.date(from: base), let day = calendar.date(byAdding: .day, value: serial, to: origin) else { return nil }
            let c = calendar.dateComponents([.year, .month, .day], from: day)
            y = c.year ?? 0; m = c.month ?? 0; d = c.day ?? 0
            s = ""
        }

        if !s.isEmpty {
            // Split "date[T| |, ]time[zone]".
            var datePart = s
            var rest = ""
            if let tIndex = s.firstIndex(of: "T"), s[s.startIndex..<tIndex].contains("-") {
                datePart = String(s[s.startIndex..<tIndex])
                rest = String(s[s.index(after: tIndex)...])
            } else if let range = s.range(of: #"\s+\d{1,2}:\d{2}"#, options: .regularExpression) {
                datePart = String(s[s.startIndex..<range.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: ", "))
                rest = String(s[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
            }
            datePart = datePart.trimmingCharacters(in: CharacterSet(charactersIn: ", "))

            guard let ymd = parseDatePart(datePart) else { return nil }
            (y, m, d) = ymd

            if !rest.isEmpty {
                var timeText = rest
                if timeText.hasSuffix("Z") || timeText.hasSuffix("z") {
                    offsetSeconds = 0
                    timeText = String(timeText.dropLast())
                } else if let r = timeText.range(of: #"[+-]\d{2}:?\d{2}$"#, options: .regularExpression) {
                    let zone = timeText[r].replacingOccurrences(of: ":", with: "")
                    let sign = zone.hasPrefix("-") ? -1 : 1
                    let digits = zone.dropFirst()
                    let hh = Int(digits.prefix(2)) ?? 0, mm = Int(digits.suffix(2)) ?? 0
                    offsetSeconds = sign * (hh * 3600 + mm * 60)
                    timeText = String(timeText[timeText.startIndex..<r.lowerBound])
                }
                if let dot = timeText.firstIndex(of: ".") { timeText = String(timeText[..<dot]) }   // fractional seconds
                guard let t = time(timeText) else { return nil }
                clock = t
            }
        }

        if clock == nil, let timeRaw, !timeRaw.trimmingCharacters(in: .whitespaces).isEmpty {
            clock = time(timeRaw)
        }
        if y < 100 { y += 2000 }
        guard (1990...2100).contains(y), (1...12).contains(m), (1...31).contains(d) else { return nil }

        var cal = calendar
        if let offsetSeconds, let zone = TimeZone(secondsFromGMT: offsetSeconds) { cal.timeZone = zone }
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d
        c.hour = clock?.hour ?? 12; c.minute = clock?.minute ?? 0; c.second = clock?.second ?? 0
        guard let result = cal.date(from: c) else { return nil }
        // Reject impossible days (31.02.) that Calendar would roll over.
        let check = cal.dateComponents([.year, .month, .day], from: result)
        guard check.year == y, check.month == m, check.day == d else { return nil }
        return result
    }

    private static func parseDatePart(_ raw: String) -> (Int, Int, Int)? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        func ints(_ parts: [Substring]) -> [Int]? {
            let values = parts.compactMap { p -> Int? in
                let t = p.trimmingCharacters(in: .whitespaces)
                return t.isEmpty || !t.allSatisfy(\.isNumber) ? nil : Int(t)
            }
            return values.count == parts.count ? values : nil
        }
        // ISO yyyy-MM-dd
        if s.contains("-") {
            let p = s.split(separator: "-", omittingEmptySubsequences: false)
            if p.count == 3, p[0].count == 4, let v = ints(p) { return (v[0], v[1], v[2]) }
            if p.count == 3, p[2].count == 4, let v = ints(p) { return (v[2], v[1], v[0]) }   // dd-MM-yyyy
            return nil
        }
        // dd.MM.yyyy / d.M.yy / "9. Okt. 2026" / "9. Oktober 2026"
        if s.contains(".") || s.contains(" ") {
            let lower = s.lowercased()
            if lower.contains(where: \.isLetter) {
                let tokens = lower.replacingOccurrences(of: ".", with: " ").split(separator: " ").map(String.init)
                // Optional leading weekday ("Fr., 9. Okt. 2026").
                let cleaned = tokens.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ",")) }.filter { !$0.isEmpty }
                guard let dayIndex = cleaned.firstIndex(where: { $0.allSatisfy(\.isNumber) }), dayIndex + 2 < cleaned.count,
                      let day = Int(cleaned[dayIndex]), let year = Int(cleaned[dayIndex + 2]), cleaned[dayIndex + 2].count == 4 else { return nil }
                let monthToken = cleaned[dayIndex + 1]
                guard let month = monthNames.first(where: { monthToken == $0.0 })?.1
                        ?? monthNames.first(where: { $0.0.count >= 3 && monthToken.hasPrefix($0.0) })?.1 else { return nil }
                return (year, month, day)
            }
            let p = s.split(separator: ".", omittingEmptySubsequences: true)
            if p.count == 3, let v = ints(p), p[0].count <= 2, p[1].count <= 2, p[2].count == 4 || p[2].count == 2 { return (v[2], v[1], v[0]) }
            if p.count == 3, let v = ints(p), p[0].count == 4 { return (v[0], v[1], v[2]) }   // yyyy.MM.dd
            return nil
        }
        // dd/MM/yyyy (European default), MM/dd/yyyy when the middle value cannot be a month, yyyy/MM/dd
        if s.contains("/") {
            let p = s.split(separator: "/", omittingEmptySubsequences: false)
            guard p.count == 3, let v = ints(p) else { return nil }
            if p[0].count == 4 { return (v[0], v[1], v[2]) }
            guard p[2].count == 4 || p[2].count == 2 else { return nil }
            if v[1] > 12 && v[0] <= 12 { return (v[2], v[0], v[1]) }
            return (v[2], v[1], v[0])
        }
        // yyyyMMdd
        if s.count == 8, s.allSatisfy(\.isNumber), let y = Int(s.prefix(4)), let m = Int(s.dropFirst(4).prefix(2)), let d = Int(s.suffix(2)) {
            return (y, m, d)
        }
        return nil
    }

    // MARK: - Booleans, modes, categories, routes

    /// "ja", "x", "1", "true", "H+R", "retour", "✓" → true; "nein", "0", "", "-" → false; nil when unrecognised.
    public static func bool(_ raw: String) -> Bool? {
        if raw.contains("✓") || raw.contains("✔") || raw.contains("☑") { return true }
        let s = normalizeKey(raw)
        if s.isEmpty { return false }
        let yes: Set<String> = ["ja", "j", "yes", "y", "true", "wahr", "1", "x", "hr", "hinretour", "hinundretour", "retour", "hinundzuruck",
                                "hinzuruck", "roundtrip", "return", "beide", "both", "2"]
        let no: Set<String> = ["nein", "n", "no", "false", "falsch", "0", "einfach", "einzel", "oneway", "single", "hin", "1x"]
        if yes.contains(s) { return true }
        if no.contains(s) || raw.trimmingCharacters(in: .whitespaces) == "-" || raw.trimmingCharacters(in: .whitespaces) == "–" { return false }
        return nil
    }

    /// Transport mode from German/English names, ÖBB train categories and our raw values.
    public static func mode(_ raw: String) -> TransportMode? {
        let s = normalizeKey(raw)
        guard !s.isEmpty else { return nil }
        if let exact = TransportMode(rawValue: raw.trimmingCharacters(in: .whitespaces)) { return exact }
        if let byName = TransportMode.allCases.first(where: { normalizeKey($0.displayName) == s }) { return byName }
        let table: [(TransportMode, [String])] = [
            (.sBahn, ["sbahn", "s", "schnellbahn", "suburban", "commuterrail", "lokalbahn"]),
            (.metro, ["ubahn", "u", "metro", "subway", "underground", "u1", "u2", "u3", "u4", "u5", "u6"]),
            (.tram, ["bim", "tram", "strassenbahn", "strasenbahn", "tramway", "streetcar", "trambahn", "stubaitalbahn"]),
            (.bus, ["bus", "postbus", "regionalbus", "stadtbus", "obus", "citybus", "busse", "autobus", "nachtbus", "flixbus", "coach"]),
            (.ferry, ["schiff", "fahre", "ferry", "boot", "boat", "ship", "faehre"]),
            (.cableCar, ["seilbahn", "gondel", "standseilbahn", "zahnradbahn", "cablecar", "gondola", "funicular", "sessellift", "bergbahn"]),
            (.train, ["zug", "bahn", "train", "rail", "obb", "oebb", "westbahn", "railjet", "rj", "rjx", "rex", "r", "ic", "ec", "ice",
                      "nj", "nightjet", "cjx", "d", "regionalzug", "fernzug", "intercity", "eurocity", "regiojet", "eisenbahn", "rex"]),
            (.other, ["sonstiges", "sonstige", "andere", "other", "misc", "taxi", "fahrrad", "rad", "bike"]),
        ]
        for (mode, keys) in table where keys.contains(s) { return mode }
        // Prefixes like "RJX 662", "S1", "U4 Richtung Hütteldorf", "Bus 4130".
        let firstToken = normalizeKey(String(raw.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "/" }).first ?? ""))
        if firstToken != s, let m = mode(firstToken) { return m }
        if s.count <= 4, let first = s.first, s.dropFirst().allSatisfy(\.isNumber), !s.dropFirst().isEmpty {
            if first == "s" { return .sBahn }
            if first == "u" { return .metro }
        }
        for (mode, keys) in table where keys.contains(where: { $0.count >= 4 && s.contains($0) }) { return mode }
        return nil
    }

    public static func category(_ raw: String) -> TripCategory? {
        let s = normalizeKey(raw)
        guard !s.isEmpty else { return nil }
        if let exact = TripCategory(rawValue: raw.trimmingCharacters(in: .whitespaces)) { return exact }
        if let byName = TripCategory.allCases.first(where: { normalizeKey($0.displayName) == s }) { return byName }
        let table: [(TripCategory, [String])] = [
            (.commute, ["arbeit", "arbeitsweg", "pendeln", "pendler", "job", "work", "commute", "buro", "beruf", "beruflich"]),
            (.business, ["dienstreise", "dienstlich", "geschaftlich", "geschaftsreise", "business", "businesstrip", "termin"]),
            (.education, ["schule", "uni", "universitat", "studium", "ausbildung", "fh", "kurs", "school", "university", "education", "study"]),
            (.leisure, ["freizeit", "ausflug", "wandern", "skifahren", "sport", "leisure", "trip", "hobby", "konzert", "kultur"]),
            (.holiday, ["urlaub", "ferien", "reise", "holiday", "vacation", "travel"]),
            (.visit, ["besuch", "familie", "freunde", "eltern", "visit", "family", "friends"]),
            (.errand, ["erledigung", "einkauf", "einkaufen", "arzt", "behorde", "errand", "shopping", "doctor"]),
            (.other, ["sonstiges", "sonstige", "andere", "other", "privat", "private"]),
        ]
        for (category, keys) in table where keys.contains(s) { return category }
        for (category, keys) in table where keys.contains(where: { $0.count >= 4 && s.contains($0) }) { return category }
        return nil
    }

    /// Splits "Salzburg Hbf – Wien Hbf", "A -> B", "A → B", "A nach B", "A to B"; "A ↔ B" / "A <-> B" also means round trip.
    public static func splitRoute(_ raw: String) -> (from: String, to: String, isRoundTrip: Bool)? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        let roundSeparators = ["↔", "<->", "<>", "⇄", "⇆"]
        let separators = ["→", "->", "=>", "➔", "➜", " – ", " — ", " - ", " > ", " nach ", " Nach ", " to ", " bis ", "–", "—"]
        for sep in roundSeparators + separators {
            guard let range = s.range(of: sep) else { continue }
            let a = s[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let b = s[range.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !a.isEmpty, !b.isEmpty else { continue }
            var to = b
            var round = roundSeparators.contains(sep)
            // "A – B (H+R)" / "A – B und retour"
            for marker in [" (H+R)", " (H&R)", " (hin & retour)", " (hin und retour)", " und retour", " & retour", " retour", " (retour)", " H+R"] {
                if to.lowercased().hasSuffix(marker.lowercased()) {
                    to = String(to.dropLast(marker.count)).trimmingCharacters(in: .whitespaces)
                    round = true
                }
            }
            return (a, to, round)
        }
        return nil
    }

    /// Lowercased, diacritic-free, alphanumerics only ("Hin & Retour" → "hinretour", "Preis (€)" → "preis").
    public static func normalizeKey(_ s: String) -> String {
        let folded = s.lowercased().replacingOccurrences(of: "ß", with: "ss")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_AT"))
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }.map(Character.init))
    }

    /// Strips the spreadsheet-formula guard our export adds ("'=Foo" → "=Foo").
    public static func unguard(_ s: String) -> String {
        if s.count >= 2, s.first == "'", let second = s.dropFirst().first, "=+-@".contains(second) { return String(s.dropFirst()) }
        return s
    }
}

// MARK: - Column mapping

public extension CSVImport {
    /// What a CSV column means.
    enum Field: String, CaseIterable, Sendable, Hashable, Identifiable {
        case date, time, from, to, route, price, totalValue, mode, roundTrip, category, note, distance, totalDistance, induced
        /// Via stations ("Über", docs/VIA.md) – never guessed from content, only from a header.
        case via

        public var id: String { rawValue }

        /// German title for the mapping menu.
        public var title: String {
            switch self {
            case .date: "Datum"
            case .time: "Uhrzeit"
            case .from: "Von"
            case .to: "Nach"
            case .route: "Strecke (Von – Nach)"
            case .price: "Normalpreis (pro Richtung)"
            case .totalValue: "Wert gesamt"
            case .mode: "Verkehrsmittel"
            case .roundTrip: "Hin & Retour"
            case .category: "Kategorie"
            case .note: "Notiz"
            case .distance: "Distanz (pro Richtung)"
            case .totalDistance: "Distanz gesamt"
            case .induced: "Ohne Ticket nicht gefahren"
            case .via: "Über (Zwischenhalte)"
            }
        }

        public var symbolName: String {
            switch self {
            case .date: "calendar"
            case .time: "clock"
            case .from: "circle.circle"
            case .to: "mappin.circle.fill"
            case .route: "point.topleft.down.to.point.bottomright.curvepath"
            case .price: "eurosign.circle.fill"
            case .totalValue: "sum"
            case .mode: "tram.fill"
            case .roundTrip: "arrow.left.arrow.right"
            case .category: "tag.fill"
            case .note: "text.alignleft"
            case .distance: "ruler"
            case .totalDistance: "ruler.fill"
            case .induced: "sparkles"
            case .via: "point.3.filled.connected.trianglepath.dotted"
            }
        }

        /// Header synonyms (normalised with `normalizeKey`), German first.
        var synonyms: [String] {
            switch self {
            case .date: ["datum", "date", "tag", "day", "reisedatum", "fahrtdatum", "abfahrtsdatum", "traveldate", "tripdate", "datumuhrzeit",
                         "zeitpunkt", "timestamp", "datetime", "wann", "when", "reisetag"]
            case .time: ["uhrzeit", "zeit", "time", "abfahrt", "abfahrtszeit", "departure", "departuretime", "startzeit", "abfahrtuhrzeit"]
            case .from: ["von", "start", "abfahrtsort", "startbahnhof", "startort", "starthaltestelle", "ab", "from", "origin", "departurestation",
                         "startstation", "einstieg", "abfahrtsbahnhof", "ausgangspunkt", "vonbahnhof", "vonhaltestelle", "abfahrtshaltestelle"]
            case .to: ["nach", "ziel", "ankunftsort", "zielbahnhof", "zielort", "zielhaltestelle", "an", "to", "destination", "arrival",
                       "arrivalstation", "endstation", "ausstieg", "bis", "nachbahnhof", "nachhaltestelle", "ankunftsbahnhof"]
            case .route: ["strecke", "route", "verbindung", "relation", "fahrt", "name", "titel", "title", "bezeichnung", "vorlage", "template",
                          "trip", "journey", "reise", "strecken", "linie"]
            case .price: ["preis", "normalpreis", "fahrpreis", "ticketpreis", "einzelpreis", "einzelfahrschein", "kosten", "betrag", "wert", "price",
                          "fare", "cost", "costs", "amount", "value", "eur", "euro", "preiseur", "normalpreiseur", "regularerpreis", "standardpreis",
                          "ersparnis", "gespart", "saved", "savings", "preisproRichtung".lowercased(), "preisprorichtung", "einfacherpreis"]
            case .totalValue: ["wertgesamt", "gesamtwert", "gesamtpreis", "summe", "total", "totalvalue", "gesamt", "betraggesamt",
                               "preisgesamt", "gesamtbetrag", "totalprice", "totalcost"]
            case .mode: ["verkehrsmittel", "vm", "mittel", "mode", "transport", "transportmode", "typ", "art", "fahrzeug", "vehicle",
                         "zugart", "zuggattung", "type", "transportmittel", "modus"]
            case .roundTrip: ["hinretour", "hinundretour", "hinundzuruck", "retour", "hinruck", "hinundruck", "roundtrip", "return",
                              "hinzuruck", "hr", "ruckfahrt", "hinundruckfahrt", "retourfahrt", "beidewege"]
            case .category: ["kategorie", "category", "zweck", "anlass", "reisezweck", "purpose", "grund", "tags", "label", "kat", "fahrtzweck"]
            case .note: ["notiz", "notizen", "bemerkung", "bemerkungen", "kommentar", "anmerkung", "note", "notes", "comment", "comments",
                         "memo", "beschreibung", "description", "info", "details"]
            case .distance: ["distanz", "distanzkm", "entfernung", "entfernungkm", "km", "kilometer", "distance", "distancekm", "kilometers",
                             "strecke km", "streckekm", "einfachkm", "kmprorichtung", "distanzprorichtung"]
            case .totalDistance: ["distanzgesamt", "distanzgesamtkm", "gesamtdistanz", "kmgesamt", "gesamtkm", "totaldistance", "totalkm",
                                  "gesamtkilometer", "gesamtentfernung"]
            case .induced: ["ohneticketnichtgefahren", "induziert", "induced", "zusatzfahrt", "nurwegenticket", "wegenticket", "extrafahrt",
                            "ohneticket"]
            case .via: ["uber", "via", "zwischenhalt", "zwischenhalte", "zwischenstopp", "zwischenstation", "zwischenstationen",
                        "uberbahnhof", "stopover", "stopovers", "viastations", "viastops"]
            }
        }
    }

    /// Recognised source applications.
    enum SourceFormat: String, Sendable, Hashable {
        case klimaBilanz
        case klimaTicketTracker
        case generic

        public var title: String? {
            switch self {
            case .klimaBilanz: "KlimaBilanz-Export"
            case .klimaTicketTracker: "KlimaTicket Tracker"
            case .generic: nil
            }
        }
    }

    struct MappingGuess: Sendable, Hashable {
        public var fields: [Field?]
        public var hasHeader: Bool
        public var format: SourceFormat
    }

    /// Whether the first record looks like a header row (known column names, or text above dates/numbers).
    static func looksLikeHeader(_ rows: [[String]]) -> Bool {
        guard let first = rows.first else { return false }
        let known = Set(Field.allCases.flatMap(\.synonyms))
        let keys = first.map(normalizeKey).map { stripUnits($0) }
        if keys.contains(where: { known.contains($0) }) && !first.contains(where: { date($0) != nil }) { return true }
        guard rows.count > 1 else { return false }
        let firstHasValues = first.contains { date($0) != nil || number($0) != nil }
        let secondHasValues = rows[1].contains { date($0) != nil || number($0) != nil }
        return !firstHasValues && secondHasValues
    }

    /// Removes unit suffixes from a normalised header ("preiseur" → "preis", "distanzkm" stays as synonym).
    static func stripUnits(_ key: String) -> String {
        for suffix in ["inkleur", "ineur", "eur", "euro"] where key.hasSuffix(suffix) && key.count > suffix.count + 2 {
            return String(key.dropLast(suffix.count))
        }
        return key
    }

    /// Guesses the meaning of each column from header names (German + English) and, as a fallback, from the values.
    static func guessMapping(rows: [[String]], hasHeader forcedHeader: Bool? = nil) -> MappingGuess {
        let columnCount = rows.prefix(50).map(\.count).max() ?? 0
        let hasHeader = forcedHeader ?? looksLikeHeader(rows)
        let header = hasHeader ? (rows.first ?? []) : []
        let body = Array(rows.dropFirst(hasHeader ? 1 : 0).prefix(60))
        var fields = [Field?](repeating: nil, count: columnCount)
        let keys = (0..<columnCount).map { $0 < header.count ? normalizeKey(header[$0]) : "" }

        let format: SourceFormat
        if keys.contains("normalpreis") && keys.contains("wertgesamt") || keys.contains("normalpreiseur") {
            format = .klimaBilanz
        } else if keys.contains("ticket") && keys.contains(where: { ["name", "titel", "title", "vorlage", "template", "bezeichnung"].contains($0) }) {
            format = .klimaTicketTracker
        } else {
            format = .generic
        }

        func assign(_ field: Field, to index: Int) {
            guard fields[index] == nil, !fields.contains(field) else { return }
            fields[index] = field
        }

        if hasHeader {
            // Our own export: "Distanz (km)" was the total distance (all legs) in v1 files.
            if format == .klimaBilanz, let i = keys.firstIndex(of: "distanzkm") { assign(.totalDistance, to: i) }
            // Pass 1: exact synonyms (more specific fields first).
            let order: [Field] = [.totalValue, .totalDistance, .induced, .roundTrip, .date, .time, .from, .to, .via, .price, .distance,
                                  .mode, .category, .note, .route]
            for field in order {
                for (i, key) in keys.enumerated() where !key.isEmpty {
                    let stripped = stripUnits(key)
                    if field.synonyms.contains(key) || field.synonyms.contains(stripped) { assign(field, to: i) }
                }
            }
            // Pass 2: contains-rules for compound headers ("Datum der Fahrt", "Preis in €", "Strecke von").
            let containsRules: [(Field, [String])] = [
                (.totalValue, ["gesamt", "summe", "total"]),
                (.date, ["datum", "date"]),
                (.time, ["uhrzeit", "time"]),
                (.from, ["abfahrtsort", "startbahnhof", "von", "from", "origin"]),
                (.to, ["zielbahnhof", "ziel", "nach", "destination"]),
                (.price, ["preis", "price", "fare", "kosten", "betrag", "eur"]),
                (.distance, ["distanz", "kilometer", "distance", "entfernung"]),
                (.mode, ["verkehrsmittel", "transport", "mittel"]),
                (.roundTrip, ["retour", "return", "zuruck"]),
                (.category, ["kategorie", "category", "zweck"]),
                (.note, ["notiz", "bemerk", "kommentar", "note", "comment"]),
                (.via, ["zwischenhalt", "zwischenstop", "zwischenstation"]),
            ]
            for (field, needles) in containsRules {
                for (i, key) in keys.enumerated() where !key.isEmpty && fields[i] == nil {
                    if field == .totalValue && !(key.contains("preis") || key.contains("wert") || key.contains("betrag") || key.contains("price") || key.contains("value") || key == "gesamt" || key == "summe" || key == "total") { continue }
                    if needles.contains(where: { key.contains($0) }) { assign(field, to: i) }
                }
            }
            // A route column only matters when from/to are missing.
            if fields.contains(.from) && fields.contains(.to), let i = fields.firstIndex(of: .route) { fields[i] = nil }
        }

        // Content sniffing for whatever is still unassigned (also covers header-less files).
        func column(_ i: Int) -> [String] { body.compactMap { i < $0.count ? $0[i] : nil }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        func share(_ values: [String], _ test: (String) -> Bool) -> Double {
            values.isEmpty ? 0 : Double(values.filter(test).count) / Double(values.count)
        }
        for i in 0..<columnCount where fields[i] == nil {
            let values = column(i)
            guard !values.isEmpty else { continue }
            // Named columns we don't know (e.g. "Ticket", "ID") must never become Von/Nach just because they hold text.
            let allowsText = !hasHeader || keys[i].isEmpty
            if !fields.contains(.date) && share(values, { date($0) != nil && number($0) == nil }) >= 0.8 {
                fields[i] = .date
            } else if !fields.contains(.time) && share(values, { time($0) != nil }) >= 0.8 {
                fields[i] = .time
            } else if !fields.contains(.route) && !fields.contains(.from) && share(values, { splitRoute($0) != nil }) >= 0.6 {
                fields[i] = .route
            } else if !fields.contains(.mode) && share(values, { mode($0) != nil }) >= 0.8 && values.contains(where: { $0.contains(where: \.isLetter) }) {
                fields[i] = .mode
            } else if !fields.contains(.roundTrip) && share(values, { bool($0) != nil }) >= 0.9 && values.contains(where: { $0.contains(where: \.isLetter) }) {
                fields[i] = .roundTrip
            } else if share(values, { number($0) != nil }) >= 0.8 {
                // Money has a € sign or exactly two decimals ("23,50"); everything else numeric is a distance.
                let looksLikeMoney = share(values, { v in
                    v.contains("€") || v.lowercased().contains("eur") ||
                        v.split(whereSeparator: { $0 == "," || $0 == "." }).last.map { $0.count == 2 && v.contains(where: { $0 == "," || $0 == "." }) } == true
                }) >= 0.5
                if !fields.contains(.price) && looksLikeMoney {
                    fields[i] = .price
                } else if !fields.contains(.distance) && !fields.contains(.totalDistance) {
                    fields[i] = .distance
                }
            } else if allowsText && share(values, { $0.contains(where: \.isLetter) }) >= 0.8 {
                if !fields.contains(.from) && !fields.contains(.route) { fields[i] = .from }
                else if !fields.contains(.to) && fields.contains(.from) { fields[i] = .to }
            }
        }
        return MappingGuess(fields: fields, hasHeader: hasHeader, format: format)
    }
}

// MARK: - Typed rows

public extension CSVImport {
    enum Issue: Hashable, Sendable {
        case missingDate
        case invalidDate(String)
        case missingFrom
        case missingTo
        case sameStations
        case invalidPrice(String)
        case negativePrice
        case invalidDistance(String)
        case unknownMode(String)
        case unknownCategory(String)
        case implausiblePrice(Double)

        /// Errors block the row; warnings are shown but the row is imported.
        public var isError: Bool {
            switch self {
            case .unknownMode, .unknownCategory, .implausiblePrice, .invalidDistance: false
            default: true
            }
        }

        /// German, precise, du-Form.
        public var message: String {
            switch self {
            case .missingDate: "Datum fehlt"
            case .invalidDate(let s): "Datum „\(s)“ nicht erkannt"
            case .missingFrom: "Start fehlt"
            case .missingTo: "Ziel fehlt"
            case .sameStations: "Start und Ziel sind gleich"
            case .invalidPrice(let s): "Preis „\(s)“ ist keine Zahl"
            case .negativePrice: "Preis ist negativ"
            case .invalidDistance(let s): "Distanz „\(s)“ ignoriert"
            case .unknownMode(let s): "Verkehrsmittel „\(s)“ unbekannt – als Zug übernommen"
            case .unknownCategory(let s): "Kategorie „\(s)“ unbekannt – ohne Kategorie"
            case .implausiblePrice(let v): "Ungewöhnlich hoher Preis (€ \(Int(v.rounded()))) – Komma prüfen?"
            }
        }
    }

    struct Row: Sendable, Hashable, Identifiable {
        /// 1-based line number of the record in the file (header = line 1 when present).
        public var line: Int
        public var date: Date?
        public var fromName: String
        public var toName: String
        /// Regular fare for ONE direction (nil = not given → estimate).
        public var fare: Double?
        /// Distance of ONE direction (nil = not given → estimate).
        public var distanceKm: Double?
        public var mode: TransportMode?
        public var isRoundTrip: Bool
        public var category: TripCategory?
        public var note: String
        public var isInduced: Bool
        public var issues: [Issue]
        /// Via station names in travel order (column "Über"; at most `TripVia.maxCount`).
        public var via: [String] = []

        public var id: Int { line }
        public var errors: [Issue] { issues.filter(\.isError) }
        public var warnings: [Issue] { issues.filter { !$0.isError } }
        public var isValid: Bool { errors.isEmpty }
        public var legs: Int { isRoundTrip ? 2 : 1 }
    }

    /// Spreadsheet stand-ins for "nothing here" ("-", "–", "n/a", "k. A.") – treated like an empty cell, so a dash in
    /// the price column means "estimate it", not "invalid price".
    static func isPlaceholder(_ value: String) -> Bool {
        let s = value.trimmingCharacters(in: .whitespaces).lowercased()
        return ["-", "–", "—", "--", "?", "/", "n/a", "n.a.", "na", "k.a.", "k. a.", "keine angabe", "none", "null"].contains(s)
    }

    /// Plausibility limit for a single direction (the most expensive Austrian standard ticket is far below this).
    static let implausibleFare: Double = 250

    /// Converts records into typed rows using the mapping. Records shorter than the mapping are padded.
    static func parseRows(_ records: [[String]], fields: [Field?], hasHeader: Bool, calendar: Calendar = .vienna) -> [Row] {
        let body = Array(records.dropFirst(hasHeader ? 1 : 0))
        func index(_ f: Field) -> Int? { fields.firstIndex(of: f) }
        func values(_ f: Field) -> [String] {
            guard let i = index(f) else { return [] }
            return body.compactMap { i < $0.count ? $0[i] : nil }
        }
        let priceStyle = inferDecimalStyle(values(.price) + values(.totalValue))
        let distanceStyle = inferDecimalStyle(values(.distance) + values(.totalDistance))

        return body.enumerated().map { offset, cells in
            func cell(_ f: Field) -> String? {
                guard let i = index(f), i < cells.count else { return nil }
                let v = unguard(cells[i].trimmingCharacters(in: .whitespacesAndNewlines))
                return v.isEmpty || isPlaceholder(v) ? nil : v
            }
            var issues: [Issue] = []
            var row = Row(line: offset + 1 + (hasHeader ? 1 : 0), date: nil, fromName: "", toName: "", fare: nil, distanceKm: nil, mode: nil,
                          isRoundTrip: false, category: nil, note: "", isInduced: false, issues: [])

            // Route
            row.fromName = cell(.from) ?? ""
            row.toName = cell(.to) ?? ""
            if let route = cell(.route), row.fromName.isEmpty || row.toName.isEmpty {
                if let split = splitRoute(route) {
                    if row.fromName.isEmpty { row.fromName = split.from }
                    if row.toName.isEmpty { row.toName = split.to }
                    if split.isRoundTrip { row.isRoundTrip = true }
                } else if row.fromName.isEmpty {
                    row.fromName = route
                }
            }
            if row.fromName.isEmpty { issues.append(.missingFrom) }
            if row.toName.isEmpty { issues.append(.missingTo) }
            if !row.fromName.isEmpty && !row.toName.isEmpty && normalizeKey(row.fromName) == normalizeKey(row.toName) { issues.append(.sameStations) }

            // Date
            if let raw = cell(.date) {
                if let d = date(raw, time: cell(.time), calendar: calendar) { row.date = d } else { issues.append(.invalidDate(raw)) }
            } else {
                issues.append(.missingDate)
            }

            // Flags
            if let raw = cell(.roundTrip), let b = bool(raw) { row.isRoundTrip = row.isRoundTrip || b }
            if let raw = cell(.induced), let b = bool(raw) { row.isInduced = b }

            // Money (per direction)
            if let raw = cell(.price) {
                if let v = number(raw, style: priceStyle) {
                    if v < 0 { issues.append(.negativePrice) } else if v > 0 { row.fare = v }
                } else {
                    issues.append(.invalidPrice(raw))
                }
            }
            if row.fare == nil, let raw = cell(.totalValue) {
                if let v = number(raw, style: priceStyle) {
                    if v < 0 { issues.append(.negativePrice) } else if v > 0 { row.fare = v / Double(row.legs) }
                } else if cell(.price) == nil {
                    issues.append(.invalidPrice(raw))
                }
            }
            if let fare = row.fare, fare > implausibleFare { issues.append(.implausiblePrice(fare)) }

            // Distance (per direction)
            if let raw = cell(.distance) {
                if let v = number(raw, style: distanceStyle), v > 0, v < 3000 { row.distanceKm = v } else if number(raw, style: distanceStyle) != 0 { issues.append(.invalidDistance(raw)) }
            } else if let raw = cell(.totalDistance) {
                if let v = number(raw, style: distanceStyle), v > 0, v < 6000 { row.distanceKm = v / Double(row.legs) } else if number(raw, style: distanceStyle) != 0 { issues.append(.invalidDistance(raw)) }
            }

            // Mode, category, note
            if let raw = cell(.mode) {
                if let m = mode(raw) { row.mode = m } else { issues.append(.unknownMode(raw)) }
            }
            if let raw = cell(.category) {
                if let c = category(raw) { row.category = c } else { issues.append(.unknownCategory(raw)) }
            }
            row.note = cell(.note) ?? ""
            if let raw = cell(.via) {
                let endpoints = [normalizeKey(row.fromName), normalizeKey(row.toName)]
                row.via = Array(TripVia.parseNames(raw).filter { !endpoints.contains(normalizeKey($0)) }.prefix(TripVia.maxCount))
            }
            row.issues = issues
            return row
        }
    }

    // MARK: Duplicates

    /// Duplicate key: same calendar day (Vienna), same direction-sensitive route (normalised names, vias in order) and same
    /// fare in cents. Without vias the key is the one of files and trips from before via stops.
    static func duplicateKey(date: Date, fromName: String, toName: String, fare: Double, via: [String] = [],
                             calendar: Calendar = .vienna) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        let cents = Int((fare * 100).rounded())
        let key = "\(day)|\(StationIndex.normalize(fromName))|\(StationIndex.normalize(toName))|\(cents)"
        guard !via.isEmpty else { return key }
        return key + "|über:" + via.map(StationIndex.normalize).joined(separator: ">")
    }
}
