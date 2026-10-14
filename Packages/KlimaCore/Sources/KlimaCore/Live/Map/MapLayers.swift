import Foundation

// Scotty-style map layers (docs/OEBB_LIVE.md §R10). Pure values: which layers are on, which stations are in view, how
// station markers group at a zoom, and the straight-line sketch of a saved route. The base map is MapKit and stays as it
// is (owner decision still open); every layer is drawn on top of it and does not depend on the base map.

/// The layers of the map, in the order of the glass bar.
public enum MapLayer: String, CaseIterable, Sendable, Hashable {
    case stations, trains, disruptions, routes

    public var title: String {
        switch self {
        case .stations: "Stationen"
        case .trains: "Züge"
        case .disruptions: "Störungen"
        case .routes: "Meine Routen"
        }
    }
}

/// Which layers are on. The stored form ("stations,trains") is per device; unknown words are dropped, so an old or
/// damaged value never breaks the map. An empty value means every layer is off.
public struct MapLayerSelection: Sendable, Equatable {
    public private(set) var layers: Set<MapLayer>

    /// The first view: stations and trains (the Scotty default). Disruptions and routes are opt-in.
    public static let initial = MapLayerSelection(layers: [.stations, .trains])
    public static let all = MapLayerSelection(layers: Set(MapLayer.allCases))

    public init(layers: Set<MapLayer> = []) {
        self.layers = layers
    }

    public init(storageValue: String) {
        let words = Set(storageValue.split(separator: ",").map { String($0) })
        layers = Set(MapLayer.allCases.filter { words.contains($0.rawValue) })
    }

    public func isOn(_ layer: MapLayer) -> Bool { layers.contains(layer) }

    public mutating func toggle(_ layer: MapLayer) {
        if !layers.insert(layer).inserted { layers.remove(layer) }
    }

    public var storageValue: String {
        MapLayer.allCases.filter { layers.contains($0) }.map(\.rawValue).joined(separator: ",")
    }
}

/// A station as the map sees it: id, name and coordinate (from the station index, no request).
public struct MapStationPin: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var coordinate: GeoPoint

    public init(id: String, name: String, coordinate: GeoPoint) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
    }
}

public enum MapStations {
    /// Station markers are drawn only when the view is this close (about 180 km of latitude). A country-wide view would
    /// draw thousands of stops; the layer says "Zoom näher heran" instead.
    public static let maxLatitudeSpan: Double = 1.6
    /// At most this many markers are handed to the map, in name order.
    public static let limit = 250

    public static func isDrawn(latitudeSpan span: Double) -> Bool {
        span.isFinite && span > 0 && span <= maxLatitudeSpan
    }

    /// The stations inside the box, in name order, at most `limit`. Deterministic for the same input.
    public static func visible(_ stations: [MapStationPin], in box: RadarBox, limit: Int = limit) -> [MapStationPin] {
        guard box.isValid else { return [] }
        return stations
            .filter { box.contains($0.coordinate) }
            .sorted { a, b in a.name != b.name ? a.name < b.name : a.id < b.id }
            .prefix(limit)
            .map { $0 }
    }
}

/// Station markers that share a grid cell. A cluster with one member is drawn as that station.
public struct MapCluster: Sendable, Hashable, Identifiable {
    public var id: String
    public var center: GeoPoint
    public var memberIDs: [String]

    public init(id: String, center: GeoPoint, memberIDs: [String]) {
        self.id = id
        self.center = center
        self.memberIDs = memberIDs
    }

    public var count: Int { memberIDs.count }
    public var isSingle: Bool { memberIDs.count == 1 }
}

public enum MapClustering {
    /// Groups by grid cell. The cell size follows the zoom (`RadarClustering.cellSize`), so markers merge only where they
    /// would overlap. Output is ordered by cell key: the same input always gives the same ids.
    public static func group(_ pins: [MapStationPin], cellDegrees: Double) -> [MapCluster] {
        guard cellDegrees > 0, cellDegrees.isFinite else { return [] }
        var cells: [String: [MapStationPin]] = [:]
        for pin in pins {
            let row = Int((pin.coordinate.latitude / cellDegrees).rounded(.down))
            let column = Int((pin.coordinate.longitude / cellDegrees).rounded(.down))
            cells["\(row)|\(column)", default: []].append(pin)
        }
        return cells.keys.sorted().map { key in
            let members = cells[key] ?? []
            let lat = members.reduce(0) { $0 + $1.coordinate.latitude } / Double(members.count)
            let lon = members.reduce(0) { $0 + $1.coordinate.longitude } / Double(members.count)
            return MapCluster(id: key, center: GeoPoint(latitude: lat, longitude: lon),
                              memberIDs: members.map(\.id).sorted())
        }
    }
}

/// The sketch of a saved route: its known places in order, joined by straight lines. The sketch is not the rail line; the
/// legend says so. Stops without a known place are left out, and a route needs at least two known places.
public enum MapRouteSketch {
    public static func points(_ stops: [GeoPoint?]) -> [GeoPoint]? {
        let known = stops.compactMap { $0 }
        return known.count >= 2 ? known : nil
    }
}
