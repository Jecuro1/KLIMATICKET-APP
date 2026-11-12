import Foundation

/// A starting point for the assumptions mode: routes between bundled stations (stations.json), so the screen is useful
/// before the first trip – and before the first ticket.
public struct WhatIfPreset: Identifiable, Hashable, Sendable {
    public struct RouteSpec: Hashable, Sendable {
        public var fromStationID: String
        public var toStationID: String
        public var tripsPerMonth: Int
    }

    public var id: String
    public var title: String
    /// One line below the title ("Wiener Neustadt ⇄ Wien · 40 Fahrten im Monat").
    public var subtitle: String
    public var symbol: String
    public var routes: [RouteSpec]

    /// The input this preset fills in: its routes (new ids), in 2. Klasse.
    public func input(startDate: Date = Date(), variant: TicketVariant = .klassik) -> WhatIfInput {
        WhatIfInput(routes: routes.map {
            WhatIfRoute(fromStationID: $0.fromStationID, toStationID: $0.toStationID, tripsPerMonth: $0.tripsPerMonth)
        }, variant: variant, startDate: startDate)
    }

    // Stations of the bundled stations.json (a test checks that every id exists).
    static let wien = "at:49:1349"          // Wien Hauptbahnhof
    static let wienerNeustadt = "at:43:5210" // Wiener Neustadt Hauptbahnhof
    static let graz = "at:46:3040"          // Graz Hauptbahnhof
    static let salzburg = "at:45:50002"     // Salzburg Hauptbahnhof
    static let innsbruck = "at:47:1187"     // Innsbruck Hauptbahnhof

    /// Täglich pendeln · Wochenend-Heimfahrt · Gelegentlich.
    public static let all: [WhatIfPreset] = [
        WhatIfPreset(id: "commute", title: "Täglich pendeln", subtitle: "Wiener Neustadt ⇄ Wien · 40 Fahrten im Monat",
                     symbol: "briefcase.fill",
                     routes: [RouteSpec(fromStationID: wienerNeustadt, toStationID: wien, tripsPerMonth: 40)]),
        WhatIfPreset(id: "weekend", title: "Wochenend-Heimfahrt", subtitle: "Graz ⇄ Wien · 4 Fahrten im Monat",
                     symbol: "house.fill",
                     routes: [RouteSpec(fromStationID: graz, toStationID: wien, tripsPerMonth: 4)]),
        WhatIfPreset(id: "occasional", title: "Gelegentlich", subtitle: "Salzburg ⇄ Innsbruck · 2 Fahrten im Monat",
                     symbol: "mountain.2.fill",
                     routes: [RouteSpec(fromStationID: salzburg, toStationID: innsbruck, tripsPerMonth: 2)]),
    ]

    public static func preset(id: String) -> WhatIfPreset? { all.first { $0.id == id } }
}
