import Foundation

// Zug-Radar, pure logic for the map (docs/OEBB_LIVE.md §R7). No UI, no network, no clock: every function takes `now`.
// Covers: viewport tiling past the server cap, frame retention (60 s), estimates between two answers, the delay tint,
// the filter sheet, the search with suggestions, the clusters and the summary line.

// MARK: - Tiling and frame retention

public enum RadarTiling {
    /// HAFAS answers at most this many vehicles per JourneyGeoPos request (`maxJny`).
    public static let serverCap = 256
    /// Most rectangles per refresh (one request each; the caller keeps the 40 requests/min throttle).
    public static let maxTiles = 4
    /// A vehicle stays on the map this long after the last answer that contained it.
    public static let frameRetention: TimeInterval = 60

    /// True when one answer was cut off at the server cap: the view then has to be split.
    public static func isTruncated(count: Int) -> Bool { count >= serverCap }

    /// The rectangles to request for `box`. One rectangle normally; after a truncated answer the four quadrants.
    public static func tiles(for box: RadarBox, split: Bool) -> [RadarBox] {
        guard box.isValid else { return [] }
        return split ? quadrants(of: box) : [box]
    }

    /// The four quadrants of a valid box (north-west, north-east, south-west, south-east).
    public static func quadrants(of box: RadarBox) -> [RadarBox] {
        guard box.isValid else { return [] }
        let midLat = (box.north + box.south) / 2
        let midLon = (box.east + box.west) / 2
        return [
            RadarBox(north: box.north, west: box.west, south: midLat, east: midLon),
            RadarBox(north: box.north, west: midLon, south: midLat, east: box.east),
            RadarBox(north: midLat, west: box.west, south: box.south, east: midLon),
            RadarBox(north: midLat, west: midLon, south: box.south, east: box.east),
        ]
    }
}

/// Vehicles of the last answers, merged across tiles. A vehicle that is missing from one answer (a tile that was not
/// asked, a failed refresh) stays for `retention` seconds, so the map does not flicker. Each entry keeps the previous
/// server position, which is what the estimate between two answers interpolates from.
public struct RadarFrameStore: Sendable {
    public struct Entry: Sendable, Hashable {
        public var vehicle: RadarVehicle
        /// When the latest answer containing this vehicle was received.
        public var seenAt: Date
        /// The position of the answer before the latest one, and when that answer was received.
        public var previousCoordinate: GeoPoint?
        public var previousSeenAt: Date?
    }

    public let retention: TimeInterval
    public private(set) var entries: [String: Entry] = [:]

    public init(retention: TimeInterval = RadarTiling.frameRetention) {
        self.retention = retention
    }

    /// Merges one answer (one tile or several tiles of the same refresh). The previous point is always the position of the
    /// answer before this one, so a vehicle that stands still interpolates from its own position and stays there.
    public mutating func merge(_ vehicles: [RadarVehicle], at now: Date) {
        for vehicle in vehicles {
            if let old = entries[vehicle.tripID] {
                entries[vehicle.tripID] = Entry(
                    vehicle: vehicle, seenAt: now,
                    previousCoordinate: old.vehicle.coordinate, previousSeenAt: old.seenAt)
            } else {
                entries[vehicle.tripID] = Entry(vehicle: vehicle, seenAt: now, previousCoordinate: nil, previousSeenAt: nil)
            }
        }
    }

    /// Drops vehicles that were not seen for longer than `retention`.
    public mutating func prune(now: Date) {
        entries = entries.filter { now.timeIntervalSince($0.value.seenAt) <= retention }
    }

    /// The vehicles to draw at `now`, after pruning, ordered by trip id (stable for tests and cluster ids).
    public mutating func visible(at now: Date) -> [Entry] {
        prune(now: now)
        return entries.values.sorted { $0.vehicle.tripID < $1.vehicle.tripID }
    }
}

// MARK: - Estimates between two answers

public enum RadarEstimate {
    /// The map draws every train this long behind the clock. The refresh runs every 20 s: the latest answer is always in
    /// the past, so without the lag the interpolation between two answers would never run and the marker would jump.
    /// With the lag the marker moves from the previous answer to the latest one over one interval and then holds there.
    public static let displayLag: TimeInterval = 20

    /// The position drawn at `now`: `position(of:at:)` at `now` minus `displayLag`.
    public static func shown(_ entry: RadarFrameStore.Entry, now: Date) -> (coordinate: GeoPoint, isEstimate: Bool) {
        position(of: entry, at: now.addingTimeInterval(-displayLag))
    }

