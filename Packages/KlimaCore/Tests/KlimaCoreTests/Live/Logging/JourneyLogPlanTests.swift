import XCTest
@testable import KlimaCore

final class JourneyLogPlanTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_791_000_000)

    private lazy var stations = StationIndex(stations: [
        Station(id: "uic:8100108", name: "Innsbruck Hauptbahnhof", lat: 47.2633, lon: 11.4010, state: "T"),
        Station(id: "uic:8100035", name: "Landeck-Zams Bahnhof", lat: 47.1396, lon: 10.5667, state: "T"),
        Station(id: "uic:8100002", name: "St. Anton am Arlberg", lat: 47.1285, lon: 10.2685, state: "T"),
        Station(id: "uic:8100020", name: "Feldkirch Bahnhof", lat: 47.2385, lon: 9.5985, state: "V"),
    ])

    private func loc(_ name: String, _ lat: Double, _ lon: Double, extId: String) -> Location {
        Location(lid: "A=1@L=\(extId)@", kind: .station, extId: extId, name: name, coordinate: GeoPoint(latitude: lat, longitude: lon))
    }

    private var ibk: Location { loc("Innsbruck Hbf", 47.2633, 11.4010, extId: "8100108") }
    private var landeck: Location { loc("Landeck-Zams Bahnhof", 47.1396, 10.5667, extId: "8100035") }
    private var anton: Location { loc("St.Anton am Arlberg Bahnhof", 47.1285, 10.2685, extId: "8100002") }
    private var antonBus: Location { loc("St.Anton am Arlberg Bahnhof (Vorplatz)", 47.1288, 10.2681, extId: "460631") }
    private var lech: Location { loc("Lech Rüfiplatz", 47.2079, 10.1428, extId: "460211") }

    private func ride(_ id: String, _ from: Location, _ to: Location, line: Line, stops: [Location], minutes: Int, start: Double) -> Leg {
        let dep = t0.addingTimeInterval(start * 60), arr = dep.addingTimeInterval(Double(minutes) * 60)
        let stopovers = stops.enumerated().map { i, l in
            Stopover(location: l, arrival: i == 0 ? nil : StopEvent(planned: dep.addingTimeInterval(Double(i) * 600)),
                     departure: i == stops.count - 1 ? nil : StopEvent(planned: dep.addingTimeInterval(Double(i) * 600)), index: i)
        }
        return Leg(id: id, kind: .ride, origin: from, destination: to, departure: StopEvent(planned: dep), arrival: StopEvent(planned: arr),
                   line: line, tripID: id, stopovers: stopovers)
    }

    private var rjx: Line { Line(name: "RJX 19910", category: "RJX", categoryShort: "RJX", trainNumber: "19910", productClass: 1, mode: .train) }
    private var bus: Line { Line(name: "Bus 760", category: "Bus", categoryShort: "Bus", lineNumber: "760", trainNumber: "760", productClass: 64, mode: .bus) }

    private var throughJourney: Journey {
        let train = ride("r1", ibk, anton, line: rjx, stops: [ibk, landeck, anton], minutes: 69, start: 0)
        let walk = Leg(id: "w", kind: .walk, origin: anton, destination: antonBus, departure: StopEvent(planned: t0.addingTimeInterval(69 * 60)),
                       arrival: StopEvent(planned: t0.addingTimeInterval(72 * 60)), walkDistanceMeters: 42, walkDurationSeconds: 180)
        let b = ride("r2", antonBus, lech, line: bus, stops: [antonBus, lech], minutes: 29, start: 84)
        return Journey(legs: [train, walk, b], durationSeconds: 113 * 60, changes: 1, refreshToken: "tok")
    }

    private func quote(_ amount: Double) -> PriceQuote {
        PriceQuote(amountEUR: amount, source: .liveOebb, provider: "ÖBB", travelDate: t0, explanation: "x")
    }

    func testOneRideLegIsOneTrip() {
        let journey = Journey(legs: [ride("r1", ibk, anton, line: rjx, stops: [ibk, landeck, anton], minutes: 69, start: 0)], refreshToken: "tok")
        let plan = JourneyLogPlanner.plan(journey: journey, quote: quote(22.0), coverage: nil, stations: stations)
        XCTAssertEqual(plan.legs.count, 1)
        XCTAssertFalse(plan.isJourney)
        XCTAssertEqual(plan.legs[0].fareEUR, 22.0, accuracy: 0.001)
        XCTAssertEqual(plan.legs[0].fromStationID, "uic:8100108")
        XCTAssertEqual(plan.legs[0].fromName, "Innsbruck Hauptbahnhof")
        XCTAssertEqual(plan.legs[0].mode, .train)
        XCTAssertEqual(plan.date, t0)
        XCTAssertEqual(plan.lineSummary, "RJX 19910")
        XCTAssertEqual(plan.journeyRef, "tok")
        XCTAssertGreaterThan(plan.legs[0].distanceKm, 80)
    }

    func testRideLegsBecomeAJourneyAndWalksAreNoTrips() {
        let plan = JourneyLogPlanner.plan(journey: throughJourney, quote: quote(29.70), coverage: nil, stations: stations)
        XCTAssertEqual(plan.legs.count, 2)
        XCTAssertTrue(plan.isJourney)
        XCTAssertEqual(plan.legs.map(\.mode), [.train, .bus])
        XCTAssertEqual(plan.legs.map(\.fareEUR).reduce(0, +), 29.70, accuracy: 0.0001)
        XCTAssertGreaterThan(plan.legs[0].fareEUR, plan.legs[1].fareEUR)   // the longer leg carries more
        XCTAssertEqual(plan.legs[1].toName, "Lech Rüfiplatz")
        XCTAssertNil(plan.legs[1].toStationID)
        XCTAssertEqual(plan.lineSummary, "RJX 19910 · Bus 760")
        XCTAssertEqual(plan.arrivalAt, t0.addingTimeInterval((84 + 29) * 60))
    }

    func testPartialCoverageLogsOnlyTheCoveredSegment() {
        let coverage = JourneyCoverage(overall: .partial, legs: [], lastCoveredLegIndex: 0, lastCoveredStopName: "Landeck-Zams Bahnhof")
        let plan = JourneyLogPlanner.plan(journey: throughJourney, quote: quote(12.40), coverage: coverage, stations: stations)
        XCTAssertTrue(plan.isPartial)
        XCTAssertEqual(plan.legs.count, 1)
        XCTAssertEqual(plan.legs[0].toName, "Landeck-Zams Bahnhof")
        XCTAssertEqual(plan.legs[0].toStationID, "uic:8100035")
        XCTAssertEqual(plan.legs[0].fareEUR, 12.40, accuracy: 0.001)
        let full = JourneyLogPlanner.plan(journey: throughJourney, quote: quote(29.70), coverage: nil, stations: stations)
        XCTAssertLessThan(plan.legs[0].distanceKm, full.legs[0].distanceKm)
        XCTAssertEqual(plan.lastCoveredName, "Landeck-Zams Bahnhof")
    }

    func testViaStopsLandOnTheLegThatPassesThem() {
        let plan = JourneyLogPlanner.plan(journey: throughJourney, quote: quote(29.70), coverage: nil,
                                          via: [ViaStop(location: landeck)], stations: stations)
        XCTAssertEqual(plan.legs[0].via.map(\.name), ["Landeck-Zams Bahnhof"])
        XCTAssertEqual(plan.legs[0].via.first?.stationID, "uic:8100035")
        XCTAssertTrue(plan.legs[1].via.isEmpty)
    }

    func testStatesFollowTheStops() {
        let plan = JourneyLogPlanner.plan(journey: throughJourney, quote: quote(29.70), coverage: nil, stations: stations)
        XCTAssertEqual(plan.legs[0].states, ["T"])
    }

    func testShareRemainderGoesToTheHeaviestLegAndSumsExactly() {
        let shares = JourneyLogPlanner.distribute(10.0, over: [1, 1, 1])
        XCTAssertEqual(shares.reduce(0, +), 10.0, accuracy: 0.0001)
        XCTAssertEqual(shares.sorted(), [3.33, 3.33, 3.34])
        XCTAssertEqual(JourneyLogPlanner.distribute(29.70, over: [0, 0]), [14.85, 14.85])
        XCTAssertEqual(JourneyLogPlanner.distribute(5.0, over: [7.0]), [5.0])
    }

    func testWalkOnlyConnectionIsEmpty() {
        let walk = Leg(id: "w", kind: .walk, origin: anton, destination: antonBus, departure: StopEvent(planned: t0), arrival: StopEvent(planned: t0))
        let plan = JourneyLogPlanner.plan(journey: Journey(legs: [walk]), quote: nil, coverage: nil, stations: stations)
        XCTAssertTrue(plan.isEmpty)
    }
}
