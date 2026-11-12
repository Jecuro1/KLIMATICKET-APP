import Foundation
import XCTest
@testable import KlimaCore

/// Fixtures of the „Was wäre wenn?“ tests: four stations, hand-priced relations and a small catalogue, so every
/// expected number can be computed by hand (see the comments next to the assertions).
enum WhatIfFixtures {
    static let cal = Calendar.vienna

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    // Tirol – Tirol (€ 23,50), Tirol – Salzburg (€ 35,00), Wien – Salzburg (€ 67,70), Wien – Wiener Neustadt (€ 11,40).
    static let innsbruck = Station(id: "at:47:1187", name: "Innsbruck Hauptbahnhof", lat: 47.26353, lon: 11.40028, state: "T")
    static let stAnton = Station(id: "at:47:1222", name: "St. Anton am Arlberg", lat: 47.12665, lon: 10.26774, state: "T")
    static let salzburg = Station(id: "at:45:50002", name: "Salzburg Hauptbahnhof", lat: 47.81306, lon: 13.04513, state: "S")
    static let wien = Station(id: "at:49:1349", name: "Wien Hauptbahnhof", lat: 48.18519, lon: 16.37641, state: "W")
    static let neustadt = Station(id: "at:43:5210", name: "Wiener Neustadt Hauptbahnhof", lat: 47.81131, lon: 16.23362, state: "NÖ")
    static let stations = [innsbruck, stAnton, salzburg, wien, neustadt]

    static func table() -> RelationPriceTable {
        let ids = stations.map(\.id)
        let points = ids.enumerated().map { "{\"name\":\"\($0.offset)\",\"stationID\":\"\($0.element)\"}" }.joined(separator: ",")
        // indices: 0 Innsbruck · 1 St. Anton · 2 Salzburg · 3 Wien · 4 Wiener Neustadt
        let prices = [[0, 1, 2350], [0, 2, 3500], [2, 3, 6770], [3, 4, 1140]]
        let json = "{\"validFrom\":\"2025-12-14\",\"source\":\"test\",\"points\":[\(points)],\"prices\":\(prices)}"
        return try! RelationPriceTable(jsonData: Data(json.utf8))
    }

    static func product(_ id: String, _ family: TicketFamily, _ states: [String] = [], _ variant: TicketVariant = .klassik,
                        price: Double, from: String = "2026-01-01", history: [TicketProduct.PricePoint]? = nil,
                        local: Bool? = nil, name: String? = nil) -> TicketProduct {
        TicketProduct(id: id, family: family, states: states, name: name ?? id, variant: variant, priceEUR: price,
                      validFrom: from, priceHistory: history, isLocal: local)
    }

    static func catalog(fareIndex: [TariffCatalog.FareIndexPoint]? = nil, extra: [TicketProduct] = []) -> TariffCatalog {
        let products: [TicketProduct] = [
            product("oe-klassik", .oe, price: 1400, history: [.init(validFrom: "2025-01-01", priceEUR: 1179.3),
                                                               .init(validFrom: "2025-08-01", priceEUR: 1300)],
                    name: "KlimaTicket Ö Klassik"),
            product("oe-jugend", .oe, [], .jugend, price: 1050, name: "KlimaTicket Ö Jugend"),
            product("oe-senior", .oe, [], .senior, price: 1000, name: "KlimaTicket Ö Senior"),
            // 590 until 31.3.2026, 600 from 1.4.2026.
            product("tirol-klassik", .regional, ["T"], price: 600, from: "2026-04-01",
                    history: [.init(validFrom: "2025-04-01", priceEUR: 590)], name: "KlimaTicket Tirol"),
            product("tirol-jugend", .regional, ["T"], .jugend, price: 319, from: "2026-04-01", name: "KlimaTicket Tirol Jugend"),
            product("tirol-innsbruck", .regional, ["T"], price: 475.2, from: "2026-04-01", local: true, name: "KlimaTicket Innsbruck"),
            product("wien-klassik", .regional, ["W"], price: 467, name: "Jahreskarte WIEN"),
        ] + extra
        return TariffCatalog(version: 1, updatedAt: "2026-10-09", products: products, fareModel: .fallback, cityFares: [],
                             kilometergeldEUR: 0.5, carFullCostPerKmEUR: 0.47, emissions: .fallback, fareIndex: fareIndex)
    }

    static func calculator(_ catalog: TariffCatalog = catalog()) -> WhatIfCalculator {
        WhatIfCalculator(catalog: catalog, relations: table(), stations: StationIndex(stations: stations))
    }

    /// St. Anton → Innsbruck, `trips` per month.
    static func tirol(_ trips: Int, travelClass: TravelClass = .second) -> WhatIfRoute {
        WhatIfRoute(fromStationID: stAnton.id, toStationID: innsbruck.id, tripsPerMonth: trips, travelClass: travelClass)
    }

    /// Wien → Salzburg, `trips` per month.
    static func westbahn(_ trips: Int) -> WhatIfRoute {
        WhatIfRoute(fromStationID: wien.id, toStationID: salzburg.id, tripsPerMonth: trips)
    }

    /// Start on 1 March 2026 (Ö Klassik € 1.400, Tirol still € 590), no fare index.
    static func input(_ routes: [WhatIfRoute], variant: TicketVariant = .klassik, start: Date? = nil) -> WhatIfInput {
        WhatIfInput(routes: routes, variant: variant, startDate: start ?? date(2026, 3, 1))
    }

    static func option(_ result: WhatIfResult, _ id: String, file: StaticString = #filePath, line: UInt = #line) -> WhatIfOption {
        guard let option = result.options.first(where: { $0.id == id }) else {
            XCTFail("no option \(id) in \(result.options.map(\.id))", file: file, line: line)
            return result.single
        }
        return option
    }
}
