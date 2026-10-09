import XCTest
@testable import KlimaCore

/// Pure pricing helpers: VerbundArea, TariffPeriods, ShopDeepLink, PriceCache, PriceRequest (SPEC §B3.6, §B3.7, §B4.1,
/// §B4.3, §B6; §D2 WP-B 4 and 7).
final class PricingPureTests: XCTestCase {
    typealias F = PricingFixtures

    // MARK: VerbundArea (§B4.1 table)

    func testVerbundAreaTable() {
        let expected: [String: String?] = [
            "at:41:123": "VOR", "at:42:3642": "VKG", "at:43:4848": "VOR", "at:44:41164": "OÖVV", "at:45:50002": "SVV",
            "at:46:3040": "STV", "at:47:1187": "VVT", "at:48:452": "VVV", "at:49:1349": "VOR", "wl:60201349": "VOR",
            "uic:8100227": nil, "osm:hub:wien-mitte": nil, "de:09162:6": nil, "at:40:1": nil, "": nil,
        ]
        for (id, verbund) in expected { XCTAssertEqual(VerbundArea.hint(stationID: id), verbund, id) }
        XCTAssertNil(VerbundArea.hint(stationID: nil))
        // VAO lids: embedded IFOPT id or the IFOPT-derived stop number; EVA lids give nil.
        XCTAssertEqual(VerbundArea.hint(vaoLid: "A=1@O=Eferding Bahnhof@X=14015999@Y=48303500@U=81@L=444250500@p=1791493163@i=A×at:44:42505@"), "OÖVV")
        XCTAssertEqual(VerbundArea.hint(vaoLid: "A=1@L=470118700@"), "VVT")
        XCTAssertNil(VerbundArea.hint(vaoLid: "A=1@L=8100227@"))
        XCTAssertEqual(VerbundArea.hint(PriceEndpoint(stationID: "uic:8100227", name: "Eferding"), vaoLid: "A=1@L=444250500@"), "OÖVV")
        XCTAssertTrue(VerbundArea.same("VVT", "VVT"))
        XCTAssertFalse(VerbundArea.same("VOR", "SVV"))
        XCTAssertFalse(VerbundArea.same(nil, nil), "unknown is never the same Verbund")
    }

    // MARK: TariffPeriods (§B4.3)

    func testTariffPeriods() {
        let p = TariffPeriods(estimator: F.estimator)
        XCTAssertEqual(p.boundaries, ["2025-12-14", "2026-12-13"])
        XCTAssertTrue(p.same(F.vienna("2026-10-08T08:00:00"), F.vienna("2026-10-09T12:15:00")))
        XCTAssertFalse(p.same(F.vienna("2026-12-12T08:00:00"), F.vienna("2026-12-13T08:00:00")))
        XCTAssertFalse(p.same(F.vienna("2025-12-13T08:00:00"), F.vienna("2026-01-10T08:00:00")))
        XCTAssertTrue(p.same(day: "2026-12-13", day: "2027-03-01"))
        XCTAssertTrue(p.same(day: "2025-12-14", day: "2026-12-12"), "a boundary day belongs to its own period")
        XCTAssertTrue(p.same(day: "2026-10-09", day: "2026-10-09"))
        // Order-independent; Vienna days (23:30 local on the 12th is still the 12th).
        XCTAssertFalse(p.same(F.vienna("2026-12-13T00:10:00"), F.vienna("2026-12-12T23:30:00")))
        XCTAssertEqual(TariffPeriods(boundaries: ["2026-12-13", "x", "2026-12-13"]).boundaries, ["2026-12-13"])
    }

    // MARK: ShopDeepLink (§B3.7, §D2 WP-B 7)

