import Foundation

// MARK: radar2-radarmine – „Meine Fahrzeuge“ (docs/RADAR_MINE.md §2): a line you remembered on the radar. Stored is only what names the line (its
// mode, the compact title „BUS13A“, the title „Bus 13A“), optionally a direction, and a coarse area: the centre of the level-3 radar tile where you
// remembered it (about 39 × 36 km), rounded to two decimals. Never a trip id (they are short-lived) and never a position of yours.

public struct RadarLineKey: Sendable, Hashable, Identifiable {
    /// The radar mode from the vehicle's class bit (never `Line.mode`, which calls rail replacement a bus).
    public var mode: RadarMode
    /// „BUS13A“, „S45“, „U6“, „TRAMD“, „RJX66“: the title without spaces, upper case.
    public var compact: String
    /// „Bus 13A“, „S 45“, „U6“, „Tram D“, „RJX 66“.
    public var title: String
    /// Only vehicles towards this destination (folded compare); nil: both directions.
    public var direction: String?
    /// Where the line was remembered, coarsely (the level-3 tile's centre); nil outside the radar's coverage.
    public var area: GeoPoint?

    public init(mode: RadarMode, compact: String, title: String, direction: String? = nil, area: GeoPoint? = nil) {
        self.mode = mode
        self.compact = compact
        self.title = title
        let trimmed = direction?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.direction = trimmed?.isEmpty == false ? trimmed : nil
        self.area = area
    }

    /// The key of a vehicle's line, remembered where the vehicle is now. nil without a line or for a class outside the radar's five modes
    /// (rail replacement, coaches, ships: „Andere“).
    public init?(vehicle: RadarVehicle, direction: String? = nil) {
        guard let line = vehicle.line, let identity = RadarLineKey.identity(of: line) else { return nil }
        self.init(mode: identity.mode, compact: identity.compact, title: LinePresentation.title(line), direction: direction,
                  area: RadarLineKey.area(of: vehicle.coordinate))
    }

    /// One line, one direction: „bus|BUS13A“ or „bus|BUS13A|hutteldorf“.
    public var id: String { direction.map { "\(lineID)|\(RadarText.fold($0))" } ?? lineID }

    /// The line without the direction: what `identity(of:)` gives for every vehicle of it.
    public var lineID: String { "\(mode.rawValue)|\(compact)" }

    /// The vehicle runs on this line (and towards its direction, when one is set). Different modes never match: „S 1“ is not „Bus 1“.
    public func matches(_ vehicle: RadarVehicle) -> Bool {
        guard let line = vehicle.line, let identity = RadarLineKey.identity(of: line), identity.id == lineID else { return false }
        guard let direction else { return true }
        return RadarText.fold(vehicle.direction ?? "") == RadarText.fold(direction)
    }

    /// A line for the plate of a remembered line whose vehicles are not loaded (only the key is stored): „Bus 13A“ → bus 13A, „S 45“ → S-Bahn 45,
    /// „U6“, „Tram D“, „RJX 66“ → railjet xpress 66. Its title is the key's title again.
    public var displayLine: Line {
        let words = title.split(separator: " ").map(String.init)
        let rest = words.count > 1 ? words.dropFirst().joined(separator: " ") : title
        switch mode {
        case .bus:
            return Line(name: title, category: "Bus", categoryShort: "bus", lineNumber: rest, productClass: 64, mode: .bus)
        case .tram:
            return Line(name: title, category: "Tram", categoryShort: "str", lineNumber: rest, productClass: 512, mode: .tram)
        case .subway:
            return Line(name: title, category: "U", categoryShort: "U", lineNumber: title, productClass: 256, mode: .metro)
        case .suburban:
            return Line(name: title, category: "S", categoryShort: "s", lineNumber: words.count > 1 ? rest : String(title.dropFirst()), productClass: 32,
                        mode: .sBahn)
        case .rail:
            let category = words.first ?? title
            let cls: Int
            switch RadarTrainClass.of(category: category) {
            case .rjx, .rj: cls = 1
            case .icec: cls = 4
            case .njen: cls = 8
            case .wb: cls = 4096
            default: cls = 16
            }
            return Line(name: title, category: category, categoryShort: category, trainNumber: words.count > 1 ? rest : nil, productClass: cls,
                        mode: .train)
        }
    }

