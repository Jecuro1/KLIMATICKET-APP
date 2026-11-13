import Foundation

// MARK: radarmodes – synthetic city fleets for -KBDemo, the CI scenes and the scheduler tests of Bus, Bim and U-Bahn (docs/RADAR_MODES.md §10). Generated from the clock:
// no network, no real vehicle, no real timetable. Invented runs on invented straight-line routes around the real centres of Wien, Graz, Linz and
// Innsbruck, with plausible line names, four stops per run (as the real answer carries), some delays, some runs without realtime, three operator
// names. The service answers like the real one: only the asked products, only inside the box, at most `maxVehicles` (so splits, caps and the
// 16-tile limit really happen).

public enum RadarCityDemoFleet {
    struct City {
        var centre: GeoPoint
        var radiusKm: Double
        var buses: [String]
        var trams: [String]
        var subways: [String]
        var perBus: Int
        var perTram: Int
        var perSubway: Int
        var stops: [String]
    }

    public static let stephansplatz = GeoPoint(latitude: 48.2085, longitude: 16.3725)

    static let wien = City(
        centre: stephansplatz, radiusKm: 9,
        buses: ["2A", "3A", "4A", "5A", "7A", "10A", "11A", "12A", "13A", "14A", "15A", "17A", "26A", "28A", "29A", "31A", "35A", "37A", "38A",
                "39A", "40A", "48A", "51A", "56A", "57A", "59A", "62A", "63A", "66A", "69A"],
        trams: ["1", "2", "5", "6", "9", "10", "11", "18", "25", "26", "31", "33", "37", "38", "40", "41", "43", "44", "46", "49", "52", "60",
                "62", "67", "71", "D", "O"],
        subways: ["U1", "U2", "U3", "U4", "U6"],
        perBus: 20, perTram: 11, perSubway: 8,
        stops: ["Hütteldorf", "Ottakring", "Hernals", "Döbling", "Heiligenstadt", "Floridsdorf", "Kagran", "Stadlau", "Aspern", "Seestadt",
                "Simmering", "Oberlaa", "Favoriten", "Reumannplatz", "Liesing", "Siebenhirten", "Meidling", "Hietzing", "Penzing", "Grinzing",
                "Praterstern", "Schwedenplatz", "Karlsplatz", "Westbahnhof", "Schottentor", "Volkstheater", "Rathaus", "Erdberg", "Landstraße",
                "Margareten", "Neubau", "Brigittenau", "Leopoldau", "Spittelau", "Alser Straße", "Gumpendorf"])

    static let graz = City(centre: GeoPoint(latitude: 47.0707, longitude: 15.4395), radiusKm: 5,
                           buses: ["31", "34", "39", "40", "41", "58", "63", "64"], trams: ["1", "3", "4", "5", "6", "7"], subways: [],
                           perBus: 6, perTram: 5, perSubway: 0,
                           stops: ["Jakominiplatz", "Hauptbahnhof", "Andritz", "Mariatrost", "Puntigam", "Wetzelsdorf", "St. Peter", "Krenngasse",
                                   "Eggenberg", "Liebenau"])
    static let linz = City(centre: GeoPoint(latitude: 48.3059, longitude: 14.2862), radiusKm: 5,
                           buses: ["12", "17", "19", "25", "26", "27", "33", "45"], trams: ["1", "2", "3", "4"], subways: [],
                           perBus: 6, perTram: 5, perSubway: 0,
                           stops: ["Hauptplatz", "Hauptbahnhof", "Urfahr", "Auwiesen", "solarCity", "Leonding", "Dornach", "Pichling", "Ebelsberg"])
    static let innsbruck = City(centre: GeoPoint(latitude: 47.2654, longitude: 11.3928), radiusKm: 4,
                                buses: ["A", "C", "F", "J", "M", "O", "R", "W"], trams: ["1", "2", "3", "5"], subways: [],
                                perBus: 5, perTram: 4, perSubway: 0,
                                stops: ["Marktplatz", "Hauptbahnhof", "Hungerburg", "Igls", "Technik", "Allerheiligen", "Olympisches Dorf", "Mühlau"])

    static let operators = ["Stadtverkehr", "Regionalbus", "ÖBB"]

    // MARK: Fleet

    /// Every synthetic city vehicle at `now`; `crowded` adds the knots of the crowded scene around Stephansplatz.
    public static func vehicles(now: Date, crowded: Bool = false) -> [RadarVehicle] {
        var all: [RadarVehicle] = []
        for (index, city) in [wien, graz, linz, innsbruck].enumerated() {
            all += fleet(city, cityIndex: index, now: now)
        }
        all += wienTrains(now: now)
        if crowded { all += knots(now: now) }
        return all
    }