    func testShopDeepLink() throws {
        let url = ShopDeepLink.url(from: 1290401, to: 8100002, date: F.vienna("2026-10-10T08:28:00"))
        let s = url.absoluteString
        XCTAssertTrue(s.hasPrefix("https://shop.oebbtickets.at/de/ticket?"), s)
        for part in ["cref=klimabilanz", "stationOrigEva=001290401", "stationDestEva=008100002", "outwardDateTime=2026-10-10T08%3A28"] {
            XCTAssertTrue(s.contains(part), "\(part) in \(s)")
        }
        XCTAssertFalse(s.contains("outwardArrival"))
        XCTAssertTrue(ShopDeepLink.url(from: 1290401, to: 8100002, date: F.now, arrival: true).absoluteString.hasSuffix("&outwardArrival=true"))
        XCTAssertEqual(ShopDeepLink.url(from: "1290401", to: "8100002", date: F.vienna("2026-10-10T08:28:00")), url)
        XCTAssertNil(ShopDeepLink.url(from: "Wien", to: "8100002", date: F.now))
        // Winter time is Vienna wall clock too.
        XCTAssertTrue(ShopDeepLink.url(from: 1, to: 2, date: ISO.date("2026-12-15T13:00:00Z")!).absoluteString.contains("outwardDateTime=2026-12-15T14%3A00"))
    }

    // MARK: PriceCache (§B6)

    func testCacheKeys() {
        let r = PriceRequest(from: F.epWien, to: F.epSalzburg, departure: F.vienna("2026-10-10T23:30:00"), travelClass: .first, discount: .vorteilscard)
        XCTAssertEqual(PriceCache.relationKey(r), "rel|at:49:1349|at:45:50002|2026-10-10|first|vorteilscard")
        XCTAssertEqual(PriceCache.negativeKey(.vaoTariff, r), "neg|vaoTariff|at:49:1349|at:45:50002|2026-10-10|first")
        XCTAssertEqual(PriceCache.connectionKey(F.rjx19962, travelClass: .second, discount: .none), "con|\(F.rjx19962.id)|second|none")
        // Review 2026-10-09: the class separates negative results; via stops separate connection quotes; a planner
        // connection has its own negative key.
        XCTAssertNotEqual(PriceCache.negativeKey(.oebbShop, r), PriceCache.negativeKey(.oebbShop, { var x = r; x.travelClass = .second; return x }()))
        XCTAssertEqual(PriceCache.connectionKey(F.rjx19962, travelClass: .second, discount: .none, via: [F.epGraz]),
                       "con|\(F.rjx19962.id)|second|none|via:at:46:3040")
        XCTAssertEqual(PriceCache.negativeConnectionKey(F.rjx19962, travelClass: .first), "neg|oebbShop|con|\(F.rjx19962.id)|first")
        XCTAssertEqual(PriceCache.endpointKey(PriceEndpoint(name: "Wien Hbf (U)", hafasExtId: "1290401")), "eva:1290401")
        XCTAssertEqual(PriceCache.endpointKey(PriceEndpoint(name: "Innsbruck Hauptbahnhof")), "name:innsbruck hbf")
        var via = r
        via.via = [F.epGraz]
        XCTAssertEqual(PriceCache.relationKey(via), "rel|at:49:1349|at:45:50002|2026-10-10|first|vorteilscard|via:at:46:3040")
    }

    func quote(_ amount: Double, _ source: PriceSource = .liveOebb) -> PriceQuote {
        PriceQuote(amountEUR: amount, source: source, provider: "ÖBB", travelDate: F.now, fetchedAt: F.now, explanation: "x")
    }

    func testCacheTTLNegativeLRUAndInvalidation() {
        var c = PriceCache(fileURL: nil)
        let t0 = F.now
        c.insert(quote(1), for: "a", now: t0)
        XCTAssertEqual(c.quote(for: "a", now: t0.addingTimeInterval(23 * 3600))?.amountEUR, 1)
        XCTAssertNil(c.quote(for: "a", now: t0.addingTimeInterval(24 * 3600 + 1)), "24 h TTL")
        c.insertNegative("NA", for: "n", ttl: PriceCache.notAvailableTTL, now: t0)
        c.insertNegative("offerError", for: "s", ttl: PriceCache.noPriceTTL, now: t0)
        XCTAssertEqual(c.negative(for: "n", now: t0.addingTimeInterval(3601)), "NA")
        XCTAssertNil(c.negative(for: "s", now: t0.addingTimeInterval(3601)), "noPrice negatives live 1 h")
        XCTAssertNil(c.quote(for: "n", now: t0), "a negative entry is not a quote")

        var lru = PriceCache(fileURL: nil)
        for i in 0..<PriceCache.capacity { lru.insert(quote(Double(i)), for: "k\(i)", now: t0.addingTimeInterval(Double(i))) }
        _ = lru.quote(for: "k0", now: t0.addingTimeInterval(1000)) // touch the oldest
        lru.insert(quote(999), for: "new", now: t0.addingTimeInterval(1001))
        XCTAssertEqual(lru.count, PriceCache.capacity)
        XCTAssertNotNil(lru.quote(for: "k0", now: t0.addingTimeInterval(1002)), "recently used survives")
        XCTAssertNil(lru.quote(for: "k1", now: t0.addingTimeInterval(1002)), "least recently used is evicted")

        var inv = PriceCache(fileURL: nil)
        inv.insert(quote(1, .table), for: "t", now: t0)
        inv.insert(quote(2, .liveOebb), for: "l", now: t0)
        inv.removeAll { $0.source == .table }
        XCTAssertNil(inv.quote(for: "t", now: t0))
        XCTAssertNotNil(inv.quote(for: "l", now: t0))
    }