    /// Position at `at`. Between two answers the position moves linearly from the previous server position to the
    /// latest one (the server computes the positions, `trainPosMode` CALC); after the latest answer it holds there.
    /// `isEstimate` is true while `at` lies between two answers that differ, so the UI marks only real movement.
    public static func position(of entry: RadarFrameStore.Entry, at at: Date) -> (coordinate: GeoPoint, isEstimate: Bool) {
        guard let from = entry.previousCoordinate, let fromAt = entry.previousSeenAt,
              entry.seenAt > fromAt else {
            return (entry.vehicle.coordinate, false)
        }
        let to = entry.vehicle.coordinate
        guard from != to else { return (to, false) }
        let span = entry.seenAt.timeIntervalSince(fromAt)
        let t = min(max(at.timeIntervalSince(fromAt) / span, 0), 1)
        let point = GeoPoint(latitude: from.latitude + (to.latitude - from.latitude) * t,
                             longitude: from.longitude + (to.longitude - from.longitude) * t)
        return (point, t < 1)
    }
}

// MARK: - Delay tint

/// What the marker tint says about the train (owner: on time / 5+ minutes late / cancelled).
public enum RadarDelayState: String, Sendable, Hashable, CaseIterable {
    case onTime, late, cancelled, unknown
}

public enum RadarDelay {
    /// Five minutes: from here on the marker is "verspätet".
    public static let lateThresholdSeconds = 300

    public static func state(of vehicle: RadarVehicle, now: Date) -> RadarDelayState {
        if vehicle.isCancelled { return .cancelled }
        guard let seconds = currentDelay(of: vehicle, now: now) else { return .unknown }
        return seconds >= lateThresholdSeconds ? .late : .onTime
    }

    /// The delay the train carries now: the realtime delay of the next stop it has not reached yet. Delays propagate
    /// forward, so a stop without realtime data falls back to the last stop that has one.
    public static func currentDelay(of vehicle: RadarVehicle, now: Date) -> Int? {
        let next = vehicle.stopovers.first { stop in
            guard let planned = stop.departure?.planned ?? stop.arrival?.planned else { return false }
            return planned > now
        }
        if let next, let delay = next.arrival?.delaySeconds ?? next.departure?.delaySeconds {
            return delay
        }
        return vehicle.stopovers.reversed().lazy.compactMap { $0.departure?.delaySeconds ?? $0.arrival?.delaySeconds }.first
    }
}

// MARK: - Regions by keyword (heuristic)

/// The nine Austrian Bundesländer. Assigned by keyword: a vehicle belongs to the region whose stop names and direction
/// mention the most of its keywords. There are no coordinates per region in our data, so this is an estimate.
public enum AustrianState: String, CaseIterable, Sendable, Hashable {
    case wien, niederoesterreich, burgenland, steiermark, kaernten, oberoesterreich, salzburg, tirol, vorarlberg

    public var title: String {
        switch self {
        case .wien: "Wien"
        case .niederoesterreich: "Niederösterreich"
        case .burgenland: "Burgenland"
        case .steiermark: "Steiermark"
        case .kaernten: "Kärnten"
        case .oberoesterreich: "Oberösterreich"
        case .salzburg: "Salzburg"
        case .tirol: "Tirol"
        case .vorarlberg: "Vorarlberg"
        }
    }

    /// Single words, already folded (lower case, no diacritics). Chosen from the main stations of each region.
    var keywords: Set<String> {
        switch self {
        case .wien: ["wien", "floridsdorf", "meidling", "favoriten", "penzing", "hutteldorf", "simmering"]
        case .niederoesterreich: ["polten", "amstetten", "krems", "tulln", "neustadt", "modling", "baden", "melk", "ybbs",
                                  "mistelbach", "gmund", "traisen", "hollabrunn", "gmunden"]
        case .burgenland: ["eisenstadt", "oberwart", "neusiedl", "pinkafeld", "mattersburg", "neudorf"]
        case .steiermark: ["graz", "leoben", "knittelfeld", "spielfeld", "kapfenberg", "judenburg", "murzzuschlag", "selzthal",
                           "steiermark"]
        case .kaernten: ["klagenfurt", "villach", "spittal", "wolfsberg", "karnten", "kaernten"]
        case .oberoesterreich: ["linz", "wels", "steyr", "attnang", "vocklabruck", "braunau", "innkreis", "ischl", "lambach",
                                "schwanenstadt", "freistadt", "oberosterreich"]
        case .salzburg: ["salzburg", "bischofshofen", "hallein", "saalfelden", "taxenbach", "gastein", "mittersill", "schwarzach"]
        case .tirol: ["innsbruck", "worgl", "kufstein", "jenbach", "schwaz", "landeck", "kitzbuhel", "reutte", "telfs", "imst",
                      "seefeld", "brixlegg", "wattens", "lienz", "tirol", "otztal"]
        case .vorarlberg: ["bregenz", "dornbirn", "feldkirch", "bludenz", "lustenau", "hohenems", "bezau", "lauterach", "vorarlberg"]
        }
    }