    /// The vehicles a JourneyGeoPos request would get: only the asked classes, only inside the box, the first `maxVehicles`.
    public static func answer(_ query: RadarQuery, crowded: Bool = false, extra: [RadarVehicle] = []) -> RadarSnapshot {
        let t = query.when
        let matching = (vehicles(now: t, crowded: crowded) + extra).filter { vehicle in
            guard let line = vehicle.line, line.productClass & query.products.rawValue != 0 else { return false }
            return query.box.contains(vehicle.coordinate)
        }
        let answered = Array(matching.prefix(max(query.maxVehicles, 0)))
        return RadarSnapshot(vehicles: answered, realtimeUpdatedAt: t, answeredCount: answered.count)
    }

    private static func fleet(_ city: City, cityIndex: Int, now: Date) -> [RadarVehicle] {
        var result: [RadarVehicle] = []
        let groups: [(names: [String], per: Int, cls: Int)] = [(city.buses, city.perBus, 64), (city.trams, city.perTram, 512),
                                                                (city.subways, city.perSubway, 256)]
        for (groupIndex, group) in groups.enumerated() {
            for (lineIndex, name) in group.names.enumerated() {
                let seed = cityIndex * 10_000 + groupIndex * 1000 + lineIndex
                let route = self.route(city, seed: seed, subway: group.cls == 256)
                for k in 0..<group.per {
                    if let vehicle = runVehicle(city: city, line: line(name, cls: group.cls, seed: seed), route: route,
                                                tripID: "demo|city|\(cityIndex)|\(name)|\(group.cls)|\(k)", phase: Double(k) / Double(group.per),
                                                seed: seed * 31 + k, now: now) {
                        result.append(vehicle)
                    }
                }
            }
        }
        return result
    }

    /// Two ends of a line and a bend near the centre, in km east/north of the centre.
    private static func route(_ city: City, seed: Int, subway: Bool) -> [(x: Double, y: Double)] {
        let angle = unit(seed, 1) * 2 * .pi
        let bend = subway ? 0.4 : 1.6
        let reach = city.radiusKm * (subway ? 0.75 : 0.55 + 0.45 * unit(seed, 2))
        let a = (x: cos(angle) * reach, y: sin(angle) * reach)
        let opposite = angle + .pi + (unit(seed, 3) - 0.5) * 1.4
        let reachB = city.radiusKm * (0.5 + 0.5 * unit(seed, 4))
        let b = (x: cos(opposite) * reachB, y: sin(opposite) * reachB)
        let middle = (x: (unit(seed, 5) - 0.5) * 2 * bend, y: (unit(seed, 6) - 0.5) * 2 * bend)
        return [a, middle, b]
    }