    func testCacheFileRoundTripAndWriteBehind() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kb-price-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Live/prices.json")
        var c = PriceCache(fileURL: url)
        XCTAssertFalse(c.shouldWrite(now: F.now))
        c.insert(quote(67.7), for: "rel|x", now: F.now)
        XCTAssertTrue(c.shouldWrite(now: F.now))
        XCTAssertTrue(c.write(now: F.now))
        c.insert(quote(1), for: "rel|y", now: F.now.addingTimeInterval(1))
        XCTAssertFalse(c.shouldWrite(now: F.now.addingTimeInterval(1)), "≤ 1 write per 5 s")
        XCTAssertEqual(c.writeDelay(now: F.now.addingTimeInterval(1)), 4, accuracy: 0.001)
        XCTAssertTrue(c.shouldWrite(now: F.now.addingTimeInterval(5)))
        var back = PriceCache(fileURL: url)
        XCTAssertEqual(back.quote(for: "rel|x", now: F.now)?.amountEUR, 67.7)
        XCTAssertNil(back.quote(for: "rel|y", now: F.now), "not written yet")
    }

    // MARK: PriceRequest

    func testPriceRequestFromJourney() {
        let r = PriceRequest(journey: F.rjx19962, travelClass: .second, discount: .none, stations: F.index)
        XCTAssertEqual(r.from.stationID, "at:49:1349", "„Wien Hbf (Bahnsteige 3-12)“ → app station within 300 m")
        XCTAssertEqual(r.from.hafasExtId, "8103000")
        XCTAssertEqual(r.to.stationID, "at:45:50002")
        XCTAssertEqual(r.departure, F.vienna("2026-10-10T08:28:00"))
        XCTAssertEqual(r.mode, .train)
        XCTAssertEqual(r.journey, F.rjx19962)
        XCTAssertTrue(r.via.isEmpty)
        let feldkirch = Location.station(extId: "8100197", name: "Feldkirch Bahnhof")
        let v = PriceRequest(journey: F.rjx19962, travelClass: .second, discount: .none, stations: F.index,
                             via: [ViaStop(location: feldkirch, minimumDwellMinutes: 10)])
        XCTAssertEqual(v.via.map(\.hafasExtId), ["8100197"])
    }

    func testPriceRequestDecodesWithoutVia() throws {
        let r = PriceRequest(from: F.epWien, to: F.epSalzburg, departure: F.now, via: [F.epGraz])
        let data = try JSONEncoder().encode(r)
        XCTAssertEqual(try JSONDecoder().decode(PriceRequest.self, from: data), r)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "via")
        let old = try JSONDecoder().decode(PriceRequest.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(old.via, [])
        XCTAssertEqual(old.from, F.epWien)
    }

    func testAlternativeText() {
        XCTAssertEqual(PriceAlternative(source: .liveOebb, amountEUR: 66.4, label: "Vorverkauf heute").text, "Vorverkauf heute € 66,40")
        XCTAssertEqual(PriceAlternative(source: .liveOebb, amountEUR: 91.5, label: "ÖBB-Ticketshop (andere Route)").text,
                       "ÖBB-Ticketshop € 91,50 (andere Route)")
        XCTAssertEqual(PriceAlternative(source: .table, amountEUR: 67.7, label: "Tarif-Tabelle").text, "Tarif-Tabelle € 67,70")
    }
}
