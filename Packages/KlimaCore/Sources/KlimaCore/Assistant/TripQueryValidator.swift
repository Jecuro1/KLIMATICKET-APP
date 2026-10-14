import Foundation

/// What the on-device model returned for a trip query: plain strings, not yet trusted (docs/LOCAL_AI.md §3.1).
/// Empty string means "not in the sentence".
public struct TripQueryFields: Equatable, Sendable {
    public var origin: String
    public var destination: String
    /// yyyy-MM-dd
    public var outboundDay: String
    /// HH:mm
    public var outboundTime: String
    /// yyyy-MM-dd
    public var returnDay: String
    public var isArrival: Bool

    public init(origin: String = "", destination: String = "", outboundDay: String = "", outboundTime: String = "",
                returnDay: String = "", isArrival: Bool = false) {
        self.origin = origin
        self.destination = destination
        self.outboundDay = outboundDay
        self.outboundTime = outboundTime
        self.returnDay = returnDay
        self.isArrival = isArrival
    }
}

/// Keeps every model field that the user's own sentence supports and drops the rest. Nothing the model adds reaches the
/// planner unless it can be found in the text or is a plausible date (docs/LOCAL_AI.md §4: no invented places, times or
/// days).
public enum TripQueryValidator {
    /// `rejected` names the fields that were dropped, for tests and for the note under the result.
    public static func validate(_ fields: TripQueryFields, sourceText: String, now: Date, calendar: Calendar = .vienna)
        -> (draft: TripQueryDraft, rejected: [String]) {
        var rejected: [String] = []
        let source = fold(sourceText)
        let tokens = Set(AssistantNumberGuard.tokens(in: sourceText))
        let today = calendar.startOfDay(for: now)
        let horizon = calendar.date(byAdding: .day, value: 365, to: today) ?? today
        // A date from the model is taken only when the sentence names a day (weekday, heute, Woche, 18.10.): the model may
        // not pick one on its own (docs/LOCAL_AI.md §4.1).
        let namesDay = TripQueryParser.namesDay(sourceText, now: now, calendar: calendar)

        func place(_ raw: String, _ name: String) -> String? {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            guard value.count <= 60, !value.contains("\n"), source.contains(fold(value)) else {
                rejected.append(name)
                return nil
            }
            return value
        }

        func day(_ raw: String, _ name: String, notBefore lower: Date) -> Date? {
            guard !raw.isEmpty else { return nil }
            let parts = raw.split(separator: "-").compactMap { Int($0) }
            guard namesDay else {
                rejected.append(name)
                return nil
            }
            guard parts.count == 3, let date = TripQueryParser.makeDate(year: parts[0], month: parts[1], day: parts[2],
                                                                         calendar: calendar),
                  date >= lower, date <= horizon else {
                rejected.append(name)
                return nil
            }
            return date
        }

        var draft = TripQueryDraft(source: .model)
        draft.origin = place(fields.origin, "origin")
        draft.destination = place(fields.destination, "destination")
        draft.outboundDay = day(fields.outboundDay, "outboundDay", notBefore: today)
        if !fields.outboundTime.isEmpty {
            let parts = fields.outboundTime.split(separator: ":").compactMap { Int($0) }
            // A time must be in the sentence: the hour (and the minutes, when not :00) appear as numbers in it.
            if parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]),
               tokens.contains(String(parts[0])), parts[1] == 0 || tokens.contains(String(parts[1])) {
                draft.outboundHour = parts[0]
                draft.outboundMinute = parts[1]
            } else {
                rejected.append("outboundTime")
            }
        }
        // "bis 9 Uhr" is an arrival only when the sentence says so, as a word ("bisher" is not "bis").
        let words = Set(source.split(whereSeparator: { !$0.isLetter }).map(String.init))
        let arrivalWords: Set<String> = ["bis", "ankunft", "spatestens", "ankommen"]
        draft.isArrival = fields.isArrival && !words.isDisjoint(with: arrivalWords)
        if let outbound = draft.outboundDay {
            draft.returnDay = day(fields.returnDay, "returnDay", notBefore: outbound)
        } else {
            draft.returnDay = day(fields.returnDay, "returnDay", notBefore: today)
        }
        return (draft, rejected)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_AT"))
    }
}
