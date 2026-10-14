import Foundation

/// A search as a link: `klimabilanz://plan?from=…&to=…&via=…&at=<ISO 8601>&arr=0|1` (docs/PLANNER.md §Deep-Links).
/// The places are station ids (`uic:…`) or names; the app resolves them. A link opens the search in the app, nothing is sent.
public struct PlannerLink: Equatable, Sendable {
    public var from: String
    public var to: String
    /// Via stops in travel order; at most `JourneyQuery.maxViaStops` are kept.
    public var vias: [String]
    /// nil = „Jetzt“ / the next departure.
    public var at: Date?
    public var isArrival: Bool

    public init(from: String, to: String, vias: [String] = [], at: Date? = nil, isArrival: Bool = false) {
        self.from = from
        self.to = to
        self.vias = Array(vias.prefix(JourneyQuery.maxViaStops))
        self.at = at
        self.isArrival = isArrival
    }

    public static let scheme = "klimabilanz"
    public static let host = "plan"

    /// The link for this search; nil only when the parts cannot form a URL.
    public var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        var items = [URLQueryItem(name: "from", value: from), URLQueryItem(name: "to", value: to)]
        items += vias.map { URLQueryItem(name: "via", value: $0) }
        if let at { items.append(URLQueryItem(name: "at", value: Self.isoText(at))) }
        items.append(URLQueryItem(name: "arr", value: isArrival ? "1" : "0"))
        components.queryItems = items
        return components.url
    }

    /// Reads a planner link. nil for any other URL, or when `from` or `to` is missing or empty.
    public static func parse(_ url: URL) -> PlannerLink? {
        guard url.scheme == scheme, url.host == host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            guard let raw = items.first(where: { $0.name == name })?.value else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let from = value("from"), let to = value("to") else { return nil }
        let vias = items.filter { $0.name == "via" }.compactMap { $0.value?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let at = value("at").flatMap(isoDate)
        return PlannerLink(from: from, to: to, vias: vias, at: at, isArrival: value("arr") == "1")
    }

    static func isoText(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func isoDate(_ text: String) -> Date? {
        ISO8601DateFormatter().date(from: text)
    }
}

/// When a departure reminder fires (docs/PLANNER.md §Erinnerung). The app schedules a local notification at that date.
public enum PlannerReminder {
    /// Lead times the detail offers.
    public static let leadMinutes = [5, 10, 15, 30]

    /// `lead` minutes before the planned departure; nil when that moment has already passed (no reminder for a train
    /// that is leaving now).
    public static func fireDate(departure: Date, leadMinutes lead: Int, now: Date) -> Date? {
        let fire = departure.addingTimeInterval(-Double(max(0, lead)) * 60)
        return fire > now ? fire : nil
    }
}
