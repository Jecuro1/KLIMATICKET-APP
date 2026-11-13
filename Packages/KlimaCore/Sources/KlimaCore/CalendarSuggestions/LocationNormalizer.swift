import Foundation

// MARK: calendarsuggestions – turns a calendar location into the pieces that may name a station or a town (docs/CALENDAR_SUGGESTIONS.md §3).
// "Salzburg Hbf" → ["Salzburg Hbf"]; "Hauptbahnhof Salzburg" → ["Hauptbahnhof Salzburg"] (the matcher turns the marker around);
// "Großes Festspielhaus, Hofstallgasse 1, 5020 Salzburg, Österreich" → ["Großes Festspielhaus"] + town "Salzburg" (the street,
// the postcode and the country are gone); "Zoom" or a link → virtual (no card ever).

public struct NormalizedLocation: Equatable, Sendable {
    public struct Segment: Equatable, Sendable {
        /// The piece as written, cleaned of brackets, platform numbers and a trailing country ("Salzburg Hbf").
        public var text: String
        /// A street line ("Mirabellplatz 4", "Bahnhofstraße", "Südtiroler Platz 1"): never a card on its own.
        public var isStreet: Bool
        /// `text` folded into lowercased words without diacritics (computed once, the matcher builds its keys from it).
        public var folded: [String] = []

        public static func == (a: Segment, b: Segment) -> Bool { a.text == b.text && a.isStreet == b.isStreet }
    }

    /// Pieces that may name a station or a town, in the order they were written.
    public var segments: [Segment]
    /// The town named after a postcode ("5020 Salzburg" → "Salzburg", "1060 Wien-Mariahilf" → "Wien-Mariahilf").
    public var postalTown: String?
    /// A video call, a link or a phone call – there is nowhere to travel to.
    public var isVirtual: Bool

    public var isEmpty: Bool { segments.isEmpty && postalTown == nil }
}

