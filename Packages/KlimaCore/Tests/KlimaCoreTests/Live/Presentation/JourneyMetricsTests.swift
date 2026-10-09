import XCTest
@testable import KlimaCore

/// SPEC §C3.5 / §D2 WP-C 7.
final class JourneyMetricsTests: XCTestCase {
    func testInnsbruckLech() throws {
        let j = try CoverageFixtures.page("tripsearch_innsbruck_lech_bus").journeys[0]
        XCTAssertEqual(JourneyMetrics.dominantMode(j), .train)
        XCTAssertEqual(JourneyMetrics.lineSummary(j), "RJX 19960 · Bus 750")
        // No polylines in the fixture → stopover method: RJX 99.1 + Bus 11.6 + 35 m walk.
        XCTAssertTrue(j.rideLegs.allSatisfy { $0.polyline == nil })
        let km = try XCTUnwrap(JourneyMetrics.distanceKm(j))
        XCTAssertEqual(km, 110.7, accuracy: 0.2)
        XCTAssertEqual(km, (km * 10).rounded() / 10, "rounded to 0.1")
    }

    func testDistanceMethods() throws {
        var j = try CoverageFixtures.page("tripsearch_innsbruck_lech_bus").journeys[0]
        // 1. Polylines on every ride leg win.
        let a = GeoPoint(latitude: 47.0, longitude: 11.0), b = GeoPoint(latitude: 47.1, longitude: 11.0)
        let c = GeoPoint(latitude: 47.2, longitude: 11.0)
        j.legs[0].polyline = [a, b]
        j.legs[2].polyline = [b, c]
        let expected = a.distanceKm(to: b) + b.distanceKm(to: c) + 0.035
        XCTAssertEqual(try XCTUnwrap(JourneyMetrics.distanceKm(j)), (expected * 10).rounded() / 10, accuracy: 0.0001)
        // 3. Without polylines and stopovers: crow flies × rail detour.
        for i in j.legs.indices { j.legs[i].polyline = nil; j.legs[i].stopovers = [] }
        let straight = try XCTUnwrap(j.origin?.coordinate).distanceKm(to: try XCTUnwrap(j.destination?.coordinate))
        let detour = FareModel.fallback.railDistance(fromStraightLineKm: straight)
        XCTAssertEqual(try XCTUnwrap(JourneyMetrics.distanceKm(j)), (detour * 10).rounded() / 10, accuracy: 0.0001)
        j.legs[0].origin.coordinate = nil
        XCTAssertNil(JourneyMetrics.distanceKm(j))
    }

    func testDominantModeTies() {
        let t0 = Vienna.date("2026-10-09 10:00")
        func ride(_ mode: TransportMode, _ minutes: Double, start: Double) -> Leg {
            let s = Location.station(extId: "1", name: "A")
            return Leg(id: "\(mode)", kind: .ride, origin: s, destination: s,
                       departure: StopEvent(planned: t0.addingTimeInterval(start * 60)),
                       arrival: StopEvent(planned: t0.addingTimeInterval((start + minutes) * 60)),
                       line: Line(name: "x", mode: mode))
        }
        XCTAssertEqual(JourneyMetrics.dominantMode(Journey(legs: [ride(.bus, 30, start: 0), ride(.train, 30, start: 40)])), .train)
        XCTAssertEqual(JourneyMetrics.dominantMode(Journey(legs: [ride(.bus, 31, start: 0), ride(.train, 30, start: 40)])), .bus)
        XCTAssertEqual(JourneyMetrics.dominantMode(Journey(legs: [])), .other)
    }

    /// A synthetic Wien → München RJ is covered up to Salzburg Hbf → priced segment (Wien Hbf, Salzburg Hbf).
    func testCoveredSegmentOfAPartialJourney() throws {
        let t0 = Vienna.date("2026-10-10 08:28")
        func stop(_ ext: String, _ name: String, _ lat: Double, _ lon: Double, _ cc: String, _ min: Double) -> Stopover {
            Stopover(location: Location(lid: "A=1@L=\(ext)@", extId: ext, name: name, coordinate: GeoPoint(latitude: lat, longitude: lon),
                                        countryCode: cc),
                     arrival: StopEvent(planned: t0.addingTimeInterval(min * 60)), departure: StopEvent(planned: t0.addingTimeInterval(min * 60)))
        }
        let stops = [stop("1290401", "Wien Hbf", 48.18519, 16.37641, "at", 0), stop("8100002", "Salzburg Hbf", 47.81306, 13.04513, "at", 145),
                     stop("8000320", "Rosenheim", 47.85002, 12.11921, "de", 200), stop("8000261", "München Hbf", 48.1401, 11.5585, "de", 240)]
        let rj = Leg(id: "rj", kind: .ride, origin: stops[0].location, destination: stops[3].location, departure: stops[0].departure!,
                     arrival: stops[3].arrival!,
                     line: Line(name: "RJ 61", fullName: "RJ 61", category: "RJ", categoryLong: "railjet", trainNumber: "61",
                                operatorName: "Nahreisezug", productClass: 1, mode: .train),
                     stopovers: stops)
        let journey = Journey(legs: [rj], durationSeconds: 240 * 60)
        let coverage = CoverageFixtures.evaluator.evaluate(journey, scope: .oe)
        XCTAssertEqual(coverage.overall, .partial)
        XCTAssertEqual(coverage.legs[0].ruleID, "cross-border-beyond-gemeinschaftsbahnhof")
        XCTAssertEqual(coverage.lastCoveredLegIndex, 0)
        XCTAssertEqual(coverage.lastCoveredStopName, "Salzburg Hbf")
        let segment = try XCTUnwrap(JourneyMetrics.coveredSegment(journey, coverage: coverage))
        XCTAssertEqual(segment.from.name, "Wien Hbf")
        XCTAssertEqual(segment.to.name, "Salzburg Hbf")
        XCTAssertEqual(segment.to.extId, "8100002")
        XCTAssertEqual(segment.to.kind, .station)
        // Covered and not-covered journeys have no segment.
        let lech = try CoverageFixtures.page("tripsearch_innsbruck_lech_bus").journeys[0]
        XCTAssertNil(JourneyMetrics.coveredSegment(lech, coverage: CoverageFixtures.evaluator.evaluate(lech, scope: .oe)))
        // Covered first leg, a foreign bus from the border onwards → the change station (the bus leg is `partial` with
        // its own origin as the last covered stop, so it ends the covered prefix).
        var two = journey
        var first = rj
        first.destination = stops[1].location
        first.arrival = stops[1].arrival!
        first.stopovers = Array(stops[0...1])
        var second = rj
        second.id = "db"
        second.origin = stops[1].location
        second.departure = stops[1].departure!
        second.stopovers = Array(stops[1...3])
        second.line = Line(name: "Bus 840", category: "Bus", operatorName: "DB Regio Bus Bayern", productClass: 64, mode: .bus)
        two.legs = [first, second]
        let cov2 = CoverageFixtures.evaluator.evaluate(two, scope: .oe)
        XCTAssertEqual(cov2.overall, .partial)
        XCTAssertEqual(cov2.legs.map(\.result), [.covered, .partial])
        XCTAssertEqual(cov2.lastCoveredLegIndex, 1)
        XCTAssertEqual(cov2.lastCoveredStopName, "Salzburg Hbf")
        XCTAssertEqual(JourneyMetrics.coveredSegment(two, coverage: cov2)?.to.name, "Salzburg Hbf")
    }
}
