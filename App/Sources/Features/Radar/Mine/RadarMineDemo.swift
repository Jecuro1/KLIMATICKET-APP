import Foundation
import KlimaCore

// MARK: radar2-radarmine – synthetic data of „Meine Fahrzeuge“ for -KBDemo and the CI scenes (docs/RADAR_MINE.md §10). Nothing here is real: four
// remembered lines of the demo fleets (Bus 13A, S 45, Tram D of radarmodes' city fleets, RJX 66 of the corridor demo), an invented stop
// „Neubaugasse (Demo)“ with a board of eight departures relative to now (positions invented around the stop, two without one, one cancelled, one whose
// trip id is a vehicle the demo radar holds, so its marker gets the number) and a fixed invented place for „In der Nähe“. No network, no location,
// nothing written to `RadarMine/mine.json` (screenshot launches keep the file in memory).

/// The CI scenes; the raw value is the screen name of `ScreenshotRouter`.
enum RadarMineScene: String, CaseIterable, Sendable {
    case lines = "radarMineLines"
    case highlight = "radarMineHighlight"
    case near = "radarMineNear"
    case nearIntro = "radarMineNearIntro"
    case denied = "radarMineDenied"
    case stop = "radarMineStop"
    case picker = "radarMinePicker"
    case empty = "radarMineEmpty"
    case tripSheet = "radarMineTripSheet"
    case ax5 = "radarMineAX5"
    case linesAX5 = "radarMineLinesAX5"

    /// The page the panel opens with; nil: closed.
    var page: RadarMineText.Page? {
        switch self {
        case .lines, .empty, .linesAX5: .lines
        case .near, .nearIntro, .denied: .near
        case .stop, .picker, .ax5: .stop
        case .highlight, .tripSheet: nil
        }
    }

    /// Where the camera goes (centre, latitude span).
    var camera: (GeoPoint, Double)? {
        switch self {
        case .stop, .ax5, .picker: (GeoPoint(latitude: 48.1985, longitude: 16.3530), 0.034)
        case .near, .nearIntro, .denied: (RadarMineDemo.place, 0.03)
        case .lines, .linesAX5, .highlight, .empty: (GeoPoint(latitude: 48.1990, longitude: 16.3620), 0.045)
        case .tripSheet: nil
        }
    }
}

enum RadarMineDemo {
    /// The scene of this screenshot launch (set by `RadarMineScreenshotHost` before the radar is built).
    @MainActor static var scene: RadarMineScene?

    /// The invented place of „In der Nähe“ in demo and screenshot launches (Wien Neubau), never the device's.
    static let place = GeoPoint(latitude: 48.2015, longitude: 16.3480)

    /// The invented stop of „Wo bleibt mein Bus?“.
    static let stop = Station(id: "demo:neubaugasse", name: "Neubaugasse (Demo)", lat: 48.1990, lon: 16.3525, state: "W", kind: .stop,
                              products: 64 | 512 | 256)

    /// Bus 13A, S 45 and Tram D (remembered in Wien) and RJX 66 (remembered at St. Pölten, outside the Wien view).
    static var lines: RadarMineLines {
        let wien = RadarLineKey.area(of: GeoPoint(latitude: 48.2, longitude: 16.37))
        return RadarMineLines([
            RadarLineKey(mode: .bus, compact: "BUS13A", title: "Bus 13A", area: wien),
            RadarLineKey(mode: .suburban, compact: "S45", title: "S 45", area: wien),
            RadarLineKey(mode: .tram, compact: "TRAMD", title: "Tram D", area: wien),
            RadarLineKey(mode: .rail, compact: "RJX66", title: "RJX 66", area: RadarLineKey.area(of: GeoPoint(latitude: 48.2, longitude: 15.62))),
        ])
    }

    /// The model as the scene starts.
    @MainActor static func prepare(_ mine: RadarMineModel, scene: RadarMineScene) {
        var file = RadarMineFile()
        if scene != .empty { file.lines = lines }
        file.highlight = scene == .highlight || scene == .lines || scene == .linesAX5
        file.stops = [RadarMineStop(id: stop.id, name: stop.name, coordinate: stop.location)]
        mine.adoptDemo(file)
        guard let page = scene.page else { return }
        mine.open(page: page)
        switch scene {
        case .near: mine.setSyntheticFix(place)
        case .denied: mine.simulateDenied()
        case .stop, .ax5: mine.choose(stop)
        default: break
        }
    }

