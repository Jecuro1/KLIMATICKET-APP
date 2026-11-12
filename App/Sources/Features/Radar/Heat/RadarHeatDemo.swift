import SwiftUI
import KlimaCore

// MARK: radarheat – demo trains for the CI scenes of the Pünktlichkeit layer (`-KBDemo`, no network). The positions are those of the
// dense radar demo (about 1 500 invented vehicles along invented corridors, `ScottyDemoDense.swift`), thinned to about 900 like the real
// number of rail vehicles in Austria (docs/OEBB_LIVE.md §R11), with delays made up for the scene: a delay cluster over Tirol (10 to
// 35 minutes between Landeck and Kufstein) and a quiet rest of the country (almost everything on time, a few scattered delays, a
// few trains without realtime data, a cancelled one). Nothing here is a real train, delay or position.

extension DemoRadarService {
    func heatVehicles(for query: RadarQuery, at time: Date) -> [RadarVehicle] {
        let inside = HeatDemo.vehicles(now: time).filter { vehicle in
            guard let line = vehicle.line else { return false }
            return !line.product.intersection(query.products).isEmpty && query.box.contains(vehicle.coordinate)
        }
        return Array(inside.prefix(max(query.maxVehicles, 0)))
    }
}

enum HeatDemo {
    /// The delay cluster: Tirol from the Arlberg to Kufstein, north of the Brenner.
    static let cluster = RadarBox(north: 47.75, west: 10.10, south: 46.95, east: 12.30)

    /// 0 ... 1, the same for the same text (FNV-1a, then a full avalanche: trip ids differ in their last digits only, and without the
    /// final mixing neighbours in the list would share their roll, a whole decade of trains cancelled at once).
    private static func unit(_ text: String) -> Double {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
        hash ^= hash >> 33
        hash = hash &* 0xFF51_AFD7_ED55_8CCD
        hash ^= hash >> 33
        hash = hash &* 0xC4CE_B9FE_1A85_EC53
        hash ^= hash >> 33
        return Double(hash >> 11) / Double(1 << 53)
    }

    /// (delay in seconds, nil = no realtime data, cancelled)
    private static func fate(of vehicle: RadarVehicle) -> (delay: Int?, cancelled: Bool) {
        let roll = unit(vehicle.tripID)
        let spread = unit(vehicle.tripID + "|delay")
        if cluster.contains(vehicle.coordinate) {
            if roll < 0.06 { return (nil, false) }
            if roll < 0.18 { return (240 + Int(spread * 360), false) }       // 4 to 10 minutes
            return (660 + Int(spread * 1_500), false)                         // 11 to 36 minutes
        }
        if roll < 0.84 { return (Int(spread * 170), false) }                  // 0 to 2:50: on time
        if roll < 0.915 { return (180 + Int(spread * 110), false) }          // 3 to 4:50: still on time
        if roll < 0.955 { return (300 + Int(spread * 420), false) }          // 5 to 12 minutes
        if roll < 0.97 { return (900 + Int(spread * 600), false) }           // 15 to 25 minutes
        if roll < 0.99 { return (nil, false) }                                // no realtime data
        return (nil, true)                                                    // cancelled
    }

    /// The Inntal as a line of places, for the extra trains of the cluster (the dense demo has few trains in Tirol).
    private static let inntal: [(name: String, lat: Double, lon: Double)] = [
        ("Kufstein", 47.583, 12.168), ("Wörgl Hbf", 47.492, 12.077), ("Jenbach", 47.390, 11.760), ("Hall in Tirol", 47.281, 11.505),
        ("Innsbruck Hbf", 47.263, 11.401), ("Telfs-Pfaffenhofen", 47.306, 11.072), ("Imst-Pitztal", 47.240, 10.745),
        ("Landeck-Zams", 47.139, 10.567),
    ]

    /// 46 invented trains along the Inntal, one about every 4 km: three or more share a cell of the grid, so the delay cluster shows.
    private static func inntalVehicles(now: Date) -> [RadarVehicle] {
        let lengths = zip(inntal, inntal.dropFirst()).map { a, b -> Double in
            let dLat = (b.lat - a.lat) * 111.2, dLon = (b.lon - a.lon) * 74.8
            return (dLat * dLat + dLon * dLon).squareRoot()
        }
        let total = lengths.reduce(0, +)
        let lines: [(String, String, Int, TransportMode, String)] = [
            ("RJX", "66", 1, .train, "RJX 66"), ("REX", "5", 16, .train, "REX 5"), ("S", "1", 32, .sBahn, "S 1"), ("R", "33", 16, .train, "R 33"),
        ]
        return (0..<46).map { index in
            // A little off the even spacing, deterministic.
            var remaining = (Double(index) + 0.5 + (unit("inntal|\(index)") - 0.5) * 0.6) / 46 * total
            var leg = 0
            while leg < lengths.count - 1, remaining > lengths[leg] { remaining -= lengths[leg]; leg += 1 }
            let t = min(max(remaining / max(lengths[leg], 0.1), 0), 1)
            let a = inntal[leg], b = inntal[leg + 1]
            let towardsEnd = index % 2 == 0
            let next = towardsEnd ? b : a
            let pick = lines[index % lines.count]
            let line = Line(name: pick.4, fullName: pick.4, category: pick.0, categoryShort: pick.0, lineNumber: pick.1, operatorName: "Demo",
                            productClass: pick.2, mode: pick.3)
            let planned = now.addingTimeInterval(Double(300 + (index % 7) * 60))
            let stop = Stopover(location: Location(lid: "demo|heat|\(next.name)", kind: .station, extId: nil, name: next.name,
                                                    coordinate: GeoPoint(latitude: next.lat, longitude: next.lon)),
                                arrival: StopEvent(planned: planned, realtime: planned), departure: nil, index: 0)
            return RadarVehicle(tripID: "demo|heat|inntal|\(index)", line: line, direction: next.name,
                                coordinate: GeoPoint(latitude: a.lat + (b.lat - a.lat) * t, longitude: a.lon + (b.lon - a.lon) * t),
                                stopovers: [stop])
        }
    }

    static func vehicles(now: Date) -> [RadarVehicle] {
        let thinned = DenseDemo.vehicles(now: now).enumerated().compactMap { index, vehicle -> RadarVehicle? in
            guard index % 8 < 5 else { return nil }   // about 62 % of 1 500 = 940
            return RadarVehicle(tripID: "demo|heat|\(index)", line: vehicle.line, direction: vehicle.direction, coordinate: vehicle.coordinate,
                                stopovers: vehicle.stopovers)
        }
        return (thinned + inntalVehicles(now: now)).map(withFate)
    }

    private static func withFate(_ vehicle: RadarVehicle) -> RadarVehicle {
        let (delay, cancelled) = fate(of: vehicle)
        var stopovers = vehicle.stopovers
        if let first = stopovers.first, let planned = first.arrival?.planned {
            var arrival = first.arrival
            arrival?.realtime = delay.map { planned.addingTimeInterval(TimeInterval($0)) }
            stopovers[0] = Stopover(location: first.location, arrival: arrival, departure: first.departure, index: first.index)
        }
        return RadarVehicle(tripID: vehicle.tripID, line: vehicle.line, direction: vehicle.direction, coordinate: vehicle.coordinate,
                            stopovers: stopovers, isCancelled: cancelled)
    }
}
