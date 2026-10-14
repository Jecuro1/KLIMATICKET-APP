import Foundation

// MARK: - Trip query (natural-language search, docs/LOCAL_AI.md §3.1)

/// What a sentence like "nächste Woche Freitag nach Innsbruck, Rückfahrt Sonntag" asks for. Places stay as the user wrote
/// them: the app resolves them against the station index and asks again when nothing matches.
public struct TripQueryDraft: Equatable, Sendable {
    public var origin: String?
    public var destination: String?
    /// Hinfahrt: the day (start of day, Vienna) and the optional time.
    public var outboundDay: Date?
    public var outboundHour: Int?
    public var outboundMinute: Int?
    /// "bis 9 Uhr" means arrival by that time, not departure.
    public var isArrival: Bool
    /// Rückfahrt: a day on or after the outbound day. The planner searches one direction, so the app only reports it.
    public var returnDay: Date?
    public var source: AssistantSource

    public init(origin: String? = nil, destination: String? = nil, outboundDay: Date? = nil, outboundHour: Int? = nil,
                outboundMinute: Int? = nil, isArrival: Bool = false, returnDay: Date? = nil, source: AssistantSource = .rules) {
        self.origin = origin
        self.destination = destination
        self.outboundDay = outboundDay
        self.outboundHour = outboundHour
        self.outboundMinute = outboundMinute
        self.isArrival = isArrival
        self.returnDay = returnDay
        self.source = source
    }

    public var isEmpty: Bool {
        origin == nil && destination == nil && outboundDay == nil && outboundHour == nil && returnDay == nil
    }

    /// `self` wins; `other` only fills the fields that are still empty. The source becomes `.model` when `other`
    /// (a validated model result) contributed a field, and stays `self.source` otherwise.
    public func filled(from other: TripQueryDraft) -> TripQueryDraft {
        var out = self
        var contributed = false
        func take<T>(_ mine: T?, _ theirs: T?, _ set: (T) -> Void) {
            if mine == nil, let value = theirs {
                set(value)
                contributed = true
            }
        }
        take(origin, other.origin) { out.origin = $0 }
        take(destination, other.destination) { out.destination = $0 }
        take(outboundDay, other.outboundDay) { out.outboundDay = $0 }
        take(outboundHour, other.outboundHour) { out.outboundHour = $0 }
        take(outboundMinute, other.outboundMinute) { out.outboundMinute = $0 }
        take(returnDay, other.returnDay) { out.returnDay = $0 }
        if !isArrival, other.isArrival, outboundHour == nil {
            out.isArrival = true
            contributed = true
        }
        if contributed { out.source = .model }
        return out
    }
}

/// Rule-based German parser. It is the first step for every query and the only parser when the model is not available,
/// so it covers the common phrasings: Ort, Datum, Uhrzeit, Hin- und Rückfahrt.
public enum TripQueryParser {
    public static func parse(_ text: String, now: Date, calendar: Calendar = .vienna) -> TripQueryDraft {
        let spaced = text
            .replacingOccurrences(of: ",", with: " , ")
            .replacingOccurrences(of: ";", with: " , ")
            .replacingOccurrences(of: "?", with: " ")
            .replacingOccurrences(of: "!", with: " ")
        let words = spaced.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
        let returnIndex = words.firstIndex { returnMarkers.contains(fold($0)) }
        let outboundWords = returnIndex.map { Array(words[..<$0]) } ?? words
        let returnWords = returnIndex.map { Array(words[($0 + 1)...]) } ?? []

        var draft = TripQueryDraft(source: .rules)
        let outbound = outboundPart(outboundWords, now: now, calendar: calendar)
        draft.outboundDay = outbound.day
        draft.outboundHour = outbound.hour
        draft.outboundMinute = outbound.minute
        draft.isArrival = outbound.isArrival
        draft.origin = outbound.origin
        draft.destination = outbound.destination

        if !returnWords.isEmpty, let day = dayPart(returnWords, now: now, calendar: calendar).day {
            let anchor = draft.outboundDay ?? calendar.startOfDay(for: now)
            draft.returnDay = day < anchor ? nextOccurrence(of: day, atOrAfter: anchor, calendar: calendar) : day
        }
        return draft
    }

    // MARK: Parts

    private struct Outbound {
        var day: Date?
        var hour: Int?
        var minute: Int?
        var isArrival: Bool
        var origin: String?
        var destination: String?
    }

