import XCTest
@testable import KlimaCore

final class CockpitRouteTests: XCTestCase {
    typealias F = CockpitFixtures

    func testStopsAreLaidAlongThePolyline() {
        let route = F.route()
        XCTAssertFalse(route.isStraightLine)
        XCTAssertEqual(route.stops.count, 4)
        XCTAssertEqual(route.stops.map(\.km), route.stops.map(\.km).sorted())
        XCTAssertEqual(route.stops[0].km, 0.1 * 74.5, accuracy: 0.3)
        XCTAssertEqual(route.stops[3].km, 3.1 * 74.5, accuracy: 0.6)
        XCTAssertEqual(route.runKm, 3.0 * 74.5, accuracy: 0.6)
    }

    func testNoPolylineMeansStraightLines() {
        let route = F.route(polyline: nil)
        XCTAssertTrue(route.isStraightLine)
        XCTAssertEqual(route.stops[0].km, 0)
        XCTAssertEqual(route.stops[1].km, 74.5, accuracy: 0.3)
        XCTAssertEqual(route.path.lengthKm, route.stops.last?.km ?? -1, accuracy: 0.001)
    }

    func testAPolylineThatMissesTheStopsIsNotUsed() {
        // The polyline runs 0.05° (5.5 km) north of the stops: that is not their route.
        let shifted = F.straightPolyline().map { GeoPoint(latitude: $0.latitude + 0.05, longitude: $0.longitude) }
        XCTAssertTrue(F.route(polyline: shifted).isStraightLine)
        // A polyline of one point is no polyline.
        XCTAssertTrue(F.route(polyline: [F.point(14.0)]).isStraightLine)
        // A polyline that visits the stops in the wrong order is not their route either.
        XCTAssertTrue(F.route(polyline: Array(F.straightPolyline().reversed())).isStraightLine)
    }

    func testStopsWithoutCoordinateOrTimeAreLeftOut() {
        var stops = F.stopovers(F.fourStops())
        stops[1].location.coordinate = nil
        stops[2].arrival = nil
        stops[2].departure = nil
        let route = CockpitRoute(stopovers: stops, polyline: nil)
        XCTAssertEqual(route?.stops.count, 2)
        XCTAssertNil(CockpitRoute(stopovers: Array(stops.prefix(2)), polyline: nil))
        XCTAssertNil(CockpitRoute(stopovers: [], polyline: nil))
    }

    func testStopFieldsCarryTimesDelaysAndPlatform() {
        var stops = F.fourStops()
        stops[1].arrDelay = 6
        stops[1].depDelay = 5
        let route = F.route(stops)
        let b = route.stops[1]
        XCTAssertEqual(b.name, "Halt 1")
        XCTAssertEqual(b.plannedArrival, F.at(30))
        XCTAssertEqual(b.arrival, F.at(36))
        XCTAssertEqual(b.departure, F.at(37))
        XCTAssertEqual(b.arrivalDelay, 360)
        XCTAssertEqual(b.departureDelay, 300)
        XCTAssertEqual(b.platform?.text, "Gl. 3")
        XCTAssertTrue(b.isServed)
        XCTAssertNil(route.stops[2].arrivalDelay, "no report, no delay")
        XCTAssertEqual(route.stops[2].arrival, F.at(62), "the planned time stands in for a missing realtime")
    }

    func testProgressAndFraction() {
        let route = F.route()
        XCTAssertEqual(route.progress(atKm: route.firstKm), 0, accuracy: 1e-9)
        XCTAssertEqual(route.progress(atKm: route.lastKm), 1, accuracy: 1e-9)
        XCTAssertEqual(route.progress(atKm: (route.firstKm + route.lastKm) / 2), 0.5, accuracy: 1e-9)
        XCTAssertEqual(route.progress(atKm: route.firstKm - 50), 0)
        XCTAssertEqual(route.progress(atKm: route.lastKm + 50), 1)
        XCTAssertEqual(route.fraction(of: route.stops[1]), 1.0 / 3.0, accuracy: 0.01)
    }

    func testKmOfAPositionUsesTheWindow() {
        let route = F.route()
        let onB = route.km(of: F.point(15.0))
        XCTAssertEqual(onB ?? -1, route.stops[1].km, accuracy: 0.3)
        // With a hint the search stays near it: a point at C is outside a 12 km window around B.
        XCTAssertNil(route.km(of: F.point(16.0), hintKm: route.stops[1].km, windowKm: 12))
        XCTAssertEqual(route.km(of: F.point(15.05), hintKm: route.stops[1].km) ?? -1, route.stops[1].km + 0.05 * 74.5, accuracy: 0.3)
        // Far from the route: nothing.
        XCTAssertNil(route.km(of: GeoPoint(latitude: 48.5, longitude: 15.0)))
    }