    /// The region with the most keyword hits in the stop names and the direction; nil when nothing or a tie matches.
    public static func guess(for vehicle: RadarVehicle) -> AustrianState? {
        var haystack = vehicle.stopovers.map { $0.location.name }
        if let direction = vehicle.direction { haystack.append(direction) }
        let words = Set(haystack.flatMap { RadarText.words($0) })
        var best: (state: AustrianState, hits: Int)?
        var tied = false
        for state in AustrianState.allCases {
            let hits = state.keywords.intersection(words).count
            guard hits > 0 else { continue }
            if let current = best {
                if hits > current.hits { best = (state, hits); tied = false }
                else if hits == current.hits { tied = true }
            } else {
                best = (state, hits)
            }
        }
        guard let best, !tied else { return nil }
        return best.state
    }
}

// MARK: - Filter sheet

/// The radar filter. The transport mode is not here: it is a server-side product filter (`RadarQuery.products`).
public struct RadarFilter: Sendable, Hashable {
    /// Line categories ("RJX", "REX", "S", "Bus"); empty = all.
    public var categories: Set<String> = []
    /// Delay states to show; empty = all.
    public var delays: Set<RadarDelayState> = []
    /// Region by keyword (heuristic); nil = all.
    public var state: AustrianState?
    /// Only trains that are 5 minutes or more late.
    public var onlyLate: Bool = false

    public init(categories: Set<String> = [], delays: Set<RadarDelayState> = [], state: AustrianState? = nil, onlyLate: Bool = false) {
        self.categories = categories
        self.delays = delays
        self.state = state
        self.onlyLate = onlyLate
    }

    public var isActive: Bool { !categories.isEmpty || !delays.isEmpty || state != nil || onlyLate }

    public func matches(_ vehicle: RadarVehicle, now: Date) -> Bool {
        if !categories.isEmpty, !categories.contains(RadarLine.category(of: vehicle.line)) { return false }
        let delay = RadarDelay.state(of: vehicle, now: now)
        if !delays.isEmpty, !delays.contains(delay) { return false }
        if onlyLate, delay != .late { return false }
        if let state, AustrianState.guess(for: vehicle) != state { return false }
        return true
    }

    public func apply(_ vehicles: [RadarVehicle], now: Date) -> [RadarVehicle] {
        isActive ? vehicles.filter { matches($0, now: now) } : vehicles
    }
}

/// Helpers for line names ("RJX 66", "REX 92", "S 45", "Bus 750").
public enum RadarLine {
    /// The category of a line: `Line.category` when given, else the first word of the name, upper case.
    public static func category(of line: Line?) -> String {
        guard let line else { return "" }
        if let category = line.category, !category.isEmpty { return category.uppercased() }
        return line.name.split(separator: " ").first.map { String($0).uppercased() } ?? ""
    }

    /// "RJX 66" → "RJX66": the form the search compares, so "rjx66", "RJX 66" and "rjx 66" all match.
    public static func compact(_ name: String) -> String {
        name.uppercased().filter { !$0.isWhitespace }
    }
}

// MARK: - Search

/// What the user typed: "RJX 66", "RJX66", "REX 92", "66" or a plain word (a stop or direction).
public struct RadarSearchQuery: Sendable, Hashable {
    /// Line category, upper case ("RJX"), when the text starts with letters.
    public var category: String?
    /// Train or line number ("66"), when the text contains digits.
    public var number: String?
    /// The text without category and number, folded, for stop and direction names.
    public var text: String

    public init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let compact = RadarLine.compact(trimmed)
        let letters = String(compact.prefix { $0.isLetter })
        let digits = String(compact.dropFirst(letters.count).prefix { $0.isNumber })
        // Letters are a category only in front of a number ("RJX 66"). "Wien" or "RJX" alone stay text.
        category = digits.isEmpty || letters.isEmpty ? nil : letters
        number = digits.isEmpty ? nil : digits
        text = RadarText.fold(trimmed)
    }

    /// With a number: category (when typed) and number must match the line name. Without one: the text is a line
    /// category ("RJX") or a word in a stop name or the direction ("Innsbruck").
    public func matches(_ vehicle: RadarVehicle) -> Bool {
        if let number {
            if let category, RadarLine.category(of: vehicle.line) != category { return false }
            guard let name = vehicle.line?.name else { return false }
            return name.split(separator: " ").contains { String($0) == number }
        }
        if RadarLine.category(of: vehicle.line) == RadarLine.compact(text).uppercased() { return true }
        if RadarText.fold(vehicle.direction ?? "").contains(text) { return true }
        return vehicle.stopovers.contains { RadarText.fold($0.location.name).contains(text) }
    }
}