    private static func outboundPart(_ words: [String], now: Date, calendar: Calendar) -> Outbound {
        let timed = timePart(words)
        let dated = dayPart(timed.rest, now: now, calendar: calendar)
        let places = placeWords(dated.rest)
        var out = Outbound(day: dated.day, hour: timed.hour, minute: timed.minute, isArrival: timed.isArrival,
                           origin: nil, destination: nil)
        let from = places.firstIndex { fold($0) == "von" || fold($0) == "ab" }
        let to = places.firstIndex { destinationMarkers.contains(fold($0)) }
        if let t = to {
            // "nach X von Y" and "von Y nach X" both end the destination at the other marker.
            let end = from.map { $0 > t ? $0 : places.count } ?? places.count
            out.destination = joined(places[(t + 1)..<end])
            if let f = from {
                out.origin = f < t ? joined(places[(f + 1)..<t]) : joined(places[(f + 1)...])
            } else {
                out.origin = joined(places[..<t])
            }
        } else if let f = from {
            out.origin = joined(places[(f + 1)...])
        } else {
            // A single place without a marker is the destination ("Innsbruck am Freitag").
            out.destination = joined(places[...])
        }
        out.origin = out.origin.flatMap(clean)
        out.destination = out.destination.flatMap(clean)
        return out
    }

    /// Removes the time phrase ("um 7", "ab 7:30 Uhr", "bis 9 Uhr") and reports whether it is an arrival time.
    private static func timePart(_ words: [String]) -> (rest: [String], hour: Int?, minute: Int?, isArrival: Bool) {
        var rest: [String] = []
        var hour: Int?
        var minute: Int?
        var isArrival = false
        var index = 0
        while index < words.count {
            let folded = fold(words[index])
            if timeMarkers.contains(folded), index + 1 < words.count, let parsed = clock(words[index + 1]) {
                hour = parsed.hour
                minute = parsed.minute
                isArrival = folded == "bis" || folded == "spätestens"
                index += 2
                if index < words.count, fold(words[index]) == "uhr" { index += 1 }
                continue
            }
            if let parsed = clock(words[index]), index + 1 < words.count, fold(words[index + 1]) == "uhr" {
                hour = parsed.hour
                minute = parsed.minute
                index += 2
                continue
            }
            rest.append(words[index])
            index += 1
        }
        return (rest, hour, minute, isArrival)
    }

    /// Removes the day phrase ("heute", "Freitag", "nächste Woche Freitag", "am 18.10.", "in 3 Tagen") and returns its day.
    private static func dayPart(_ words: [String], now: Date, calendar: Calendar) -> (rest: [String], day: Date?) {
        let today = calendar.startOfDay(for: now)
        var rest: [String] = []
        var day: Date?
        var index = 0
        while index < words.count {
            let folded = fold(words[index])
            let next = index + 1 < words.count ? fold(words[index + 1]) : ""
            if folded == "am", index + 1 < words.count, let found = dayWord(words[index + 1], now: now, calendar: calendar) {
                day = found
                index += 2
                continue
            }
            if ["nächste", "nächsten", "kommende"].contains(folded), next == "woche" {
                if index + 2 < words.count, let weekday = weekdayIndex(words[index + 2]),
                   let monday = calendar.date(byAdding: .day, value: 7, to: startOfWeek(today, calendar: calendar)) {
                    day = calendar.date(byAdding: .day, value: weekday, to: monday)
                    index += 3
                } else {
                    index += 2
                }
                continue
            }
            if folded == "in", index + 2 < words.count, let count = Int(words[index + 1]), (0...365).contains(count),
               fold(words[index + 2]).hasPrefix("tag") {
                day = calendar.date(byAdding: .day, value: count, to: today)
                index += 3
                continue
            }
            if let found = dayWord(words[index], now: now, calendar: calendar) {
                day = day ?? found
                index += 1
                continue
            }
            rest.append(words[index])
            index += 1
        }
        return (rest, day)
    }

