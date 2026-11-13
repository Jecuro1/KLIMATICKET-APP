import SwiftUI
import KlimaCore

// MARK: radarcockpit – demo data and the CI screenshot host of the Cockpit-Ansicht (`-KBScreenshot <name> -KBDemo YES`, RootView › ScreenshotRouter).
// One invented train on the Westbahn between Wien and Salzburg with a polyline that bends between the stations, times relative to "now", no network and
// no real run. The delays shrink along the run, so the route ahead is orange first and green after.
//
//   radarCockpit        following: behind and above the train, the route ahead tinted by delay, the HUD
//   radarCockpitBird    from above, north up
//   radarCockpitFree    the camera is the user's, zoomed out over the whole route, "Zurück zum Zug" is there
//   radarCockpitAX5     following, at the largest text size: the HUD keeps the essentials
//   radarCockpitEnded   the train has reached its last stop: "Fahrt beendet"
//   radarCockpitLost    no position for two and a half minutes: "Keine Position mehr"

enum CockpitDemo {
    struct DemoStop {
        var name: String
        var lat: Double
        var lon: Double
        /// Planned arrival and departure in minutes from now.
        var arrival: Double?
        var departure: Double?
        /// Minutes late (reported).
        var delay: Int
        var platform: String
    }

    static let stops: [DemoStop] = [
        DemoStop(name: "Wien Hbf", lat: 48.185, lon: 16.375, arrival: nil, departure: -72, delay: 0, platform: "9"),
        DemoStop(name: "St. Pölten Hbf", lat: 48.200, lon: 15.620, arrival: -47, departure: -45, delay: 1, platform: "3"),
        DemoStop(name: "Amstetten", lat: 48.122, lon: 14.872, arrival: -19, departure: -17, delay: 7, platform: "2"),
        DemoStop(name: "Linz Hbf", lat: 48.290, lon: 14.291, arrival: 13, departure: 15, delay: 6, platform: "4"),
        DemoStop(name: "Attnang-Puchheim", lat: 48.002, lon: 13.736, arrival: 38, departure: 39, delay: 4, platform: "2"),
        DemoStop(name: "Salzburg Hbf", lat: 47.813, lon: 13.045, arrival: 72, departure: nil, delay: 2, platform: "7"),
    ]

    static let line = Line(name: "RJX 66", fullName: "RJX 66", category: "RJX", categoryShort: "RJX", categoryLong: "railjet xpress", trainNumber: "66",
                           operatorName: "ÖBB", productClass: 1, mode: .train)

    static let tripID = "demo|cockpit|RJX66"

    static func stopovers(now: Date) -> [Stopover] {
        stops.enumerated().map { index, stop in
            func event(_ minutes: Double?) -> StopEvent? {
                guard let minutes else { return nil }
                let planned = now.addingTimeInterval(minutes * 60)
                return StopEvent(planned: planned, realtime: planned.addingTimeInterval(Double(stop.delay) * 60),
                                 plannedPlatform: Platform(text: stop.platform, kind: .track), realtimePlatform: Platform(text: stop.platform, kind: .track),
                                 prognosis: .prognosed)
            }
            let location = Location(lid: "demo|cockpit|\(stop.name)", kind: .station, extId: "cockpit\(index)", name: stop.name,
                                    coordinate: GeoPoint(latitude: stop.lat, longitude: stop.lon))
            return Stopover(location: location, arrival: event(stop.arrival), departure: event(stop.departure), index: index)
        }
    }

