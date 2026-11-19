import Foundation

// MARK: radar2-radarmine – the one file of „Meine Fahrzeuge“ (docs/RADAR_MINE.md §6): `RadarMine/mine.json` in Application Support, excluded from the
// iPhone backup, never in UserDefaults (that is part of the backup, and the last five stops say where you wait). Versioned JSON with tolerant
// decoding: an unknown version or garbage is an empty file, an entry that cannot be read is dropped, never a crash. The app reads and writes it
// (`RadarMineStore`); this is the pure part.

public struct RadarMineFile: Sendable, Hashable {
    public static let version = 1
    /// The last stops of the „Haltestelle“ page.
    public static let recentStopLimit = 5

    public var lines: RadarMineLines
    public var stops: [RadarMineStop]
    /// „Nur meine Linien hervorheben“.
    public var highlight: Bool

    public init(lines: RadarMineLines = RadarMineLines(), stops: [RadarMineStop] = [], highlight: Bool = false) {
        self.lines = lines
        var seen: Set<String> = []
        self.stops = Array(stops.filter { seen.insert($0.id).inserted }.prefix(RadarMineFile.recentStopLimit))
        self.highlight = highlight
    }

    public static let empty = RadarMineFile()

    public var isEmpty: Bool { lines.isEmpty && stops.isEmpty && !highlight }

    /// A stop was looked at: it goes first, the oldest beyond five goes.
    public mutating func noteStop(_ stop: RadarMineStop) {
        stops.removeAll { $0.id == stop.id }
        stops.insert(stop, at: 0)
        if stops.count > RadarMineFile.recentStopLimit { stops.removeLast(stops.count - RadarMineFile.recentStopLimit) }
    }

    // MARK: JSON

    public func encoded() -> Data {
        var object: [String: Any] = ["version": RadarMineFile.version]
        object["lines"] = lines.keys.map { key -> [String: Any] in
            var entry: [String: Any] = ["mode": key.mode.rawValue, "compact": key.compact, "title": key.title]
            if let direction = key.direction { entry["direction"] = direction }
            if let area = key.area { entry["lat"] = area.latitude; entry["lon"] = area.longitude }
            return entry
        }
        object["stops"] = stops.map { ["id": $0.id, "name": $0.name, "lat": $0.coordinate.latitude, "lon": $0.coordinate.longitude] as [String: Any] }
        if highlight { object["highlight"] = true }
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }

    /// From the stored bytes: an unknown version or anything unreadable is the empty file; an entry with a missing or wrong field is dropped.
    public init(data: Data) {
        self.init()
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              object["version"] as? Int == RadarMineFile.version else { return }
        let keys = ((object["lines"] as? [Any]) ?? []).compactMap { raw -> RadarLineKey? in
            guard let entry = raw as? [String: Any],
                  let mode = (entry["mode"] as? String).flatMap(RadarMode.init(rawValue:)),
                  let compact = entry["compact"] as? String, !compact.isEmpty,
                  let title = entry["title"] as? String, !title.isEmpty else { return nil }
            return RadarLineKey(mode: mode, compact: compact, title: title, direction: entry["direction"] as? String,
                                area: Self.point(entry))
        }
        let stops = ((object["stops"] as? [Any]) ?? []).compactMap { raw -> RadarMineStop? in
            guard let entry = raw as? [String: Any], let id = entry["id"] as? String, !id.isEmpty,
                  let name = entry["name"] as? String, let point = Self.point(entry) else { return nil }
            return RadarMineStop(id: id, name: name, coordinate: point)
        }
        self.init(lines: RadarMineLines(keys), stops: stops, highlight: object["highlight"] as? Bool ?? false)
    }

    private static func point(_ entry: [String: Any]) -> GeoPoint? {
        guard let lat = (entry["lat"] as? NSNumber)?.doubleValue, let lon = (entry["lon"] as? NSNumber)?.doubleValue,
              lat.isFinite, lon.isFinite, abs(lat) <= 90, abs(lon) <= 180 else { return nil }
        return GeoPoint(latitude: lat, longitude: lon)
    }
}