    /// Whether the sentence names a day the way people write one: a weekday, heute, morgen, a Tag/Woche/Monat word, or a
    /// date such as 18.10. The validator takes a model's date only then (docs/LOCAL_AI.md §4.1).
    public static func namesDay(_ text: String, now: Date, calendar: Calendar = .vienna) -> Bool {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "," || $0 == ";" }).contains { raw in
            let word = String(raw)
            let folded = fold(word)
            if dayCueStems.contains(where: { folded.hasPrefix($0) }) { return true }
            if weekdayIndex(word) != nil { return true }
            return explicitDate(word, now: now, calendar: calendar) != nil
        }
    }

    /// Words that carry no place are dropped. The remaining words keep their casing ("St. Anton am Arlberg").
    private static func placeWords(_ words: [String]) -> [String] {
        words.filter { $0 != "," && !fillerWords.contains(fold($0)) }
    }

    // MARK: Day and time words

    private static func dayWord(_ word: String, now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        switch fold(word) {
        case "heute": return today
        case "morgen": return calendar.date(byAdding: .day, value: 1, to: today)
        case "übermorgen", "uebermorgen": return calendar.date(byAdding: .day, value: 2, to: today)
        default: break
        }
        if let weekday = weekdayIndex(word) {
            let delta = (weekday - mondayFirstIndex(today, calendar: calendar) + 7) % 7
            return calendar.date(byAdding: .day, value: delta, to: today)
        }
        return explicitDate(word, now: now, calendar: calendar)
    }

    /// "18.10." or "18.10.2026". Without a year the next occurrence of that date is used. "18.10" (no dot at the end and no
    /// year) stays a clock time, as before.
    private static func explicitDate(_ word: String, now: Date, calendar: Calendar) -> Date? {
        let parts = word.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let dottedDay = parts.count == 3 && parts[2].isEmpty && word.hasSuffix(".")
        let withYear = parts.count == 3 && parts[2].count == 4
        guard dottedDay || withYear,
              let day = Int(parts[0]), let month = Int(parts[1]), (1...31).contains(day), (1...12).contains(month) else {
            return nil
        }
        let today = calendar.startOfDay(for: now)
        let explicitYear = parts.count == 3 && !parts[2].isEmpty ? Int(parts[2]) : nil
        let year = explicitYear ?? calendar.component(.year, from: today)
        guard let date = makeDate(year: year, month: month, day: day, calendar: calendar) else { return nil }
        if explicitYear == nil, date < today {
            return makeDate(year: year + 1, month: month, day: day, calendar: calendar)
        }
        return date
    }

    /// "7", "7 Uhr", "7:30", "7.30". A word ending in a dot is a date ("18.10."), never a time.
    private static func clock(_ word: String) -> (hour: Int, minute: Int)? {
        guard !word.hasSuffix(".") else { return nil }
        let text = fold(word).replacingOccurrences(of: "uhr", with: "")
        let separator: Character = text.contains(":") ? ":" : "."
        let parts = text.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
        if parts.count == 1 {
            guard let hour = Int(parts[0]), (0...23).contains(hour), parts[0].count <= 2 else { return nil }
            return (hour, 0)
        }
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute), parts[1].count == 2 else { return nil }
        return (hour, minute)
    }

    /// Full German weekday names, and "Fr." style abbreviations only with their dot ("so" alone is a word, not Sunday).
    private static func weekdayIndex(_ word: String) -> Int? {
        let folded = fold(word)
        guard let index = weekdays[folded] else { return nil }
        return folded.count > 2 || word.hasSuffix(".") ? index : nil
    }

    // MARK: Calendar helpers

    /// Monday = 0 … Sunday = 6.
    private static func mondayFirstIndex(_ day: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: day) + 5) % 7
    }

    private static func startOfWeek(_ day: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .day, value: -mondayFirstIndex(start, calendar: calendar), to: start) ?? start
    }

    private static func nextOccurrence(of day: Date, atOrAfter anchor: Date, calendar: Calendar) -> Date {
        let base = calendar.startOfDay(for: anchor)
        let delta = (mondayFirstIndex(day, calendar: calendar) - mondayFirstIndex(base, calendar: calendar) + 7) % 7
        return calendar.date(byAdding: .day, value: delta, to: base) ?? base
    }

    static func makeDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else { return nil }
        // Rejects 31.02. and the like: the calendar rolls them over.
        let check = calendar.dateComponents([.day, .month], from: date)
        return check.day == day && check.month == month ? date : nil
    }

    // MARK: Words

    static func fold(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,!?:;"))
    }

    private static func joined(_ words: ArraySlice<String>) -> String? {
        let text = words.joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    private static func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:"))
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Prefixes of day words: "heute", "morgen", "nächsten", "in 3 Tagen", "zwei Wochen", "kommenden".
    private static let dayCueStems = ["heute", "morgen", "übermorgen", "uebermorgen", "übernächst", "nächst", "kommend", "tag", "woche", "monat"]
    private static let returnMarkers: Set<String> = ["rückfahrt", "rückfahrten", "rückweg", "rück", "zurück", "retour", "heimfahrt"]
    private static let destinationMarkers: Set<String> = ["nach", "richtung"]
    private static let timeMarkers: Set<String> = ["um", "ab", "gegen", "bis", "spätestens"]
    private static let weekdays: [String: Int] = [
        "montag": 0, "mo": 0, "dienstag": 1, "di": 1, "mittwoch": 2, "mi": 2, "donnerstag": 3, "do": 3,
        "freitag": 4, "fr": 4, "samstag": 5, "sa": 5, "sonnabend": 5, "sonntag": 6, "so": 6,
    ]
    private static let fillerWords: Set<String> = [
        "ich", "wir", "will", "möchte", "moechte", "würde", "fahre", "fahren", "fahrt", "brauche", "bitte", "gern", "gerne",
        "einen", "eine", "einmal", "zug", "bahn", "mit", "hin", "hinfahrt", "hinweg", "und", "den", "dem", "der", "die", "das",
        "nächste", "nächsten", "woche", "kommende", "uhr", "in", "tagen", "tag", "mir", "früh", "vormittags", "nachmittags",
        "abends", "morgens", "zu", "um", "gegen",
    ]
}
