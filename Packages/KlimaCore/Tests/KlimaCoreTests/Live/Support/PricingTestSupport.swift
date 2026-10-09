// WP-B test helpers (SPEC §D2 WP-B): stations, offline tariff, fixture routes and a wired LivePriceService.
import Foundation
import XCTest
@testable import KlimaCore

enum PricingFixtures {
    /// 2026-10-09T12:15 Europe/Vienna (SPEC §D2 WP-B 5).
    static let now = ISO.date("2026-10-09T12:15:00+02:00")!

    /// "2026-10-10T08:28:00" as Europe/Vienna wall clock.
    static func vienna(_ s: String) -> Date { ShopTime.date(s)! }

    // MARK: Stations (stations.json ids and coordinates)

    static let wienHbf = Station(id: "at:49:1349", name: "Wien Hauptbahnhof", lat: 48.18519, lon: 16.37641, state: "W", aliases: ["Wien Hbf"])
    static let wienWest = Station(id: "at:49:1468", name: "Wien Westbahnhof", lat: 48.19666, lon: 16.33765, state: "W")
    static let salzburg = Station(id: "at:45:50002", name: "Salzburg Hauptbahnhof", lat: 47.81306, lon: 13.04513, state: "S", aliases: ["Salzburg Hbf"])
    static let innsbruck = Station(id: "at:47:1187", name: "Innsbruck Hauptbahnhof", lat: 47.26353, lon: 11.40028, state: "T", aliases: ["Innsbruck Hbf"])
    static let hall = Station(id: "at:47:1184", name: "Hall in Tirol", lat: 47.27727, lon: 11.50165, state: "T")
    static let rum = Station(id: "at:47:1186", name: "Rum", lat: 47.27791, lon: 11.45668, state: "T", aliases: ["Rum Bahnhof"])
    static let landeck = Station(id: "at:47:1212", name: "Landeck-Zams", lat: 47.14842, lon: 10.57828, state: "T", aliases: ["Landeck-Zams Bahnhof"])
    static let graz = Station(id: "at:46:3040", name: "Graz Hauptbahnhof", lat: 47.07248, lon: 15.41751, state: "ST", aliases: ["Graz Hbf"])
    static let stPoelten = Station(id: "at:43:4848", name: "St. Pölten Hauptbahnhof", lat: 48.20819, lon: 15.62404, state: "NÖ")
    static let feldkirch = Station(id: "at:48:817", name: "Feldkirch", lat: 47.2416, lon: 9.60493, state: "V", aliases: ["Feldkirch Bahnhof"])
    static let bregenz = Station(id: "at:48:452", name: "Bregenz", lat: 47.50237, lon: 9.73977, state: "V", aliases: ["Bregenz Bahnhof"])
    static let wrNeustadt = Station(id: "at:43:5210", name: "Wiener Neustadt Hauptbahnhof", lat: 47.81131, lon: 16.23362, state: "NÖ", aliases: ["Wiener Neustadt Hbf"])
    static let karlsplatz = Station(id: "wl:60200657", name: "Wien Karlsplatz", lat: 48.20096, lon: 16.36895, state: "W", kind: .metro)

    static let index = StationIndex(stations: [wienHbf, wienWest, salzburg, innsbruck, hall, rum, landeck, graz, stPoelten, wrNeustadt, feldkirch, bregenz, karlsplatz])

    // MARK: Offline tariff

    /// Official table excerpt (2nd class, day of travel, from 14.12.2025); Wien Westbahnhof is missing (as in the real table).
    static let relations = RelationPriceTable(file: .init(
        validFrom: "2025-12-14", source: "test",
        points: [.init(name: "Wien", stationID: wienHbf.id), .init(name: "Salzburg", stationID: salzburg.id),
                 .init(name: "Graz", stationID: graz.id), .init(name: "Innsbruck", stationID: innsbruck.id),
                 .init(name: "Landeck-Zams", stationID: landeck.id)],
        prices: [[0, 1, 6770], [2, 0, 4430], [3, 4, 1760]]))