    // MARK: Identity

    public struct Identity: Sendable, Hashable {
        public var mode: RadarMode
        public var compact: String
        public var id: String { "\(mode.rawValue)|\(compact)" }
    }

    /// Mode and compact title of a line; nil for a class outside the five modes or a line without a usable title.
    public static func identity(of line: Line) -> Identity? {
        guard let mode = RadarMode.of(productClass: line.productClass) else { return nil }
        let compact = RadarLine.compact(LinePresentation.title(line))
        guard !compact.isEmpty else { return nil }
        return Identity(mode: mode, compact: compact)
    }

    // MARK: Area

    /// The level of the radar's tile grid whose tile names the area (about 39 × 36 km).
    public static let areaLevel = 3

    /// The centre of the level-3 tile around `point`, rounded to two decimals; nil outside the grid's coverage or for a non-finite point.
    public static func area(of point: GeoPoint) -> GeoPoint? {
        guard point.latitude.isFinite, point.longitude.isFinite else { return nil }
        let probe = RadarBox(north: point.latitude + 1e-7, west: point.longitude - 1e-7, south: point.latitude - 1e-7, east: point.longitude + 1e-7)
        guard RadarTileGrid.coverage.contains(point),
              let tile = RadarTileGrid.tiles(intersecting: probe, level: areaLevel).first else { return nil }
        let centre = RadarTileGrid.box(of: tile).center
        return GeoPoint(latitude: (centre.latitude * 100).rounded() / 100, longitude: (centre.longitude * 100).rounded() / 100)
    }
}

/// The remembered lines in the order they were added: at most 20, no line twice. The 21st is refused, never an old one dropped silently.
public struct RadarMineLines: Sendable, Hashable {
    public static let capacity = 20

    public private(set) var keys: [RadarLineKey]

    public init(_ keys: [RadarLineKey] = []) {
        var seen: Set<String> = []
        self.keys = Array(keys.filter { seen.insert($0.id).inserted }.prefix(RadarMineLines.capacity))
    }

    public enum AddResult: Equatable, Sendable { case added, alreadyThere, full }

    public var isEmpty: Bool { keys.isEmpty }
    public var count: Int { keys.count }
    public var isFull: Bool { keys.count >= RadarMineLines.capacity }

    @discardableResult
    public mutating func add(_ key: RadarLineKey) -> AddResult {
        if keys.contains(where: { $0.id == key.id }) { return .alreadyThere }
        guard !isFull else { return .full }
        keys.append(key)
        return .added
    }

    public mutating func remove(id: String) {
        keys.removeAll { $0.id == id }
    }

    /// Removes every key of the vehicle's line (any direction).
    public mutating func remove(lineOf vehicle: RadarVehicle) {
        guard let id = vehicle.line.flatMap(RadarLineKey.identity(of:))?.id else { return }
        keys.removeAll { $0.lineID == id }
    }

    public mutating func removeAll() { keys = [] }

    /// The first key the vehicle matches.
    public func key(for vehicle: RadarVehicle) -> RadarLineKey? {
        keys.first { $0.matches(vehicle) }
    }

    public func contains(_ vehicle: RadarVehicle) -> Bool { key(for: vehicle) != nil }

    /// The line ids (without direction) of the keys that have no direction: a fast lookup for thousands of markers.
    public var wholeLineIDs: Set<String> { Set(keys.filter { $0.direction == nil }.map(\.lineID)) }
    /// Keys that only match one direction.
    public var directedKeys: [RadarLineKey] { keys.filter { $0.direction != nil } }
}

/// A stop you looked at on the „Haltestelle“ page (the last five): the app's station id, its name and where it is (public data, no position of
/// yours).
public struct RadarMineStop: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var coordinate: GeoPoint

    public init(id: String, name: String, coordinate: GeoPoint) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
    }
}
