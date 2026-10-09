import XCTest
@testable import KlimaCore

final class HafasTimeTests: XCTestCase {
    func testExplicitOffset() throws {
        let d = try XCTUnwrap(HafasTime.date(base: "20261009", time: "111600", tzOffsetMinutes: 120))
        XCTAssertEqual(d, ISO.date("2026-10-09T09:16:00Z"))
    }

    func testDayOffset() throws {
        let d = try XCTUnwrap(HafasTime.date(base: "20261009", time: "01004100", tzOffsetMinutes: 120))
        XCTAssertEqual(d, ISO.date("2026-10-10T00:41:00+02:00"))
        // Month and year roll over.
        XCTAssertEqual(HafasTime.date(base: "20261231", time: "01001500", tzOffsetMinutes: 60), ISO.date("2027-01-01T00:15:00+01:00"))
    }

    func testMissingOffsetIsVienna() throws {
        XCTAssertEqual(HafasTime.date(base: "20261009", time: "111600", tzOffsetMinutes: nil), ISO.date("2026-10-09T11:16:00+02:00"))
        // After the DST change (2026-10-25) Vienna is +01:00.
        XCTAssertEqual(HafasTime.date(base: "20261027", time: "235900", tzOffsetMinutes: nil), ISO.date("2026-10-27T23:59:00+01:00"))
        XCTAssertEqual(HafasTime.date(base: "20261025", time: "01000500", tzOffsetMinutes: nil), ISO.date("2026-10-26T00:05:00+01:00"))
    }

    func testMalformed() {
        XCTAssertNil(HafasTime.date(base: "2026109", time: "111600", tzOffsetMinutes: nil))
        XCTAssertNil(HafasTime.date(base: "20261009", time: "11:16", tzOffsetMinutes: nil))
        XCTAssertNil(HafasTime.date(base: "20261309", time: "111600", tzOffsetMinutes: nil))
        XCTAssertNil(HafasTime.duration(nil))
        XCTAssertNil(HafasTime.duration("abc"))
    }

    func testDurations() {
        XCTAssertEqual(HafasTime.duration("000100"), 60)
        XCTAssertEqual(HafasTime.duration("021600"), 8160)
        XCTAssertEqual(HafasTime.duration("072100"), 26_460)
        XCTAssertEqual(HafasTime.duration("01000000"), 86_400)
        XCTAssertEqual(HafasTime.duration("003800"), 2280)
    }

    /// NJ 19946 departs 22:44 (+02:00) and arrives 05:05 next day (+01:00): 26,460 s = HAFAS `dur` 072100.
    func testDSTGolden() throws {
        let page = try HafasCodec.journeyPage(from: Fixture.data("hafas/tripsearch_overnight_dst_change_wien_innsbruck.response"))
        let g = try XCTUnwrap((try Fixture.golden("hafas/tripsearch_overnight_dst_change_wien_innsbruck")["journeys"] as? [[String: Any]])?.first)
        let j = try XCTUnwrap(page.journeys.first)
        let dep = try XCTUnwrap(j.departure?.planned), arr = try XCTUnwrap(j.arrival?.planned)
        XCTAssertEqual(dep, ISO.date("2026-10-24T22:44:00+02:00"))
        XCTAssertEqual(arr, ISO.date("2026-10-25T05:05:00+01:00"))
        XCTAssertEqual(Int(arr.timeIntervalSince(dep)), 26_460)
        XCTAssertEqual(j.durationSeconds, 26_460)
        XCTAssertEqual(j.durationSeconds, g["durationSec"] as? Int)
        XCTAssertEqual(dep, ISO.date(g["plannedDeparture"] as? String))
        XCTAssertEqual(arr, ISO.date(g["plannedArrival"] as? String))
    }

    func testRequestFormatting() throws {
        let d = try XCTUnwrap(ISO.date("2026-10-09T09:30:05Z"))
        XCTAssertEqual(HafasTime.dateString(d), "20261009")
        XCTAssertEqual(HafasTime.timeString(d), "113005")
        let late = try XCTUnwrap(ISO.date("2026-10-09T22:30:00Z")) // 00:30 next day in Vienna
        XCTAssertEqual(HafasTime.dateString(late), "20261010")
        XCTAssertEqual(HafasTime.timeString(late), "003000")
    }