public enum RadarSearch {
    /// Matching vehicles, one per line name, ordered by name. Used for the suggestions under the search field.
    public static func suggestions(for query: RadarSearchQuery, in vehicles: [RadarVehicle], limit: Int = 8) -> [RadarVehicle] {
        var seen = Set<String>()
        var result: [RadarVehicle] = []
        for vehicle in vehicles.sorted(by: { ($0.line?.name ?? "") < ($1.line?.name ?? "") }) where query.matches(vehicle) {
            let key = vehicle.line.map { RadarLine.compact($0.name) } ?? vehicle.tripID
            guard seen.insert(key).inserted else { continue }
            result.append(vehicle)
            if result.count == limit { break }
        }
        return result
    }
}

// MARK: - Clusters

/// A vehicle as the clustering sees it.
public struct RadarPoint: Sendable, Hashable {
    public var tripID: String
    public var coordinate: GeoPoint
    public var delay: RadarDelayState

    public init(tripID: String, coordinate: GeoPoint, delay: RadarDelayState) {
        self.tripID = tripID
        self.coordinate = coordinate
        self.delay = delay
    }
}

/// Vehicles that share a grid cell. A cluster with one member is drawn as that vehicle.
public struct RadarCluster: Sendable, Hashable, Identifiable {
    public var id: String
    public var center: GeoPoint
    public var tripIDs: [String]
    public var lateCount: Int
    public var cancelledCount: Int

    public var count: Int { tripIDs.count }
    public var isSingle: Bool { tripIDs.count == 1 }
}

public enum RadarClustering {
    /// Grid cell in degrees for a visible latitude span: about seven cells across the screen, so markers only merge
    /// when they would overlap at this zoom.
    public static func cellSize(forLatitudeSpan span: Double) -> Double {
        guard span.isFinite, span > 0 else { return 0.01 }
        return max(span / 7, 0.005)
    }

    /// Groups points by grid cell. Output is ordered by cell key, so the same input always gives the same ids.
    public static func group(_ points: [RadarPoint], cellDegrees: Double) -> [RadarCluster] {
        guard cellDegrees > 0, cellDegrees.isFinite else { return [] }
        var cells: [String: [RadarPoint]] = [:]
        for point in points {
            let row = Int((point.coordinate.latitude / cellDegrees).rounded(.down))
            let column = Int((point.coordinate.longitude / cellDegrees).rounded(.down))
            cells["\(row)|\(column)", default: []].append(point)
        }
        return cells.keys.sorted().map { key in
            let members = cells[key] ?? []
            let lat = members.reduce(0) { $0 + $1.coordinate.latitude } / Double(members.count)
            let lon = members.reduce(0) { $0 + $1.coordinate.longitude } / Double(members.count)
            return RadarCluster(
                id: key,
                center: GeoPoint(latitude: lat, longitude: lon),
                tripIDs: members.map(\.tripID).sorted(),
                lateCount: members.filter { $0.delay == .late }.count,
                cancelledCount: members.filter { $0.delay == .cancelled }.count)
        }
    }
}

// MARK: - Next stop and direction

public enum RadarRun {
    /// The first stop of the run that is planned after `now` (the stop the train is heading for).
    public static func nextStop(of vehicle: RadarVehicle, now: Date) -> Stopover? {
        vehicle.stopovers.first { stop in
            guard let planned = stop.departure?.planned ?? stop.arrival?.planned else { return false }
            return planned > now
        }
    }
}

public enum RadarBearing {
    /// Initial bearing from `from` to `to` in degrees, clockwise from north, in 0..<360. Used for the direction arrow.
    public static func degrees(from: GeoPoint, to: GeoPoint) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}

// MARK: - Summary and text helpers

public enum RadarSummary {
    /// "12 Züge im Ausschnitt, 3 verspätet" – the label of the train layer for VoiceOver and the status pill.
    /// `rail` picks "Züge" over "Fahrzeuge" when every visible vehicle is a train.
    public static func line(count: Int, late: Int, rail: Bool) -> String {
        let noun: String
        if rail {
            noun = count == 1 ? "Zug" : "Züge"
        } else {
            noun = count == 1 ? "Fahrzeug" : "Fahrzeuge"
        }
        var text = "\(count) \(noun) im Ausschnitt"
        if late > 0 { text += ", \(late) verspätet" }
        return text
    }
}

/// Text helpers shared by the radar pieces: folding for comparisons, words for the keyword heuristic.
public enum RadarText {
    /// Lower case, no diacritics ("Mödling" → "modling", "Wörgl" → "worgl").
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Folded words of a text, split at every character that is not a letter or digit.
    public static func words(_ text: String) -> [String] {
        fold(text).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
}