    // MARK: The board

    /// Eight departures from `station` relative to `now` (minute-aligned, so a refresh within the minute shows the same board). The first is a
    /// vehicle the demo radar holds (same trip id, its position), when one of the city fleets' buses is near; the others are invented.
    static func board(for station: Station, now: Date) -> Board {
        let base = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.down) * 60)
        let here = station.location
        let location = Location(lid: "demo|stop|\(station.id)", kind: .station, name: station.name, coordinate: here)
        func at(_ km: Double, bearing: Double) -> GeoPoint {
            let rad = bearing * .pi / 180
            return GeoPoint(latitude: here.latitude + km * cos(rad) / 111.2,
                            longitude: here.longitude + km * sin(rad) / (111.2 * cos(here.latitude * .pi / 180)))
        }
        func entry(_ id: String, _ line: Line, to direction: String, in minutes: Double, delay: Int?, platform: Platform?,
                   cancelled: Bool = false, position: GeoPoint?) -> BoardEntry {
            let planned = base.addingTimeInterval(minutes * 60)
            let event = StopEvent(planned: planned, realtime: delay.map { planned.addingTimeInterval(Double($0) * 60) }, plannedPlatform: platform,
                                  isCancelled: cancelled, prognosis: delay == nil ? nil : .prognosed)
            return BoardEntry(tripID: id, line: line, direction: direction, stop: location, event: event, currentPosition: position)
        }
        let bus = { (name: String) in RadarCityDemoFleet.line(name, cls: 64, seed: 1) }
        let tram = { (name: String) in RadarCityDemoFleet.line(name, cls: 512, seed: 1) }
        let subway = RadarCityDemoFleet.line("U3", cls: 256, seed: 1)
        let stand = { (text: String) in Platform(text: text, kind: .stand) }
        // A bus the demo radar holds: the nearest city bus within 2.5 km, with its own trip id and position.
        let held = RadarCityDemoFleet.vehicles(now: now)
            .filter { $0.line?.productClass == 64 && !$0.isCancelled && $0.coordinate.distanceKm(to: here) < 2.5 }
            .min { $0.coordinate.distanceKm(to: here) < $1.coordinate.distanceKm(to: here) }
        var entries: [BoardEntry] = []
        if let held, let line = held.line {
            entries.append(entry(held.tripID, line, to: held.direction ?? "Hauptbahnhof", in: 2, delay: 1, platform: stand("2"), position: held.coordinate))
        } else {
            entries.append(entry("demo|board|1", bus("13A"), to: "Hauptbahnhof", in: 2, delay: 1, platform: stand("2"), position: at(0.6, bearing: 20)))
        }
        entries += [
            entry("demo|board|2", tram("49"), to: "Hütteldorf", in: 4, delay: 0, platform: stand("1"), position: at(1.1, bearing: 95)),
            entry("demo|board|3", subway, to: "Simmering", in: 5, delay: 0, platform: Platform(text: "2", kind: .track), position: at(1.6, bearing: 300)),
            entry("demo|board|4", bus("48A"), to: "Dr.-Karl-Renner-Ring", in: 7, delay: nil, platform: stand("3"), position: nil),
            entry("demo|board|5", bus("13A"), to: "Alser Straße", in: 9, delay: 3, platform: stand("1"), position: at(2.3, bearing: 165)),
            entry("demo|board|6", tram("49"), to: "Dr.-Karl-Renner-Ring", in: 11, delay: 0, platform: stand("2"), cancelled: true, position: nil),
            entry("demo|board|7", bus("2A"), to: "Graben, Petersplatz", in: 14, delay: 1, platform: stand("4"), position: at(3.4, bearing: 230)),
            entry("demo|board|8", subway, to: "Ottakring", in: 16, delay: nil, platform: Platform(text: "1", kind: .track), position: nil),
        ]
        return Board(kind: .departures, entries: entries, realtimeUpdatedAt: now)
    }
}