    // MARK: Situation

    func testBeforeDeparture() {
        let route = F.route()
        let km = route.stops[0].km
        XCTAssertEqual(route.situation(atKm: km, now: F.at(-3)), .beforeDeparture(stop: 0))
        XCTAssertEqual(route.nextStopIndex(atKm: km, now: F.at(-3)), 1)
        // Past the departure time and still on the spot: leaving, on the way to the next stop.
        XCTAssertEqual(route.situation(atKm: km, now: F.at(1)), .between(from: 0, to: 1))
    }

    func testBetweenTwoStops() {
        let route = F.route()
        let km = (route.stops[1].km + route.stops[2].km) / 2
        XCTAssertEqual(route.situation(atKm: km, now: F.at(47)), .between(from: 1, to: 2))
        XCTAssertEqual(route.nextStopIndex(atKm: km, now: F.at(47)), 2)
        XCTAssertEqual(route.upcoming(atKm: km, now: F.at(47), limit: 5).map(\.id), [2, 3])
        XCTAssertEqual(route.upcoming(atKm: km, now: F.at(47), limit: 1).map(\.id), [2])
        XCTAssertEqual(route.upcoming(atKm: km, now: F.at(47), limit: 0).count, 0)
    }

    func testStandingAtAStopNeedsPositionAndTimes() {
        let route = F.route()
        let km = route.stops[1].km
        XCTAssertEqual(route.situation(atKm: km, now: F.at(31)), .atStop(1))
        XCTAssertEqual(route.nextStopIndex(atKm: km, now: F.at(31)), 2, "standing at B: the next stop is C")
        XCTAssertEqual(route.upcoming(atKm: km, now: F.at(31), limit: 3).map(\.id), [2, 3])
        // Before the arrival time the train is approaching, not standing.
        XCTAssertEqual(route.situation(atKm: km - 0.2, now: F.at(29)), .between(from: 0, to: 1))
        // After the departure time it is leaving.
        XCTAssertEqual(route.situation(atKm: km + 0.1, now: F.at(33)), .between(from: 1, to: 2))
        // A late train: the stop's times move with the delay.
        var stops = F.fourStops()
        stops[1].arrDelay = 6
        stops[1].depDelay = 6
        let late = F.route(stops)
        XCTAssertEqual(late.situation(atKm: late.stops[1].km, now: F.at(31)), .between(from: 0, to: 1), "not yet arrived at its delayed time")
        XCTAssertEqual(late.situation(atKm: late.stops[1].km, now: F.at(37)), .atStop(1))
    }

    func testArrived() {
        let route = F.route()
        XCTAssertEqual(route.situation(atKm: route.lastKm, now: F.at(96)), .arrived(stop: 3))
        XCTAssertEqual(route.situation(atKm: route.lastKm + 3, now: F.at(120)), .arrived(stop: 3))
        XCTAssertNil(route.nextStopIndex(atKm: route.lastKm, now: F.at(96)))
        XCTAssertTrue(route.upcoming(atKm: route.lastKm, now: F.at(96), limit: 4).isEmpty)
        // Approaching the last stop 300 m before it is still on the way.
        XCTAssertEqual(route.situation(atKm: route.lastKm - 0.3, now: F.at(94)), .between(from: 2, to: 3))
    }

    func testStopsWithoutServiceAreNotNextStops() {
        var stops = F.fourStops()
        stops[1].passes = true            // the line passes B without stopping
        stops[2].arrCancelled = true      // C is cancelled
        stops[2].depCancelled = true
        let route = F.route(stops)
        XCTAssertFalse(route.stops[1].isServed)
        XCTAssertFalse(route.stops[2].isServed)
        let km = route.stops[0].km + 5
        XCTAssertEqual(route.situation(atKm: km, now: F.at(3)), .between(from: 0, to: 3))
        XCTAssertEqual(route.nextStopIndex(atKm: km, now: F.at(3)), 3)
        XCTAssertEqual(route.upcoming(atKm: km, now: F.at(3), limit: 4).map(\.id), [3])
        // The train does not stand at a stop it passes.
        XCTAssertEqual(route.situation(atKm: route.stops[1].km, now: F.at(31)), .between(from: 1, to: 3))
    }

    // MARK: Tint

    func testLegTintFollowsTheDelayAtTheEndOfTheLeg() {
        var stops = F.fourStops()
        stops[1].arrDelay = 1; stops[1].depDelay = 1     // B: one minute: on time by the radar's rule
        stops[2].arrDelay = 6; stops[2].depDelay = 6     // C: six minutes late
        let route = F.route(stops)
        XCTAssertEqual(route.legs.map(\.state), [.onTime, .late, .late], "D has no report: the delay of C carries on")
        XCTAssertEqual(route.legs.map(\.id), [0, 1, 2])
        XCTAssertEqual(route.legs[0].fromKm, route.stops[0].km)
        XCTAssertEqual(route.legs[0].toKm, route.stops[1].km)
    }

