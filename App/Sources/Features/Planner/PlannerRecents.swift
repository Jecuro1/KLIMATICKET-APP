import Foundation
import KlimaCore

/// The last places searched, newest first (UserDefaults `planner.recents`, JSON). Local only – never synced, no consent
/// needed. Stations are stored by id, live locations whole.
struct PlannerRecents {
    struct Entry: Codable, Equatable {
        var stationID: String?
        var location: Location?
        var title: String
    }

    static let limit = 8
    private static let key = "planner.recents"

    static func load(stations: StationIndex) -> [PlannerPlace] {
        guard let data = UserDefaults.standard.data(forKey: key), let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries.compactMap { entry in
            if let id = entry.stationID, let station = stations.station(id: id) { return .station(station) }
            if let location = entry.location { return .live(location) }
            return nil
        }
    }

    static func remember(_ place: PlannerPlace) {
        let entry: Entry
        switch place {
        case .station(let s): entry = Entry(stationID: s.id, location: nil, title: place.title)
        case .live(let l): entry = Entry(stationID: nil, location: l, title: place.title)
        case .currentLocation: return
        }
        var entries = loadEntries().filter { $0 != entry && !($0.stationID != nil && $0.stationID == entry.stationID) }
        entries.insert(entry, at: 0)
        if let data = try? JSONEncoder().encode(Array(entries.prefix(limit))) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }

    private static func loadEntries() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }
}