    /// The track: the stations in a row with a gentle bend between each two, 4 km at most to the side, none at the stations themselves.
    static func polyline() -> [GeoPoint] {
        var points: [GeoPoint] = []
        for index in 0..<(stops.count - 1) {
            let a = stops[index], b = stops[index + 1]
            let dLat = b.lat - a.lat, dLon = b.lon - a.lon
            let length = (dLat * dLat + dLon * dLon).squareRoot()
            // The unit vector at right angles to the leg.
            let nLat = -dLon / length, nLon = dLat / length
            let steps = 90
            for step in 0..<steps {
                let t = Double(step) / Double(steps)
                let bend = 0.03 * sin(.pi * t) * (0.65 * sin(3 * .pi * t + Double(index)) + 0.35 * sin(7 * .pi * t))
                points.append(GeoPoint(latitude: a.lat + dLat * t + nLat * bend, longitude: a.lon + dLon * t + nLon * bend))
            }
        }
        if let last = stops.last { points.append(GeoPoint(latitude: last.lat, longitude: last.lon)) }
        return points
    }

    static func details(now: Date) -> TripDetails {
        TripDetails(tripID: tripID, line: line, direction: "Salzburg Hbf", stopovers: stopovers(now: now), polyline: polyline(),
                    realtimeUpdatedAt: now)
    }

    /// Where the train is at `time`: along the polyline between the stop it last left and the next one, by the real (delayed) times.
    static func position(at time: Date, now: Date) -> GeoPoint {
        guard let route = CockpitRoute(stopovers: stopovers(now: now), polyline: polyline()) else {
            return GeoPoint(latitude: stops[0].lat, longitude: stops[0].lon)
        }
        for index in 0..<(route.stops.count - 1) {
            let from = route.stops[index], to = route.stops[index + 1]
            guard let left = from.departure, let reached = to.arrival, time >= left, time < reached else { continue }
            let fraction = time.timeIntervalSince(left) / max(reached.timeIntervalSince(left), 1)
            return route.point(atKm: from.km + (to.km - from.km) * fraction)
        }
        return route.point(atKm: route.firstKm)
    }

    /// The radar's answer for the train: its position and the four stops the radar lists (origin, last left, next, destination).
    static func vehicle(at position: GeoPoint, now: Date) -> RadarVehicle {
        let all = stopovers(now: now)
        let four = [all[0], all[2], all[3], all[5]]
        return RadarVehicle(tripID: tripID, line: line, direction: "Salzburg Hbf", coordinate: position, stopovers: four)
    }

    static func launch(now: Date, scenario: CockpitLaunch.Scenario = .live, mode: CockpitCameraMode = .follow, camera: CockpitCamera? = nil) -> CockpitLaunch {
        let seen: Date
        let position: GeoPoint
        switch scenario {
        case .live:
            seen = now
            position = self.position(at: now, now: now)
        case .lost:
            seen = now.addingTimeInterval(-150)
            position = self.position(at: seen, now: now)
        case .ended:
            seen = now
            position = GeoPoint(latitude: stops[stops.count - 1].lat, longitude: stops[stops.count - 1].lon)
        }
        return CockpitLaunch(vehicle: vehicle(at: position, now: now), details: details(now: now), seenAt: seen, mode: mode, staticCamera: camera,
                             scenario: scenario)
    }
}

struct CockpitScreenshotHost: View {
    static let screens: Set<String> = ["radarCockpit", "radarCockpitBird", "radarCockpitFree", "radarCockpitAX5", "radarCockpitEnded", "radarCockpitLost"]

    let screen: String

    private var launch: CockpitLaunch {
        let now = Date()
        switch screen {
        case "radarCockpitBird":
            return CockpitDemo.launch(now: now, mode: .bird)
        case "radarCockpitFree":
            // The whole corridor from Wien to Salzburg in view.
            let overview = CockpitCamera(center: GeoPoint(latitude: 48.0, longitude: 14.7), distance: 560_000, heading: 0, pitch: 0)
            return CockpitDemo.launch(now: now, mode: .free, camera: overview)
        case "radarCockpitEnded":
            return CockpitDemo.launch(now: now, scenario: .ended)
        case "radarCockpitLost":
            return CockpitDemo.launch(now: now, scenario: .lost)
        default:
            return CockpitDemo.launch(now: now)
        }
    }

    var body: some View {
        CockpitView(launch: launch, services: .offline, onClose: {})
            .dynamicTypeSize(screen == "radarCockpitAX5" ? .accessibility5 : .large)
    }
}