    static func catalog(cityFares: [CityFare] = []) -> TariffCatalog {
        TariffCatalog(version: 1, updatedAt: "2026-10-01", products: [], fareModel: .fallback, cityFares: cityFares,
                      kilometergeldEUR: 0.5, carFullCostPerKmEUR: 0.47, emissions: .fallback,
                      fareIndex: [.init(validFrom: "2026-12-13", factor: 1.035)])
    }

    static let estimator = FareEstimator(catalog: catalog(), relations: relations)

    // MARK: Endpoints (SPEC §D2 WP-B 5: endpoints carry hafasExtId, so no LocMatch is needed)

    static func endpoint(_ s: Station, eva: String?) -> PriceEndpoint {
        PriceEndpoint(stationID: s.id, name: s.name, coordinate: s.location, hafasExtId: eva)
    }

    static let epWien = endpoint(wienHbf, eva: "1290401")
    static let epSalzburg = endpoint(salzburg, eva: "8100002")
    static let epInnsbruck = endpoint(innsbruck, eva: "8100108")
    static let epHall = endpoint(hall, eva: "8100105")
    static let epLandeck = endpoint(landeck, eva: "8100063")
    static let epGraz = endpoint(graz, eva: "8100173")
    static let epStPoelten = endpoint(stPoelten, eva: "8100008")
    static let epFeldkirch = endpoint(feldkirch, eva: "8100197")
    static let epBregenz = endpoint(bregenz, eva: "8100090")
    static let epRum = endpoint(rum, eva: "8100106")

    // MARK: Routes

    static let tokenSuffix = "/api/domain/v1/anonymousToken"
    static let initSuffix = "/api/domain/v1/initUserData"
    static let timetableSuffix = "/api/hafas/v4/timetable"
    static let offersSuffix = "/api/offer/v6/offers"
    static let vaoSuffix = "anachb.vor.at/hamm/gate"
    static let hafasSuffix = "fahrplan.oebb.at/gate"
    /// The redacted token value of the token fixture (sent back as `AccessToken`).
    static let token = "<redacted 967 chars>"

    static func shop(_ name: String) throws -> HTTPResponse { try Fixture.shopResponse("shop/\(name)") }
    static func vao(_ name: String) throws -> HTTPResponse { try Fixture.shopResponse("vao/\(name)") }

    /// Token + initUserData routes (the session).
    static func sessionRoutes() throws -> [FixtureTransport.Route] {
        [.init(method: "GET", urlSuffix: tokenSuffix, response: try shop("shop_wien-salzburg_2026-10-10_01_anonymousToken")),
         .init(urlSuffix: initSuffix, response: try shop("shop_wien-salzburg_2026-10-10_02_initUserData"))]
    }

    /// Session + timetable + offers.
    static func shopRoutes(timetable: HTTPResponse, offers: HTTPResponse) throws -> [FixtureTransport.Route] {
        try sessionRoutes() + [.init(urlSuffix: timetableSuffix, response: timetable), .init(urlSuffix: offersSuffix, response: offers)]
    }

    /// JSON number as Double (JSONSerialization gives Int for integral values on Linux).
    static func number(_ v: Any?) -> Double? {
        switch v {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let n as NSNumber: return n.doubleValue
        default: return nil
        }
    }

