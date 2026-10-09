import XCTest
@testable import KlimaCore

/// Owner request 2026-10-09 („man sollte auch VIA Halte rein machen“): via stops with a minimum stay.
/// Fixture `tripsearch_via_feldkirch_dwell_ibk_bregenz` = ONE live request (Innsbruck Hbf → Bregenz via Feldkirch,
/// `min: 10`), trimmed. Without the stay every RJX runs through to Bregenz; with it HAFAS breaks the trip at Feldkirch.
final class HafasViaTests: XCTestCase {
    static let scenario = "tripsearch_via_feldkirch_dwell_ibk_bregenz"
    static let feldkirch = Location.station(extId: "8100197", name: "Feldkirch Bahnhof")

    func testRequestShapeMatchesTheLiveVerifiedRequest() throws {
        let fixture = try HafasEncoderTests.fixtureRequest(Self.scenario)
        let req = try XCTUnwrap(fixture["req"] as? [String: Any])
        let date = try XCTUnwrap(HafasTime.date(base: req["outDate"] as! String, time: req["outTime"] as! String, tzOffsetMinutes: nil))
        let q = JourneyQuery(origin: .station(extId: "8100108", name: "Innsbruck Hbf"), destination: .station(extId: "8100090", name: "Bregenz Bahnhof"),
                             via: [ViaStop(location: Self.feldkirch, minimumDwellMinutes: 10)], date: date, products: .klimaTicket, results: 3)
        let ours = try HafasEncoderTests.encode(HafasRequests.tripSearch(q))
        HafasEncoderTests.assertSameShape(ours, fixture)
        let via = try XCTUnwrap(req["viaLocL"] as? [[String: Any]])
        XCTAssertEqual(via.count, 1)
        XCTAssertEqual(via[0]["min"] as? Int, 10)
        XCTAssertEqual((via[0]["loc"] as? [String: Any])?["lid"] as? String, "A=1@L=8100197@")
        // The full envelope as sent (gate profile) matches too.
        var env = try XCTUnwrap(try HafasEncoderTests.encode(HafasEnvelope(profile: LiveConfig.default.hafas, svcReqL: [HafasRequests.tripSearch(q)])) as? [String: Any])
        env["svcReqL"] = nil
        HafasEncoderTests.assertSameShape(env, try HafasEncoderTests.fixtureEnvelope(Self.scenario))
    }

    func testEveryJourneyPassesTheViaStationWithTheMinimumStay() throws {
        let page = try HafasCodec.journeyPage(from: Fixture.data("hafas/\(Self.scenario).response"))
        XCTAssertEqual(page.journeys.count, 3)
        for j in page.journeys {
            XCTAssertTrue(j.passes(Self.feldkirch), "journey \(j.id) does not pass Feldkirch")
            XCTAssertFalse(j.passes(.station(extId: "8100002", name: "Salzburg Hbf")))
            let stay = try XCTUnwrap(Self.stayMinutes(in: j, at: Self.feldkirch), "no stop at Feldkirch in \(j.id)")
            XCTAssertGreaterThanOrEqual(stay, 10, "minimum stay honoured")
            XCTAssertEqual(j.origin?.extId, "8100108")
            XCTAssertEqual(j.destination?.extId, "8100090")
            XCTAssertEqual(j.legs.map(\.kind), [.ride, .transfer, .ride])
        }
    }

    /// Minutes between arriving at and leaving `station` (leg boundary or a stopover of one ride leg).
    static func stayMinutes(in j: Journey, at station: Location) -> Int? {
        let rides = j.rideLegs
        for (a, b) in zip(rides, rides.dropFirst()) where a.destination.extId == station.extId && b.origin.extId == station.extId {
            guard let arr = a.arrival.effective, let dep = b.departure.effective else { continue }
            return Int(dep.timeIntervalSince(arr) / 60)
        }
        for leg in rides {
            if let s = leg.stopovers.first(where: { $0.location.extId == station.extId }), let arr = s.arrival?.effective, let dep = s.departure?.effective {
                return Int(dep.timeIntervalSince(arr) / 60)
            }
        }
        return nil
    }
}
