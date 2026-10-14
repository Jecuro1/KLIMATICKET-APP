import Foundation
import KlimaCore

/// Demo content for the widget placeholders and the in-app preview routes (no network, no user data). Times are built from
/// `now`, so the previews always show departures ahead of the moment they are rendered.
enum WidSamples {
    static func connections(now: Date) -> [WidgetConnection] {
        let first = now.addingTimeInterval(8 * 60)
        return [
            WidgetConnection(id: "s1", planned: first, realtime: first.addingTimeInterval(4 * 60), arrival: first.addingTimeInterval(88 * 60),
                             changes: 0, durationMinutes: 88, fromName: "St. Anton am Arlberg", toName: "Innsbruck Hbf",
                             lineName: "RJX 19960", modeSymbol: TransportMode.train.symbolName, direction: "Wien Hbf",
                             platform: "Gl. 3", platformChanged: true, trainAttributes: ["wifi", "fork.knife", "toilet"]),
            WidgetConnection(id: "s2", planned: first.addingTimeInterval(34 * 60), arrival: first.addingTimeInterval(124 * 60),
                             changes: 1, durationMinutes: 124, fromName: "St. Anton am Arlberg", toName: "Innsbruck Hbf",
                             lineName: "RJ 1063", modeSymbol: TransportMode.train.symbolName, platform: "Gl. 2"),
            WidgetConnection(id: "s3", planned: first.addingTimeInterval(64 * 60), realtime: nil, arrival: first.addingTimeInterval(150 * 60),
                             changes: 1, durationMinutes: 150, fromName: "St. Anton am Arlberg", toName: "Innsbruck Hbf",
                             lineName: "REX 2", modeSymbol: TransportMode.train.symbolName, isCancelled: false,
                             trainAttributes: ["bicycle"]),
        ]
    }

    static func departures(now: Date) -> [WidgetDeparture] {
        let start = max(now, now.addingTimeInterval(3 * 60))
        return [
            WidgetDeparture(id: "d1", planned: start.addingTimeInterval(4 * 60), realtime: start.addingTimeInterval(7 * 60),
                            lineName: "S 4", modeSymbol: TransportMode.sBahn.symbolName, direction: "Floridsdorf",
                            platform: "Gl. 1", platformChanged: false),
            WidgetDeparture(id: "d2", planned: start.addingTimeInterval(11 * 60), lineName: "R 51", modeSymbol: TransportMode.train.symbolName,
                            direction: "Bludenz", platform: "Gl. 4", platformChanged: true),
            WidgetDeparture(id: "d3", planned: start.addingTimeInterval(19 * 60), lineName: "Bus 750", modeSymbol: TransportMode.bus.symbolName,
                            direction: "Langen am Arlberg", platform: "Steig 2", isCancelled: true),
            WidgetDeparture(id: "d4", planned: start.addingTimeInterval(26 * 60), lineName: "RJX 662", modeSymbol: TransportMode.train.symbolName,
                            direction: "Wien Hbf", platform: "Gl. 3"),
            WidgetDeparture(id: "d5", planned: start.addingTimeInterval(41 * 60), lineName: "S 4", modeSymbol: TransportMode.sBahn.symbolName,
                            direction: "Mistelbach", platform: "Gl. 1"),
        ]
    }

    /// Trips per day for the twelve-week grid: a rhythm of commuter days with a few quiet ones.
    static func heatmapCounts() -> [Int] {
        (0..<WidgetHeatmap.cellCount).map { index in
            let weekday = index % 7
            if weekday >= 5 { return index % 3 == 0 ? 1 : 0 }
            return (index * 7 + 3) % 4 == 0 ? 0 : 1 + (index * 5) % 3
        }
    }

    static let stations: [WidgetStation] = [
        WidgetStation(id: "sample-home", name: "Innsbruck Hbf", isHome: true, facilities: [.bikeRide, .barrierFree]),
        WidgetStation(id: "sample-2", name: "St. Anton am Arlberg", facilities: [.parkRide]),
    ]

    static let disruptions: [WidgetDisruption] = [
        WidgetDisruption(id: "sample-h1", title: "Bauarbeiten", summary: "Die S 4 fährt zwischen Floridsdorf und Stammersdorf mit Schienenersatzverkehr.",
                         lines: ["S 4"], validFrom: nil, validUntil: nil),
    ]
}