    func testLegTintUnknownWithoutAnyReport() {
        XCTAssertEqual(F.route().legs.map(\.state), [.unknown, .unknown, .unknown])
    }

    func testLegTintCancelled() {
        var stops = F.fourStops(delay: 0)
        stops[2].arrCancelled = true
        stops[2].depCancelled = true
        XCTAssertEqual(F.route(stops).legs.map(\.state), [.onTime, .cancelled, .onTime])
        XCTAssertEqual(F.route(F.fourStops(delay: 0), cancelled: true).legs.map(\.state), [.cancelled, .cancelled, .cancelled])
    }

    func testDelayStateUsesTheRadarsFiveMinutes() {
        XCTAssertEqual(CockpitRoute.state(forDelay: nil), .unknown)
        XCTAssertEqual(CockpitRoute.state(forDelay: -120), .onTime)
        XCTAssertEqual(CockpitRoute.state(forDelay: 0), .onTime)
        XCTAssertEqual(CockpitRoute.state(forDelay: 299), .onTime)
        XCTAssertEqual(CockpitRoute.state(forDelay: 300), .late)
    }

    func testCarriedDelay() {
        var stops = F.fourStops()
        stops[1].arrDelay = 4
        let route = F.route(stops)
        XCTAssertNil(route.carriedDelay(at: 0))
        XCTAssertEqual(route.carriedDelay(at: 1), 240)
        XCTAssertEqual(route.carriedDelay(at: 3), 240)
        XCTAssertNil(route.carriedDelay(at: 9))
    }

    // MARK: A run that ends early (review 1)

    func testATrainThatTurnsShortEndsAtItsLastServedStop() {
        var stops = F.fourStops(delay: 2)
        stops[3].arrCancelled = true      // "Zug endet in Halt 2": the last stop D is cancelled
        let route = F.route(stops)
        XCTAssertEqual(route.endIndex, 2)
        XCTAssertEqual(route.endStop.name, "Halt 2")
        XCTAssertEqual(route.lastKm, route.stops[2].km)
        XCTAssertEqual(route.progress(atKm: route.stops[2].km), 1, accuracy: 1e-9)
        // On the way to C: C is the end, no stop after it is ever "next", the cancelled D is no flag.
        let km = (route.stops[1].km + route.stops[2].km) / 2
        XCTAssertEqual(route.nextStopIndex(atKm: km, now: F.at(47)), 2)
        XCTAssertEqual(route.upcoming(atKm: km, now: F.at(47), limit: 4).map(\.id), [2])
        // At C the run is over, although the list goes on to D (before: "stands at C", next stop the cancelled D with its time).
        XCTAssertEqual(route.situation(atKm: route.stops[2].km, now: F.at(65)), .arrived(stop: 2))
        XCTAssertNil(route.nextStopIndex(atKm: route.stops[2].km, now: F.at(65)))
        // The cancelled leg is still drawn ahead of the train, red.
        XCTAssertEqual(route.legs.map(\.state), [.onTime, .onTime, .cancelled])
        XCTAssertEqual(route.lines(atKm: km).ahead.last?.state, .cancelled)
    }

    func testTheShortTurnEndForTheExitAlarm() {
        var stops = F.fourStops()
        XCTAssertNil(CockpitRoute.shortTurnEndID(of: F.stopovers(stops)), "the last stop is served: the alarm keeps its own default")
        stops[3].arrCancelled = true
        XCTAssertEqual(CockpitRoute.shortTurnEndID(of: F.stopovers(stops)), "cockpit|2")
        stops[2].arrCancelled = true; stops[2].depCancelled = true
        stops[1].passes = true
        XCTAssertNil(CockpitRoute.shortTurnEndID(of: F.stopovers(stops)), "only the first stop is left: no run to end early")
        XCTAssertNil(CockpitRoute.shortTurnEndID(of: []))
    }

    func testTheEndOfARunWithoutCancelledStopsIsTheLastStop() {
        XCTAssertEqual(F.route().endIndex, 3)
        XCTAssertEqual(F.route(F.fourStops(delay: 0), cancelled: true).endIndex, 3, "a cancelled run keeps its stops")
        // Everything after the first stop cancelled: no run to speak of, the list's last stop stays the end.
        var stops = F.fourStops()
        for index in 1...3 { stops[index].arrCancelled = true; stops[index].depCancelled = true }
        XCTAssertEqual(F.route(stops).endIndex, 3)
    }
}
