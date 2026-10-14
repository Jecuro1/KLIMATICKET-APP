import Foundation

/// Sort orders of the Fahrplan results (docs/PLANNER.md §Sortierung). Pure: the app maps its rows to `ConnectionSortFacts`.
public enum ConnectionSort: String, CaseIterable, Codable, Sendable, Identifiable {
    /// The timetable order (departure, then duration): the default.
    case departure
    /// Shortest planned door-to-door time.
    case fastest
    case fewestChanges
    /// Lowest regular fare shown on the card (live quote or tariff table). Connections without a price sort last.
    case cheapest
    /// Lowest CO₂ estimate (`PlannerEmissions`, Umweltbundesamt factors).
    case lowestCO2

    public var id: String { rawValue }

    /// Segment title.
    public var title: String {
        switch self {
        case .departure: "Abfahrt"
        case .fastest: "Schnellste"
        case .fewestChanges: "Wenig Umstiege"
        case .cheapest: "Günstigste"
        case .lowestCO2: "Wenig CO₂"
        }
    }

    /// SF Symbol of the segment.
    public var symbol: String {
        switch self {
        case .departure: "clock"
        case .fastest: "hare.fill"
        case .fewestChanges: "arrow.triangle.swap"
        case .cheapest: "eurosign.circle"
        case .lowestCO2: "leaf.fill"
        }
    }

    /// The sort key in words, shown under the list ("honest labels": the price sort says which price it uses).
    public var caption: String {
        switch self {
        case .departure: "Nach Abfahrtszeit"
        case .fastest: "Nach Fahrzeit"
        case .fewestChanges: "Nach Umstiegen, dann Fahrzeit"
        case .cheapest: "Nach Normalpreis (Live oder Tarif-Tabelle). Ohne Preis ans Ende."
        case .lowestCO2: "Nach geschätzter CO₂-Menge (Umweltbundesamt), dann Fahrzeit"
        }
    }
}

/// What a sort needs to know about one connection. `nil` means unknown; unknown values sort last.
public struct ConnectionSortFacts: Sendable, Equatable {
    public var departure: Date?
    public var durationSeconds: Int?
    public var changes: Int
    public var priceEUR: Double?
    public var co2Kg: Double?

    public init(departure: Date?, durationSeconds: Int?, changes: Int, priceEUR: Double? = nil, co2Kg: Double? = nil) {
        self.departure = departure
        self.durationSeconds = durationSeconds
        self.changes = changes
        self.priceEUR = priceEUR
        self.co2Kg = co2Kg
    }
}

/// A result row the sort can order.
public protocol SortableConnection {
    var sortFacts: ConnectionSortFacts { get }
}

public enum ConnectionSorting {
    /// Orders the connections by `sort`. Ties keep the incoming order, so the sort is stable for equal keys.
    /// Every sort ends with the planned duration and the departure as tie-breakers.
    public static func sorted<T: SortableConnection>(_ items: [T], by sort: ConnectionSort) -> [T] {
        items.enumerated().sorted { lhs, rhs in
            let a = keys(lhs.element.sortFacts, sort), b = keys(rhs.element.sortFacts, sort)
            for (x, y) in zip(a, b) where x != y { return x < y }
            return lhs.offset < rhs.offset
        }
        .map(\.element)
    }

    /// The lexicographic key of one connection (`.infinity` for unknown values).
    static func keys(_ facts: ConnectionSortFacts, _ sort: ConnectionSort) -> [Double] {
        let duration = facts.durationSeconds.map(Double.init) ?? .infinity
        let departure = facts.departure?.timeIntervalSince1970 ?? .infinity
        switch sort {
        case .departure: return [departure, duration]
        case .fastest: return [duration, departure]
        case .fewestChanges: return [Double(facts.changes), duration, departure]
        case .cheapest: return [facts.priceEUR ?? .infinity, duration, departure]
        case .lowestCO2: return [facts.co2Kg ?? .infinity, duration, departure]
        }
    }
}
