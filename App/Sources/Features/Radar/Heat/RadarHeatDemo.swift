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

    /// 0 ... 1, the same for the same trip id (FNV-1a), so the scene looks the same at every launch.
    private static func unit(_ text: String) -> Double {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
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
        if roll < 0.80 { return (Int(spread * 170), false) }                  // 0 to 2:50: on time
        if roll < 0.885 { return (180 + Int(spread * 110), false) }          // 3 to 4:50: still on time
        if roll < 0.935 { return (300 + Int(spread * 420), false) }          // 5 to 12 minutes
        if roll < 0.955 { return (900 + Int(spread * 600), false) }          // 15 to 25 minutes
        if roll < 0.99 { return (nil, false) }                                // no realtime data
        return (nil, true)                                                    // cancelled
    }

    static func vehicles(now: Date) -> [RadarVehicle] {
        DenseDemo.vehicles(now: now).enumerated().compactMap { index, vehicle -> RadarVehicle? in
            guard index % 8 < 5 else { return nil }   // about 62 % of 1 500 = 940
            let (delay, cancelled) = fate(of: vehicle)
            var stopovers = vehicle.stopovers
            if let first = stopovers.first, let planned = first.arrival?.planned {
                var arrival = first.arrival
                arrival?.realtime = delay.map { planned.addingTimeInterval(TimeInterval($0)) }
                stopovers[0] = Stopover(location: first.location, arrival: arrival, departure: first.departure, index: first.index)
            }
            return RadarVehicle(tripID: "demo|heat|\(index)", line: vehicle.line, direction: vehicle.direction, coordinate: vehicle.coordinate,
                                stopovers: stopovers, isCancelled: cancelled)
        }
    }
}