    /// A vehicle running back and forth on its route: where it is at `now`, the four stops of the answer (start, last left, next, destination)
    /// and its delay.
    private static func runVehicle(city: City, line: Line, route: [(x: Double, y: Double)], tripID: String, phase: Double, seed: Int,
                                   now: Date) -> RadarVehicle? {
        let lengths = zip(route, route.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        let total = lengths.reduce(0, +)
        guard total > 0 else { return nil }
        let roundTrip = total / 0.33 * 60 * 2   // about 20 km/h, there and back, in seconds
        let f = (phase + now.timeIntervalSince1970 / roundTrip).truncatingRemainder(dividingBy: 1)
        let outbound = f < 0.5
        let u = outbound ? f * 2 : (1 - f) * 2
        func point(at u: Double) -> (x: Double, y: Double) {
            var left = u * total
            for (i, length) in lengths.enumerated() {
                if left <= length || i == lengths.count - 1 {
                    let t = length > 0 ? min(left / length, 1) : 0
                    return (route[i].x + (route[i + 1].x - route[i].x) * t, route[i].y + (route[i + 1].y - route[i].y) * t)
                }
                left -= length
            }
            return route[route.count - 1]
        }
        func geo(_ p: (x: Double, y: Double)) -> GeoPoint {
            GeoPoint(latitude: city.centre.latitude + p.y / 111.2,
                     longitude: city.centre.longitude + p.x / (111.2 * cos(city.centre.latitude * .pi / 180)))
        }
        let stopsOnRoute = 12
        let gap = roundTrip / 2 / Double(stopsOnRoute - 1)
        let along = u * Double(stopsOnRoute - 1)
        let lastIndex = min(Int(along), stopsOnRoute - 2)
        let travelled = along - Double(lastIndex)
        // Direction of travel: outbound from stop 0 to the last stop, back the other way.
        let lastLeft = outbound ? lastIndex : stopsOnRoute - 1 - lastIndex
        let nextStop = outbound ? lastIndex + 1 : stopsOnRoute - 2 - lastIndex
        let first = outbound ? 0 : stopsOnRoute - 1
        let last = outbound ? stopsOnRoute - 1 : 0
        func stopName(_ i: Int) -> String {
            if i == 0 { return city.stops[seed / 31 % city.stops.count] }
            if i == stopsOnRoute - 1 { return city.stops[(seed / 31 + 7) % city.stops.count] }
            return city.stops[(seed / 31 * 3 + i * 5) % city.stops.count]
        }
        func stopPoint(_ i: Int) -> GeoPoint { geo(point(at: Double(i) / Double(stopsOnRoute - 1))) }
        // Delay: most runs on time or a little late, some five minutes and more, a few without realtime, one in fifty cancelled.
        let roll = unit(seed, 9)
        let realtime = roll > 0.08
        let cancelled = roll < 0.02
        let delay = roll > 0.78 ? 300 + Int(unit(seed, 10) * 600) : Int(unit(seed, 11) * 200)
        let elapsedToLast = travelled * gap
        func event(_ minutesFromNow: TimeInterval) -> StopEvent {
            let planned = now.addingTimeInterval(minutesFromNow)
            return StopEvent(planned: planned, realtime: realtime ? planned.addingTimeInterval(TimeInterval(delay)) : nil,
                             prognosis: realtime ? .prognosed : nil)
        }
        let startOffset = -(Double(lastIndex) * gap + elapsedToLast)
        let lastOffset = -elapsedToLast
        let nextOffset = gap - elapsedToLast
        let endOffset = Double(stopsOnRoute - 1 - lastIndex) * gap - elapsedToLast
        func location(_ i: Int) -> Location {
            Location(lid: "demo|city|\(stopName(i))", kind: .station, extId: nil, name: stopName(i), coordinate: stopPoint(i))
        }
        let stops = [
            Stopover(location: location(first), departure: event(startOffset), index: 0),
            Stopover(location: location(lastLeft), arrival: event(lastOffset - 20), departure: event(lastOffset), index: 1),
            Stopover(location: location(nextStop), arrival: event(nextOffset), departure: event(nextOffset + 20), index: 2),
            Stopover(location: location(last), arrival: event(endOffset), index: 3),
        ]
        return RadarVehicle(tripID: tripID, line: line, direction: stopName(last), coordinate: geo(point(at: u)), stopovers: stops,
                            isCancelled: cancelled)
    }

    public static func line(_ name: String, cls: Int, seed: Int) -> Line {
        let op = cls == 64 && seed % 5 == 4 ? operators[1] : operators[0]
        switch cls {
        case 512:
            return Line(name: "Tram \(name)", fullName: "Tram \(name)", category: "Tram", categoryShort: "str", lineNumber: name,
                        operatorName: op, productClass: 512, mode: .tram)
        case 256:
            return Line(name: name, fullName: name, category: "U", categoryShort: "U", lineNumber: name, operatorName: op, productClass: 256,
                        mode: .metro)
        default:
            return Line(name: "Bus \(name)", fullName: "Bus \(name)", category: "Bus", categoryShort: "bus", lineNumber: name, operatorName: op,
                        productClass: 64, mode: .bus)
        }
    }

    // MARK: Trains of the Wien view

    /// S-Bahnen, regional and long-distance trains on lines through Wien, so the city view shows all five modes.
    private static func wienTrains(now: Date) -> [RadarVehicle] {
        let lines: [(Line, Int)] = [
            (train(cls: 32, "S 1", number: "1"), 3), (train(cls: 32, "S 2", number: "2"), 3), (train(cls: 32, "S 3", number: "3"), 3),
            (train(cls: 32, "S 7", number: "7"), 2), (train(cls: 32, "S 50", number: "50"), 2), (train(cls: 32, "S 60", number: "60"), 2),
            (train(cls: 32, "S 80", number: "80"), 2), (train(cls: 16, "REX 1", number: "1"), 2), (train(cls: 16, "REX 3", number: "3"), 2),
            (train(cls: 1, "RJX 562", number: "562"), 1), (train(cls: 1, "RJ 74", number: "74"), 1),
        ]
        var city = wien
        city.radiusKm = 14
        var result: [RadarVehicle] = []
        for (index, (line, count)) in lines.enumerated() {
            let seed = 90_000 + index
            let route = self.route(city, seed: seed, subway: true)
            for k in 0..<count {
                if let vehicle = runVehicle(city: city, line: line, route: route, tripID: "demo|city|train|\(line.name)|\(k)",
                                            phase: Double(k) / Double(count) + 0.13, seed: seed * 31 + k, now: now) {
                    result.append(vehicle)
                }
            }
        }
        // Short runs in and out of Wien Hbf, so a close view of the centre always has trains and S-Bahnen.
        var hbf = wien
        hbf.centre = GeoPoint(latitude: 48.1855, longitude: 16.3765)
        hbf.radiusKm = 2.5
        let approach: [(Line, Int)] = [(train(cls: 16, "REX 2", number: "2"), 2), (train(cls: 16, "R 12", number: "12"), 2),
                                       (train(cls: 1, "RJ 541", number: "541"), 1), (train(cls: 32, "S 45", number: "45"), 2),
                                       (train(cls: 32, "S 4", number: "4"), 2)]
        for (index, (line, count)) in approach.enumerated() {
            let seed = 95_000 + index
            let route = self.route(hbf, seed: seed, subway: true)
            for k in 0..<count {
                if let vehicle = runVehicle(city: hbf, line: line, route: route, tripID: "demo|city|hbf|\(line.name)|\(k)",
                                            phase: Double(k) / Double(count) + 0.31, seed: seed * 31 + k, now: now) {
                    result.append(vehicle)
                }
            }
        }
        return result
    }

    /// A train line of the Wien view (S-Bahn, regional, long distance), shaped like the answer's lines.
    static func train(cls: Int, _ name: String, number: String) -> Line {
        let category = String(name.split(separator: " ").first ?? "")
        switch cls {
        case 32:
            return Line(name: name, fullName: name, category: "S", categoryShort: "s", categoryLong: "S-Bahn", lineNumber: number,
                        operatorName: "ÖBB", productClass: 32, mode: .sBahn)
        case 16:
            return Line(name: name, fullName: name, category: category, categoryShort: category, categoryLong: "Regional-Express", lineNumber: number,
                        operatorName: "ÖBB", productClass: 16, mode: .train)
        default:
            return Line(name: name, fullName: name, category: category, categoryShort: category, categoryLong: "railjet", trainNumber: number,
                        operatorName: "ÖBB", productClass: 1, mode: .train)
        }
    }

    // MARK: The crowded scene

    /// The level-8 city tile with Stephansplatz (about 1.2 × 1.1 km).
    public static var knotTile: RadarTileKey? {
        let p = stephansplatz
        return RadarTileGrid.tiles(intersecting: RadarBox(north: p.latitude + 1e-5, west: p.longitude - 1e-5, south: p.latitude - 1e-5,
                                                          east: p.longitude + 1e-5), level: 8, lane: .city).first
    }

    /// 1200 vehicles inside the Stephansplatz tile (more than one answer carries: it is still cut off at level 8) and three more knots of 1100
    /// in other parts of the view, whose splits together need more than 16 city tiles. Fixed places, a little jitter with the clock.
    private static func knots(now: Date) -> [RadarVehicle] {
        guard let tile = knotTile else { return [] }
        let centreBox = RadarTileGrid.box(of: tile)
        // Inside a Wien view of 0.12° around Stephansplatz, each in another tile of level 5.
        let others = [GeoPoint(latitude: 48.240, longitude: 16.335), GeoPoint(latitude: 48.175, longitude: 16.405),
                      GeoPoint(latitude: 48.250, longitude: 16.410)]
        var boxes = [(centreBox, 1200)]
        for point in others {
            boxes.append((RadarBox(north: point.latitude + 0.012, west: point.longitude - 0.016, south: point.latitude - 0.012,
                                   east: point.longitude + 0.016), 1100))
        }
        var result: [RadarVehicle] = []
        let wobble = now.timeIntervalSince1970 / 40
        for (b, (box, count)) in boxes.enumerated() {
            for k in 0..<count {
                let seed = 500_000 + b * 10_000 + k
                let lat = box.south + (box.north - box.south) * (0.04 + 0.92 * unit(seed, 1)) + sin(wobble + Double(k)) * 0.00004
                let lon = box.west + (box.east - box.west) * (0.04 + 0.92 * unit(seed, 2)) + cos(wobble + Double(k)) * 0.00005
                let isTram = k % 3 == 0
                let names = isTram ? wien.trams : wien.buses
                let name = names[k % names.count]
                let line = self.line(name, cls: isTram ? 512 : 64, seed: seed)
                let here = GeoPoint(latitude: lat, longitude: lon)
                let stop = Location(lid: "demo|city|knot", kind: .station, extId: nil, name: wien.stops[k % wien.stops.count], coordinate: here)
                let planned = now.addingTimeInterval(120)
                let late = unit(seed, 3) > 0.7
                let next = Stopover(location: stop, arrival: StopEvent(planned: planned, realtime: planned.addingTimeInterval(late ? 420 : 60),
                                                                        prognosis: .prognosed), index: 0)
                result.append(RadarVehicle(tripID: "demo|city|knot|\(b)|\(k)", line: line, direction: stop.name, coordinate: here,
                                           stopovers: [next]))
            }
        }
        return result
    }

    // MARK: Determinism

    /// A fixed pseudo-random number in 0..<1 from two integers (the same on every run).
    static func unit(_ seed: Int, _ salt: Int) -> Double {
        var z = UInt64(bitPattern: Int64(seed &* 7919 &+ salt &* 104_729)) &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