public enum LocationNormalizer {
    public static func normalize(_ raw: String?) -> NormalizedLocation {
        var result = NormalizedLocation(segments: [], postalTown: nil, isVirtual: false)
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return result }
        if isVirtual(raw) {
            result.isVirtual = true
            return result
        }
        for piece in split(raw) {
            var text = clean(piece)
            guard !text.isEmpty else { continue }
            // Folded once per piece: diacritic folding is the expensive step (500 events in < 50 ms, docs §3).
            var folded = words(text)
            if countries.contains(folded.joined(separator: " ")) { continue }
            if folded.count > 1, let last = folded.last, trailingCountries.contains(last) {
                text = text.split(separator: " ").dropLast().joined(separator: " ")
                folded.removeLast()
            }
            if let town = postalTown(text) {
                if result.postalTown == nil { result.postalTown = town }
                continue
            }
            guard !folded.isEmpty, !noise.contains(folded.joined(separator: " ")) else { continue }
            result.segments.append(.init(text: text, isStreet: isStreet(text, folded: folded), folded: folded))
        }
        return result
    }

    // MARK: Pieces

    /// Lines, commas, semicolons, bars and spaced dashes separate the parts of an address; a dash inside a name
    /// ("Schwarzach-St. Veit", "Wien-Mariahilf") does not.
    static func split(_ raw: String) -> [String] {
        let chars = Array(raw)
        var pieces: [String] = []
        var current = ""
        for (i, ch) in chars.enumerated() {
            let isBreak: Bool
            switch ch {
            case "\n", "\r", "\r\n", ",", ";", "|": isBreak = true
            case "-", "–", "—", "·": isBreak = i > 0 && i + 1 < chars.count && chars[i - 1] == " " && chars[i + 1] == " "
            default: isBreak = false
            }
            if isBreak {
                if !current.isEmpty { pieces.append(current) }
                current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    /// Brackets become spaces ("Salzburg (Hbf)" → "Salzburg Hbf"), platform numbers go ("Gleis 3", "Bahnsteig 4a", "Bstg. 2").
    static func clean(_ piece: String) -> String {
        var words = piece.split(whereSeparator: { " \t()\"„“”".contains($0) }).map(String.init)
        var i = 0
        while i < words.count {
            let folded = words[i].lowercased().trimmingCharacters(in: dotColon)
            if platformWords.contains(folded) {
                let removesNumber = i + 1 < words.count && words[i + 1].first?.isNumber == true
                words.removeSubrange(i..<(removesNumber ? i + 2 : i + 1))
                continue
            }
            i += 1
        }
        return words.joined(separator: " ").trimmingCharacters(in: edgePunctuation)
    }

    private static let dotColon = CharacterSet(charactersIn: ".:")
    private static let edgePunctuation = CharacterSet(charactersIn: " .:-")
    private static let platformWords: Set<String> = ["gleis", "bahnsteig", "bstg", "steig", "platform", "track"]

    // MARK: Kinds

    private static let virtualWords: Set<String> = [
        "zoom", "teams", "webex", "skype", "facetime", "jitsi", "whereby", "gotomeeting", "online", "virtuell", "virtual",
        "remote", "telefon", "telefonisch", "phone", "anruf", "videocall", "videokonferenz", "videotelefonat", "call",
    ]

    static func isVirtual(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        if lower.contains("@") { return true }
        // Links need a dot or a colon; most places have neither, so the substring searches are skipped for them.
        if lower.contains(".") || lower.contains(":"), ["http://", "https://", "www.", "meet.google", "zoom.us", "teams.microsoft"]
            .contains(where: { lower.range(of: $0) != nil }) {
            return true
        }
        // The words of a call are plain ASCII: lowercase and split, no diacritic folding needed.
        return lower.split(whereSeparator: { !$0.isLetter }).contains { virtualWords.contains(String($0)) }
    }

    private static let countries: Set<String> = [
        "osterreich", "austria", "at", "a", "deutschland", "germany", "de", "d", "schweiz", "switzerland", "suisse", "ch",
        "italien", "italy", "italia", "it", "slowakei", "slovakia", "tschechien", "czechia", "czech republic", "ungarn", "hungary",
        "slowenien", "slovenia", "liechtenstein", "fl", "europa", "europe",
    ]

    static func isCountry(_ text: String) -> Bool { countries.contains(words(text).joined(separator: " ")) }

    /// "Salzburg Österreich" → "Salzburg" (only a multi-word piece ending in one of these).
    private static let trailingCountries: Set<String> = ["osterreich", "austria", "deutschland", "germany"]

    /// "5020 Salzburg", "A-5020 Salzburg", "AT-6580 St. Anton am Arlberg", "80331 München" → the town; nil for any other piece.
    static func postalTown(_ text: String) -> String? {
        var parts = text.split(separator: " ").map(String.init)
        guard parts.count >= 2 else { return nil }
        var code = parts[0]
        if let dash = code.firstIndex(of: "-"), code[..<dash].allSatisfy(\.isLetter), code[..<dash].count <= 2 {
            code = String(code[code.index(after: dash)...])
        }
        guard (4...5).contains(code.count), code.allSatisfy(\.isNumber) else { return nil }
        parts.removeFirst()
        let town = parts.joined(separator: " ")
        return town.contains(where: \.isLetter) ? town : nil
    }

    /// Pieces that never name a place: "Büro", "Home Office", "tbd", "?".
    private static let noise: Set<String> = [
        "buro", "office", "home", "homeoffice", "home office", "zuhause", "daheim", "tbd", "tba", "offen", "unbekannt", "n a",
        "besprechungsraum", "meetingraum", "meeting room", "raum", "room", "kantine", "rezeption",
    ]

    static func isNoise(_ text: String) -> Bool {
        let w = words(text)
        guard !w.isEmpty else { return true }
        return noise.contains(w.joined(separator: " "))
    }

    private static let streetSuffixes = ["strasse", "gasse", "platz", "weg", "allee", "kai", "ufer", "zeile", "lande",
                                          "promenade", "steig", "gurtel", "damm", "chaussee"]
    private static let streetWords: Set<String> = ["strasse", "str", "gasse", "platz", "weg", "allee", "ring", "kai", "ufer", "zeile",
                                                   "lande", "promenade", "gurtel", "street", "road", "avenue"]

    /// A street line: a word with a house number ("Mirabellplatz 4", "Am Hauptbahnhof 1", "Hauptstraße 12/3"), or a piece of at most
    /// two words whose last word is a street ("Bahnhofstraße", "Südtiroler Platz", "Linzer Gasse").
    static func isStreet(_ text: String) -> Bool { isStreet(text, folded: words(text)) }

    static func isStreet(_ text: String, folded w: [String]) -> Bool {
        let raw = text.split(separator: " ").map(String.init)
        guard !raw.isEmpty else { return false }
        if raw.count >= 2, raw.contains(where: isHouseNumber) { return true }
        guard let last = w.last, w.count <= 2 else { return false }
        if streetWords.contains(last) { return true }
        return streetSuffixes.contains { last.count > $0.count + 2 && last.hasSuffix($0) }
    }

    /// "4", "12a", "3/2/5", "1-3", "14B".
    static func isHouseNumber(_ token: String) -> Bool {
        guard let first = token.first, first.isNumber else { return false }
        var letters = 0
        for ch in token {
            if ch.isNumber || ch == "/" || ch == "-" { continue }
            guard ch.isLetter else { return false }
            letters += 1
        }
        return letters <= 1
    }

    // MARK: Folding

    /// Lowercased words without diacritics ("Österreich" → "osterreich", "Büro" → "buro").
    static func words(_ text: String) -> [String] { StationIndex.foldedWords(text) }

    static func fold(_ word: String) -> String { words(word).joined(separator: " ") }
}
