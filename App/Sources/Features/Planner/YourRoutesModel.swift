import Foundation
import KlimaCore

/// „Deine Strecken“: the relations the user rides most (docs/OEBB_LIVE.md §E3) – favourites first, then the trips of the
/// last 90 days by how often each relation was logged. Both stations must be known app stations.
enum YourRoutes {
    static func relations(trips: [TripEntity], favorites: [FavoriteRouteEntity], stations: StationIndex, now: Date = Date(),
                          limit: Int = 3) -> [(from: Station, to: Station)] {
        var ordered: [String] = []
        var pairs: [String: (String, String)] = [:]
        func add(_ from: String?, _ to: String?) {
            guard let from, let to, from != to else { return }
            let key = "\(from)>\(to)"
            if pairs[key] == nil { pairs[key] = (from, to); ordered.append(key) }
        }
        for favorite in favorites.sorted(by: { $0.sortIndex < $1.sortIndex }) where favorite.deletedAt == nil {
            add(favorite.fromStationID, favorite.toStationID)
        }
        let cutoff = now.addingTimeInterval(-90 * 86_400)
        var counts: [String: Int] = [:]
        for trip in trips where trip.deletedAt == nil && trip.date >= cutoff && trip.journeyID == nil {
            guard let from = trip.fromStationID, let to = trip.toStationID, from != to else { continue }
            counts["\(from)>\(to)", default: 0] += 1
            if pairs["\(from)>\(to)"] == nil { pairs["\(from)>\(to)"] = (from, to) }
        }
        let frequent = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
        for key in frequent where !ordered.contains(key) { ordered.append(key) }
        var out: [(from: Station, to: Station)] = []
        for key in ordered {
            guard let ids = pairs[key], let a = stations.station(id: ids.0), let b = stations.station(id: ids.1) else { continue }
            out.append((a, b))
            if out.count == limit { break }
        }
        return out
    }
}
