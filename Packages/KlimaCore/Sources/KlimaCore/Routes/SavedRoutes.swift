import Foundation

// „Meine Routen“ (docs/ROUTES_ALARMS.md §1): ordering, the route line and the figures shown per route. The figures use the
// app's emission factors (`EmissionFactors`, Umweltbundesamt) and the stored fare; nothing here reads the network.

public enum SavedRoutes {
    /// Moves the items like SwiftUI's `Array.move(fromOffsets:toOffset:)`, without importing SwiftUI. `destination` is an
    /// index of the original array, as `onMove` reports it.
    public static func moved<T>(_ items: [T], from offsets: IndexSet, to destination: Int) -> [T] {
        let indexes = offsets.sorted().filter { items.indices.contains($0) }
        guard !indexes.isEmpty else { return items }
        let moving = indexes.map { items[$0] }
        var rest = items.enumerated().filter { !indexes.contains($0.offset) }.map(\.element)
        let removedBefore = indexes.filter { $0 < destination }.count
        let insertAt = min(max(destination - removedBefore, 0), rest.count)
        rest.insert(contentsOf: moving, at: insertAt)
        return rest
    }

    /// "St. Anton → Lech → Innsbruck": the stations in travel order, empty names dropped.
    public static func routeLine(from: String, via: [String] = [], to: String) -> String {
        ([from] + via + [to]).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            .joined(separator: " → ")
    }

    /// CO₂ in kg of one ride of `distanceKm` by `mode`, with the app's emission factors (g per passenger-km).
    public static func co2Kg(distanceKm: Double, mode: TransportMode, factors: EmissionFactors = .fallback) -> Double {
        max(0, distanceKm) * factors.grams(for: mode) / 1000
    }

    /// The first cached connection whose departure (real-time when known) is not earlier than `now` minus `grace` seconds.
    /// The cache is written by the app's live refresh, so this only reads.
    public static func nextConnection(in connections: [WidgetConnection], now: Date, grace: TimeInterval = 60) -> WidgetConnection? {
        func departure(_ connection: WidgetConnection) -> Date { connection.realtime ?? connection.planned }
        return connections
            .filter { departure($0) >= now.addingTimeInterval(-grace) }
            .min { departure($0) < departure($1) }
    }
}