    static func json(_ object: Any, status: Int = 200) throws -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": "application/json"], body: try JSONSerialization.data(withJSONObject: object))
    }

    /// The `response` of a shop fixture as a mutable JSON object.
    static func shopObject(_ name: String) throws -> [String: Any] {
        let obj = try XCTUnwrap(try Fixture.json("shop/\(name)") as? [String: Any])
        return try XCTUnwrap(obj["response"] as? [String: Any])
    }

    /// The same-day Wien–Salzburg offers with the 2nd-class Standard-Ticket at `price` (synthetic detour case).
    static func offers(sameDayWithSecondClassPrice price: Double) throws -> HTTPResponse {
        var root = try shopObject("shop_wien-salzburg_sameday_2026-10-09_07_offers_v6_adult")
        var sections = try XCTUnwrap(root["offerSections"] as? [[String: Any]])
        for s in sections.indices {
            var classes = sections[s]["travelClasses"] as? [[String: Any]] ?? []
            for c in classes.indices where classes[c]["class"] as? String == "2" {
                var offers = classes[c]["offers"] as? [[String: Any]] ?? []
                for o in offers.indices {
                    offers[o]["price"] = price
                    var products = offers[o]["products"] as? [[String: Any]] ?? []
                    for p in products.indices { products[p]["price"] = price }
                    offers[o]["products"] = products
                }
                classes[c]["offers"] = offers
            }
            sections[s]["travelClasses"] = classes
        }
        root["offerSections"] = sections
        return try json(root)
    }

    /// A minimal synthetic offers response: one FLEX ONEWAY offer per class.
    static func offers(owner: String = "ÖBB", product: String = "Standard-Ticket", second: Double, first: Double? = nil) throws -> HTTPResponse {
        func offer(_ cls: String, _ price: Double) -> [String: Any] {
            ["class": cls, "offers": [["flexibility": ["de": "FLEX"], "price": price,
                                       "products": [["name": ["de": product], "price": price, "class": cls, "trafficType": "ONEWAY",
                                                     "owners": [["nameShort": owner, "description": owner]], "relevantReductions": []]]]]]
        }
        var classes = [offer("2", second)]
        if let first { classes.append(offer("1", first)) }
        return try json(["offerError": false, "offerSections": [["travelClasses": classes]]])
    }

    /// A synthetic timetable with one connection per tuple (id, from esn, departure, to esn, arrival, train numbers, ms).
    static func timetable(_ connections: [(id: String, from: Int, dep: String, to: Int, arr: String, trains: [String], ms: Int)]) throws -> HTTPResponse {
        let list: [[String: Any]] = connections.map { c in
            ["id": c.id,
             "from": ["name": "A", "esn": c.from, "departure": c.dep],
             "to": ["name": "B", "esn": c.to, "arrival": c.arr],
             "sections": c.trains.map { ["category": ["name": "RJ", "number": $0], "type": "journey"] },
             "switches": max(0, c.trains.count - 1), "duration": c.ms]
        }
        return try json(["connections": list])
    }

    // MARK: Journeys

    static func location(_ extId: String, _ name: String, _ lat: Double, _ lon: Double) -> Location {
        Location(lid: "A=1@L=\(extId)@", kind: .station, extId: extId, name: name, coordinate: GeoPoint(latitude: lat, longitude: lon), products: .rail)
    }

    static func ride(_ id: String, _ a: Location, _ dep: String, _ b: Location, _ arr: String, category: String, number: String) -> Leg {
        Leg(id: id, kind: .ride, origin: a, destination: b, departure: StopEvent(planned: vienna(dep)), arrival: StopEvent(planned: vienna(arr)),
            line: Line(name: "\(category) \(number)", category: category, trainNumber: number, productClass: category == "WB" ? 4096 : 1, mode: .train))
    }

    /// Wien Hbf 8103000 dep 2026-10-10T08:28 → Salzburg Hbf 10:53, RJX 19962 (SPEC §D2 WP-B 5 `.connection` case).
    static let rjx19962 = Journey(legs: [ride("C-0-0", location("8103000", "Wien Hbf (Bahnsteige 3-12)", 48.18518, 16.37641), "2026-10-10T08:28:00",
                                              location("8100002", "Salzburg Hbf", 47.81306, 13.04559), "2026-10-10T10:53:00",
                                              category: "RJX", number: "19962")],
                                  durationSeconds: 8700, changes: 0)

    /// WESTbahn Wien Westbahnhof → Salzburg Hbf, today 14:08 (not sold by the ÖBB shop).
    static let westbahn = Journey(legs: [ride("C-1-0", location("8101001", "Wien Westbahnhof", 48.19666, 16.33765), "2026-10-09T14:08:00",
                                               location("8100002", "Salzburg Hbf", 47.81306, 13.04559), "2026-10-09T16:36:00",
                                               category: "WB", number: "917")],
                                  durationSeconds: 8880, changes: 0)
}

