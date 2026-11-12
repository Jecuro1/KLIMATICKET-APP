import XCTest
@testable import KlimaCore

/// Zug-Radar (JourneyGeoPos): request shape, parser over the synthetic fixture, and the client-side guards.
/// The fixture is invented (see Fixtures/OEBB/hafas/radar_synthetic_austria.response.json); no live data is used here.
final class RadarTests: XCTestCase {
    private let when = Date(timeIntervalSince1970: 1_791_796_500)

    private func encodedRequest(_ query: RadarQuery) throws -> [String: Any] {
        let body = try JSONEncoder().encode(HafasRequests.journeyGeoPos(query))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    func testRequestKeySetAndRectangle() throws {
        let query = RadarQuery(box: RadarBox(north: 47.5, west: 13.0, south: 47.0, east: 14.0), when: when)
        let req = try encodedRequest(query)
        XCTAssertEqual(req["meth"] as? String, "JourneyGeoPos")
        XCTAssertNil(req["cfg"], "radar sends no cfg (rtMode is never sent)")
        let body = try XCTUnwrap(req["req"] as? [String: Any])
        // Exactly the reference key set (format/radar-req.js); the /gate parser rejects anything else.
        XCTAssertEqual(Set(body.keys), ["maxJny", "onlyRT", "date", "time", "rect", "perSize", "perStep", "ageOfReport",
                                        "jnyFltrL", "trainPosMode"])
        XCTAssertEqual(body["maxJny"] as? Int, 1000, "the request cap measured in docs/OEBB_LIVE.md §R11")
        XCTAssertEqual(body["onlyRT"] as? Bool, false)
        XCTAssertEqual(body["ageOfReport"] as? Bool, true)
        XCTAssertEqual(body["trainPosMode"] as? String, "CALC")
        XCTAssertEqual(body["perSize"] as? Int, 30_000)
        XCTAssertEqual(body["perStep"] as? Int, 10_000)
        let rect = try XCTUnwrap(body["rect"] as? [String: Any])
        let ll = try XCTUnwrap(rect["llCrd"] as? [String: Int])
        let ur = try XCTUnwrap(rect["urCrd"] as? [String: Int])
        XCTAssertEqual(ll["x"], 13_000_000, "llCrd.x = west")
        XCTAssertEqual(ll["y"], 47_000_000, "llCrd.y = south")
        XCTAssertEqual(ur["x"], 14_000_000, "urCrd.x = east")
        XCTAssertEqual(ur["y"], 47_500_000, "urCrd.y = north")
        XCTAssertEqual(body["date"] as? String, HafasTime.dateString(when))
        XCTAssertEqual(body["time"] as? String, HafasTime.timeString(when))
    }

    func testRailFilterIsPROD4157() throws {
        let req = try encodedRequest(RadarQuery(when: when))
        let body = try XCTUnwrap(req["req"] as? [String: Any])
        let filters = try XCTUnwrap(body["jnyFltrL"] as? [[String: Any]])
        XCTAssertEqual(filters.count, 1)
        XCTAssertEqual(filters[0]["type"] as? String, "PROD")
        XCTAssertEqual(filters[0]["mode"] as? String, "INC")
        XCTAssertEqual(filters[0]["value"] as? String, "4157")
    }

    func testMaxVehiclesIsClampedAndFramesNeverDivideByZero() throws {
        let req = try encodedRequest(RadarQuery(when: when, maxVehicles: 9_999, durationSeconds: 60, frames: 0))
        let body = try XCTUnwrap(req["req"] as? [String: Any])
        XCTAssertEqual(body["maxJny"] as? Int, 1000)
        XCTAssertEqual(body["perStep"] as? Int, 60_000)
        let small = try encodedRequest(RadarQuery(when: when, maxVehicles: 300))
        XCTAssertEqual((small["req"] as? [String: Any])?["maxJny"] as? Int, 300, "a smaller request is passed on as asked")
    }

    func testParserKeepsPositionedUniqueVehicles() throws {
        let snapshot = try HafasCodec.radar(from: Fixture.data("hafas/radar_synthetic_austria.response"))
        // The bus has no position and the fourth entry repeats the first trip id: both are dropped.
        XCTAssertEqual(snapshot.vehicles.map(\.tripID), ["1|SYN0000001|0|1012", "1|SYN0000002|0|1012"])
        XCTAssertEqual(snapshot.realtimeUpdatedAt, Date(timeIntervalSince1970: 1_791_796_500))
        XCTAssertEqual(snapshot.answeredCount, 4, "the server answered four journeys, two of them are dropped")
    }

    /// The cut-off test must see what the server answered, not what is left after the entries without a position are dropped:
    /// 1000 answered and three of them without a position is a cut-off answer with 997 vehicles.
    func testAnAnswerCutOffAtTheCapIsRecognisedEvenWhenSomeEntriesHaveNoPosition() throws {
        var entries: [String] = []
        for index in 0..<1000 {
            if index < 3 {
                entries.append(#"{"jid":"1|NOPOS\#(index)|0|1","date":"20261012","prodX":0}"#)
            } else {
                entries.append(#"{"jid":"1|T\#(index)|0|1","date":"20261012","prodX":0,"pos":{"x":13600000,"y":48000000}}"#)
            }
        }
        let json = #"{"ver":"1.88","err":"OK","svcResL":[{"meth":"JourneyGeoPos","err":"OK","res":{"common":{},"jnyL":["# + entries.joined(separator: ",") + "]}}]}"
        let snapshot = try HafasCodec.radar(from: Data(json.utf8))
        XCTAssertEqual(snapshot.vehicles.count, 997)
        XCTAssertEqual(snapshot.answeredCount, 1000)
        XCTAssertFalse(RadarTiling.isTruncated(count: snapshot.vehicles.count), "the vehicles alone would hide the cut-off")
        XCTAssertTrue(RadarTiling.isTruncated(count: snapshot.answeredCount))
    }

    func testAnsweredCountIsNeverBelowTheVehicles() {
        let vehicle = RadarVehicle(tripID: "a", coordinate: GeoPoint(latitude: 47, longitude: 13))
        XCTAssertEqual(RadarSnapshot(vehicles: [vehicle]).answeredCount, 1, "defaults to the vehicles (demo and tests)")
        XCTAssertEqual(RadarSnapshot(vehicles: [vehicle], answeredCount: 0).answeredCount, 1)
        XCTAssertEqual(RadarSnapshot.empty.answeredCount, 0)
    }

    func testParserMapsLineDirectionAndPosition() throws {
        let snapshot = try HafasCodec.radar(from: Fixture.data("hafas/radar_synthetic_austria.response"))
        let rjx = try XCTUnwrap(snapshot.vehicles.first)
        XCTAssertEqual(rjx.line?.name, "RJX 66")
        XCTAssertEqual(rjx.direction, "Wien Hbf")
        XCTAssertEqual(rjx.coordinate.latitude, 48.0, accuracy: 1e-9)
        XCTAssertEqual(rjx.coordinate.longitude, 13.6, accuracy: 1e-9)
        XCTAssertEqual(rjx.stopovers.map(\.location.name), ["Salzburg Hbf", "Linz Hbf", "Wien Hbf"])

        let linz = try XCTUnwrap(rjx.stopovers.dropFirst().first)
        XCTAssertEqual(linz.departure?.delaySeconds, 300, "realtime departure is five minutes late")
        XCTAssertEqual(linz.departure?.platform?.text, "4")
        XCTAssertTrue(linz.departure?.platformChanged == true, "platform 3 → 4")

        let sbahn = try XCTUnwrap(snapshot.vehicles.last)
        XCTAssertEqual(sbahn.line?.name, "S 45")
        XCTAssertEqual(sbahn.line?.mode, .sBahn)
    }

    func testMissingJourneyListIsEmptyNotAnError() throws {
        let data = Data(#"{"ver":"1.88","err":"OK","svcResL":[{"meth":"JourneyGeoPos","err":"OK","res":{"common":{}}}]}"#.utf8)
        let snapshot = try HafasCodec.radar(from: data)
        XCTAssertTrue(snapshot.vehicles.isEmpty)
        XCTAssertEqual(snapshot.answeredCount, 0)
        XCTAssertNil(snapshot.realtimeUpdatedAt)
    }

    func testDegenerateBoxNeverLeavesTheDevice() async throws {
        let transport = FixtureTransport(routes: [])   // any request would fail the test
        let (client, _) = HafasClient.testClient(transport, clock: FakeClock(when))
        let flat = RadarBox(north: 47.0, west: 13.0, south: 47.0, east: 14.0)
        let snapshot = try await client.radar(RadarQuery(box: flat, when: when))
        XCTAssertEqual(snapshot, RadarSnapshot.empty)
        XCTAssertTrue(transport.recorded.isEmpty)
    }

    func testBoxHelpers() {
        XCTAssertTrue(RadarBox.austria.isValid)
        XCTAssertFalse(RadarBox(north: 47, west: 13, south: 47, east: 14).isValid)
        XCTAssertFalse(RadarBox(north: .nan, west: 13, south: 47, east: 14).isValid)
        let around = RadarBox.around(GeoPoint(latitude: 47.2, longitude: 11.4), halfSpan: 0.5)
        XCTAssertEqual(around.center.latitude, 47.2, accuracy: 1e-9)
        XCTAssertEqual(around.center.longitude, 11.4, accuracy: 1e-9)
    }
}