    func testCivilRoundTrip() {
        for days in [-1, 0, 1, 365, 20_000, 20_735, 21_000] {
            let c = HafasTime.civil(fromDays: days)
            XCTAssertEqual(HafasTime.daysFromCivil(c.y, c.m, c.d), days)
        }
    }
}

final class PolylineTests: XCTestCase {
    func testGoogleReference() {
        let pts = Polyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        XCTAssertEqual(pts.count, 3)
        XCTAssertEqual(pts[0].latitude, 38.5, accuracy: 1e-9)
        XCTAssertEqual(pts[0].longitude, -120.2, accuracy: 1e-9)
        XCTAssertEqual(pts[1].latitude, 40.7, accuracy: 1e-9)
        XCTAssertEqual(pts[1].longitude, -120.95, accuracy: 1e-9)
        XCTAssertEqual(pts[2].latitude, 43.252, accuracy: 1e-9)
        XCTAssertEqual(pts[2].longitude, -126.453, accuracy: 1e-9)
    }

    func testTruncatedAndEmpty() {
        XCTAssertTrue(Polyline.decode("").isEmpty)
        XCTAssertEqual(Polyline.decode("_p~iF~ps|U_ulL").count, 1)
    }

    func testConcatenationDeduplicatesJoints() {
        let a = GeoPoint(latitude: 1, longitude: 1), b = GeoPoint(latitude: 2, longitude: 2), c = GeoPoint(latitude: 3, longitude: 3)
        XCTAssertEqual(Polyline.concatenate([[a, b], [b, c], [], [c]]), [a, b, c])
        XCTAssertEqual(Polyline.concatenate([[a], [c]]), [a, c])
    }

    /// RJX St. Anton → Innsbruck: three segments (DOT · SOLID · DOT) → 889 points; first point at the origin.
    func testTripSearchGolden889() throws {
        let page = try HafasCodec.journeyPage(from: Fixture.data("hafas/tripsearch_st_anton_innsbruck.response"))
        let g = try XCTUnwrap((try Fixture.golden("hafas/tripsearch_st_anton_innsbruck")["journeys"] as? [[String: Any]])?.first)
        let leg = try XCTUnwrap(page.journeys.first?.legs.first)
        XCTAssertEqual(leg.polyline?.count, 889)
        XCTAssertEqual(page.journeys[0].legs.map { $0.polyline?.count ?? 0 }, g["polylinePointCounts"] as? [Int])
        let first = try XCTUnwrap(leg.polyline?.first), origin = try XCTUnwrap(leg.origin.coordinate)
        XCTAssertEqual(first.latitude, origin.latitude, accuracy: 0.02)
        XCTAssertEqual(first.longitude, origin.longitude, accuracy: 0.02)
    }

    /// JourneyDetails RJX 133: 3,589 points, (48.18505, 16.37701) … (45.44138, 12.32044).
    func testJourneyDetailsGolden3589() throws {
        let trip = try HafasCodec.trip(from: Fixture.data("hafas/journeydetails_rjx133_koralm_polyline.response"))
        let g = try XCTUnwrap(try Fixture.golden("hafas/journeydetails_rjx133_koralm_polyline")["trip"] as? [String: Any])
        let poly = try XCTUnwrap(trip.polyline)
        XCTAssertEqual(poly.count, 3589)
        XCTAssertEqual(poly.count, g["polylinePointCount"] as? Int)
        let f = try XCTUnwrap(g["polylineFirst"] as? [Double]), l = try XCTUnwrap(g["polylineLast"] as? [Double])
        XCTAssertEqual(poly[0].latitude, f[0], accuracy: 1e-9)
        XCTAssertEqual(poly[0].longitude, f[1], accuracy: 1e-9)
        XCTAssertEqual(poly[poly.count - 1].latitude, l[0], accuracy: 1e-9)
        XCTAssertEqual(poly[poly.count - 1].longitude, l[1], accuracy: 1e-9)
        XCTAssertEqual(poly[0].latitude, 48.18505, accuracy: 1e-9)
        XCTAssertEqual(poly[poly.count - 1].longitude, 12.32044, accuracy: 1e-9)
    }
}