/// Every piece wired over one `FixtureTransport` and one fake clock (no real sleeping).
struct PricingRig {
    let transport: FixtureTransport
    let clock: FakeClock
    let health: LiveHealth
    let throttle: RequestThrottle
    let shop: OebbShopClient
    let verbund: VerbundTariffClient
    let service: LivePriceService

    init(routes: [FixtureTransport.Route], config: LiveConfig = .default, now: Date = PricingFixtures.now,
         estimator: FareEstimator = PricingFixtures.estimator, cacheURL: URL? = nil, linker: StationLinker? = nil,
         wrap: ((HTTPTransport, FakeClock) -> HTTPTransport)? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let clock = FakeClock(now)
        let transport = FixtureTransport(routes: routes, file: file, line: line)
        let wire: HTTPTransport = wrap?(transport, clock) ?? transport
        let health = LiveHealth(clock: clock.closure)
        let throttle = RequestThrottle(clock: clock.closure, sleeper: clock.sleeper)
        let shop = OebbShopClient(config: config, transport: wire, throttle: throttle, health: health, clock: clock.closure,
                                  appVersion: "1.0.0", sleeper: clock.sleeper)
        let verbund = VerbundTariffClient(config: config, transport: wire, throttle: throttle, health: health, appVersion: "1.0.0",
                                          sleeper: clock.sleeper)
        self.transport = transport
        self.clock = clock
        self.health = health
        self.throttle = throttle
        self.shop = shop
        self.verbund = verbund
        self.service = LivePriceService(config: config, shop: shop, verbund: verbund, linker: linker, estimator: estimator,
                                        stations: PricingFixtures.index, cacheURL: cacheURL, clock: clock.closure)
    }

    /// Recorded request paths ("/api/domain/v1/anonymousToken", "anachb.vor.at/hamm/gate" …).
    var paths: [String] {
        transport.recorded.map { r in r.url.host == "anachb.vor.at" || r.url.host == "fahrplan.oebb.at" ? "\(r.url.host!)\(r.url.path)" : r.url.path }
    }

    func count(_ suffix: String) -> Int { transport.recorded.filter { $0.url.absoluteString.contains(suffix) }.count }
}

/// Advances the fake clock by `delay` seconds whenever a request matches `suffix` (simulated slow transport).
final class DelayingTransport: HTTPTransport, @unchecked Sendable {
    let base: HTTPTransport
    let clock: FakeClock
    let delay: TimeInterval
    let suffix: String

    init(_ base: HTTPTransport, clock: FakeClock, delay: TimeInterval, suffix: String) {
        self.base = base
        self.clock = clock
        self.delay = delay
        self.suffix = suffix
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let response = try await base.send(request)
        if request.url.absoluteString.contains(suffix) { clock.advance(delay) }
        return response
    }
}

/// Counts calls; answers with a fixed quote or throws.
final class StubPriceProvider: LivePriceProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [PriceRequest] = []
    let result: Result<PriceQuote, LiveError>

    init(_ result: Result<PriceQuote, LiveError>) { self.result = result }

    var calls: [PriceRequest] {
        lock.lock(); defer { lock.unlock() }
        return _calls
    }

    func livePrice(_ request: PriceRequest) async throws -> PriceQuote {
        record(request)
        return try result.get()
    }

    private func record(_ request: PriceRequest) {
        lock.lock()
        _calls.append(request)
        lock.unlock()
    }
}
