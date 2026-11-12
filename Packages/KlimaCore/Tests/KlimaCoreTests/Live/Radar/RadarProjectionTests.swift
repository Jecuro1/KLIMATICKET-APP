import XCTest
@testable import KlimaCore

/// Radar time travel: where a run is at another time (docs/RADAR_TIMETRAVEL.md §2, §3). Synthetic runs on a west-east line, no network.
final class RadarProjectionTests: XCTestCase {
    private typealias F = RadarTimeFixtures

    private func schedule(_ stops: [F.Stop]) -> RadarSchedule {
        RadarSchedule(F.vehicle("t", stops: stops))
    }

    // MARK: Schedule: planned times plus the delay that is known

    func testDelayIsCarriedOnToStopsWithoutAReport() {
        // A reports 2 min on departure, B has no report, C reports 5 min: B takes A's 2 minutes, C its own 5.
        let stops = [F.Stop(lon: 14, arr: nil, dep: 0, depDelay: 2), F.Stop(lon: 15, arr: 30, dep: 32), F.Stop(lon: 16, arr: 62, dep: nil, arrDelay: 5)]
        let schedule = self.schedule(stops)
        XCTAssertEqual(schedule.stops.count, 3)
        XCTAssertEqual(schedule.stops[1].arrival, F.at(32), "planned 30 + the 2 minutes carried from A")
        XCTAssertEqual(schedule.stops[1].departure, F.at(34))
        XCTAssertEqual(schedule.stops[2].arrival, F.at(67), "its own report: 62 + 5")
        XCTAssertEqual(schedule.stops[1].arrivalDelay, 120)
        XCTAssertEqual(schedule.stops[2].arrivalDelay, 300)
        XCTAssertTrue(schedule.hasRealtime)
    }

    func testWithoutAnyReportTheTimesArePlannedAndTheDelayIsUnknown() {
        let schedule = self.schedule(F.threeStops())
        XCTAssertFalse(schedule.hasRealtime)
        XCTAssertEqual(schedule.stops[1].arrival, F.at(30))
        XCTAssertNil(schedule.delay(at: F.at(10)), "no report: no number, the ring is grey")
    }

    func testDelayAtATimeIsTheOneOfTheNextStop() {
        let schedule = self.schedule([F.Stop(lon: 14, arr: nil, dep: 0, depDelay: 1), F.Stop(lon: 15, arr: 30, dep: 32, arrDelay: 6, depDelay: 6),
                                      F.Stop(lon: 16, arr: 62, dep: nil, arrDelay: 6)])
        XCTAssertEqual(schedule.delay(at: F.at(-5)), 60, "before the start: the first stop's")
        XCTAssertEqual(schedule.delay(at: F.at(10)), 360, "between A and B: B's, the stop it heads for")
        XCTAssertEqual(schedule.delay(at: F.at(90)), 360, "after the run: the last stop's")
    }

    func testTimesNeverRunBackwards() {
        // A is 10 minutes late, B reports on time: B's arrival would be before A's departure. It is not.
        let schedule = self.schedule([F.Stop(lon: 14, arr: nil, dep: 0, depDelay: 10), F.Stop(lon: 15, arr: 8, dep: 9, arrDelay: 0, depDelay: 0),
                                      F.Stop(lon: 16, arr: 40, dep: nil, arrDelay: 0)])
        XCTAssertEqual(schedule.stops[0].departure, F.at(10))
        XCTAssertGreaterThanOrEqual(schedule.stops[1].arrival, schedule.stops[0].departure)
        XCTAssertGreaterThanOrEqual(schedule.stops[1].departure, schedule.stops[1].arrival)
    }

    func testStopsWithoutCoordinateOrTimeAreLeftOut() {
        var noCoordinate = F.Stop(lon: 15, arr: 30, dep: 32)
        noCoordinate.hasCoordinate = false
        let schedule = self.schedule([F.Stop(lon: 14, arr: nil, dep: 0), noCoordinate, F.Stop(lon: 15.5, arr: nil, dep: nil), F.Stop(lon: 16, arr: 62, dep: nil)])
        XCTAssertEqual(schedule.stops.count, 2)
        XCTAssertNil(RadarProjection.position(of: self.schedule([F.Stop(lon: 14, arr: nil, dep: 0)]), anchor: nil, at: F.at(0)), "one stop has no path")
    }

    func testACancelledStopEventCarriesNoDelay() {
        var vehicle = F.vehicle("c", stops: [F.Stop(lon: 14, arr: nil, dep: 0, depDelay: 3), F.Stop(lon: 15, arr: 30, dep: 32, arrDelay: 20), F.Stop(lon: 16, arr: 62, dep: nil)])
        vehicle.stopovers[1].arrival?.isCancelled = true
        let schedule = RadarSchedule(vehicle)
        XCTAssertEqual(schedule.stops[1].arrivalDelay, 180, "the cancelled event's 20 minutes are ignored: A's 3 are carried")
    }

    // MARK: Position along the run

    func testBetweenTwoStopsThePositionIsInterpolatedByTime() throws {
        let schedule = self.schedule(F.threeStops())
        let halfway = try XCTUnwrap(RadarProjection.position(of: schedule, anchor: nil, at: F.at(15)))
        F.assertClose(halfway.coordinate, F.point(14.5), "15 of the 30 minutes: half way")
        XCTAssertEqual(halfway.phase, .between(0))
        XCTAssertEqual(halfway.path, .straight, "no route known: the straight line, and it says so")
        let quarter = try XCTUnwrap(RadarProjection.position(of: schedule, anchor: nil, at: F.at(7.5)))
        F.assertClose(quarter.coordinate, F.point(14.25))
        let second = try XCTUnwrap(RadarProjection.position(of: schedule, anchor: nil, at: F.at(47)))
        F.assertClose(second.coordinate, F.point(15.5), "B to C: 15 of 30 minutes")
        XCTAssertEqual(second.phase, .between(1))
    }

    func testStandingAtAStopBetweenArrivalAndDeparture() throws {
        let schedule = self.schedule(F.threeStops())
        for minute in [30.0, 31] {
            let projected = try XCTUnwrap(RadarProjection.position(of: schedule, anchor: nil, at: F.at(minute)))
            F.assertClose(projected.coordinate, F.point(15.0), "minute \(minute)")
            XCTAssertEqual(projected.phase, .atStop(1))
            XCTAssertEqual(projected.path, .atStop)
        }
        let leaving = try XCTUnwrap(RadarProjection.position(of: schedule, anchor: nil, at: F.at(32)))
        F.assertClose(leaving.coordinate, F.point(15.0), "at the departure it is still at the stop")
    }

    func testNotStartedAndEndedRunsAreNotOnTheMap() throws {
        let schedule = self.schedule(F.threeStops())
        XCTAssertNil(RadarProjection.position(of: schedule, anchor: nil, at: F.at(-1)), "before the first departure")
        XCTAssertNotNil(RadarProjection.position(of: schedule, anchor: nil, at: F.at(0)), "at the departure the train is at A")
        XCTAssertNotNil(RadarProjection.position(of: schedule, anchor: nil, at: F.at(62)), "at the last arrival it is at C")
        XCTAssertNil(RadarProjection.position(of: schedule, anchor: nil, at: F.at(62).addingTimeInterval(1)), "a second later the run is over")
        let end = try XCTUnwrap(RadarProjection.position(of: schedule, anchor: nil, at: F.at(62)))
        F.assertClose(end.coordinate, F.point(16.0))
        XCTAssertNil(end.bearing, "nothing to head for at the last stop")
    }

    func testTheKnownDelayShiftsTheWholeRun() throws {
        let late = self.schedule(F.threeStops(delay: 10))
        XCTAssertNil(RadarProjection.position(of: late, anchor: nil, at: F.at(-1)))
        let atMinute10 = try XCTUnwrap(RadarProjection.position(of: late, anchor: nil, at: F.at(10)))
        F.assertClose(atMinute10.coordinate, F.point(14.0), "10 minutes late: still at A at minute 10")
        let atMinute25 = try XCTUnwrap(RadarProjection.position(of: late, anchor: nil, at: F.at(25)))
        F.assertClose(atMinute25.coordinate, F.point(14.5), "half way at 25 instead of 15")
        XCTAssertNotNil(RadarProjection.position(of: late, anchor: nil, at: F.at(72)), "ends at 62 + 10")
        XCTAssertNil(RadarProjection.position(of: late, anchor: nil, at: F.at(73)))
    }

    func testBearingPointsTowardsTheNextStop() throws {
        let schedule = self.schedule(F.threeStops())
        let moving = try XCTUnwrap(RadarProjection.position(of: schedule, anchor: nil, at: F.at(15)))
        XCTAssertEqual(moving.bearing ?? -1, 90, accuracy: 0.5, "heading east")
        let standing = try XCTUnwrap(RadarProjection.position(of: schedule, anchor: nil, at: F.at(31)))
        XCTAssertEqual(standing.bearing ?? -1, 90, accuracy: 0.5, "standing at B: towards C")
    }

    // MARK: Anchor (the server's position at the time of its answer)

    func testProjectionPassesThroughTheServersPosition() throws {
        // The server has the train a little behind the timetable's straight line: 12 minutes into the A-B leg it is at 14.3 (timetable: 14.4).
        let schedule = self.schedule(F.threeStops())
        let anchor = try XCTUnwrap(RadarProjection.validatedAnchor(for: schedule, time: F.at(12), coordinate: F.point(14.3)))
        let at = try XCTUnwrap(RadarProjection.position(of: schedule, anchor: anchor, at: F.at(12)))
        F.assertClose(at.coordinate, F.point(14.3), "at the time of the answer the projection is the server's position")
        // Continuous around it, and still reaching B on time.
        let before = try XCTUnwrap(RadarProjection.position(of: schedule, anchor: anchor, at: F.at(11.9)))
        let after = try XCTUnwrap(RadarProjection.position(of: schedule, anchor: anchor, at: F.at(12.1)))
        XCTAssertLessThan(before.coordinate.distanceKm(to: at.coordinate), 0.5)
        XCTAssertLessThan(after.coordinate.distanceKm(to: at.coordinate), 0.5)
        let arrival = try XCTUnwrap(RadarProjection.position(of: schedule, anchor: anchor, at: F.at(30)))
        F.assertClose(arrival.coordinate, F.point(15.0), "the arrival is still on time")
        let departure = try XCTUnwrap(RadarProjection.position(of: schedule, anchor: anchor, at: F.at(0)))
        F.assertClose(departure.coordinate, F.point(14.0))
        // Moving forward in time never moves the train backwards.
        var last = -1.0
        for step in 0...60 {
            guard let p = RadarProjection.position(of: schedule, anchor: anchor, at: F.at(Double(step))) else { continue }
            XCTAssertGreaterThanOrEqual(p.coordinate.longitude, last - 1e-9, "minute \(step)")
            last = p.coordinate.longitude
        }
    }

    func testAnAnchorThatDoesNotFitIsRejected() {
        let schedule = self.schedule(F.threeStops())
        XCTAssertNil(RadarProjection.validatedAnchor(for: schedule, time: F.at(12), coordinate: F.point(14.3, lat: 48.5)), "55 km off the line")
        XCTAssertNil(RadarProjection.validatedAnchor(for: schedule, time: F.at(12), coordinate: F.point(13.5)), "before the stop it left")
        XCTAssertNil(RadarProjection.validatedAnchor(for: schedule, time: F.at(12), coordinate: F.point(15.6)), "beyond the stop it heads for")
        XCTAssertNotNil(RadarProjection.validatedAnchor(for: schedule, time: F.at(12), coordinate: F.point(14.3, lat: 48.02)), "2 km off the line is track curvature")
        XCTAssertNil(RadarProjection.validatedAnchor(for: schedule, time: F.at(31), coordinate: F.point(15.0)), "standing at a stop: the stop is exact, no anchor")
        XCTAssertNil(RadarProjection.validatedAnchor(for: schedule, time: F.at(70), coordinate: F.point(16.0)), "after the run")
        XCTAssertNil(RadarProjection.validatedAnchor(for: schedule, time: F.at(12), coordinate: GeoPoint(latitude: .nan, longitude: 14.3)))
    }

    func testATrainHeldAtItsFirstStopStaysThereOnlyBecauseTheAnswerSaidSo() throws {
        let schedule = self.schedule([F.Stop(lon: 14, arr: nil, dep: 25), F.Stop(lon: 15, arr: 55, dep: nil)])
        // Without an answer that puts it at A, a train that has not started is not on the map.
        XCTAssertNil(RadarProjection.position(of: schedule, anchor: nil, at: F.at(15)))
        // The answer for minute 10 has it standing at A: held there until it leaves.
        let anchor = try XCTUnwrap(RadarProjection.validatedAnchor(for: schedule, time: F.at(10), coordinate: F.point(14.0)))
        XCTAssertNil(RadarProjection.position(of: schedule, anchor: anchor, at: F.at(9)), "before the answer's time it is not held")
        let held = try XCTUnwrap(RadarProjection.position(of: schedule, anchor: anchor, at: F.at(15)))
        F.assertClose(held.coordinate, F.point(14.0))
        let moving = try XCTUnwrap(RadarProjection.position(of: schedule, anchor: anchor, at: F.at(40)))
        F.assertClose(moving.coordinate, F.point(14.5), "halfway at 40: half of 25 to 55")
        // Far from the first stop it was not held there: no anchor.
        XCTAssertNil(RadarProjection.validatedAnchor(for: schedule, time: F.at(10), coordinate: F.point(14.5)))
    }

    // MARK: Route polyline

    func testAlongThePolylineInsteadOfTheStraightLine() throws {
        // A to B by a detour over a point 55 km north: half the time is the top of the detour, not the middle of the straight line.
        let route = try XCTUnwrap(RadarRoute([F.point(14.0), F.point(14.5, lat: 48.5), F.point(15.0), F.point(16.0)]))
        let schedule = self.schedule(F.threeStops())
        let projected = try XCTUnwrap(RadarProjection.position(of: schedule, anchor: nil, at: F.at(15), route: route))
        XCTAssertEqual(projected.path, .polyline)
        F.assertClose(projected.coordinate, GeoPoint(latitude: 48.5, longitude: 14.5), accuracy: 1e-3, "the detour's top")
        let straight = try XCTUnwrap(RadarProjection.position(of: schedule, anchor: nil, at: F.at(15)))
        XCTAssertEqual(straight.path, .straight)
        XCTAssertGreaterThan(projected.coordinate.distanceKm(to: straight.coordinate), 50)
    }

    func testAPolylineThatIsNotTheRouteIsIgnored() throws {
        // The polyline runs 55 km north of the stops: not the route between them.
        let route = try XCTUnwrap(RadarRoute([F.point(14.0, lat: 48.5), F.point(16.0, lat: 48.5)]))
        let projected = try XCTUnwrap(RadarProjection.position(of: self.schedule(F.threeStops()), anchor: nil, at: F.at(15), route: route))
        XCTAssertEqual(projected.path, .straight)
        F.assertClose(projected.coordinate, F.point(14.5))
        XCTAssertNil(RadarRoute([F.point(14)]), "one point is no route")
    }

    func testAReversedPolylineFallsBackToTheStraightLine() throws {
        let route = try XCTUnwrap(RadarRoute([F.point(16.0), F.point(15.0), F.point(14.0)]))
        let projected = try XCTUnwrap(RadarProjection.position(of: self.schedule(F.threeStops()), anchor: nil, at: F.at(15), route: route))
        XCTAssertEqual(projected.path, .straight, "B lies before A along this polyline")
    }

    // MARK: Midnight and summer time (Europe/Vienna)

    func testARunAcrossMidnightIsProjectedByTheAbsoluteClock() throws {
        let departure = F.vienna(2026, 11, 12, 23, 50)
        let arrival = F.vienna(2026, 11, 13, 0, 20)
        let vehicle = RadarVehicle(tripID: "night", coordinate: F.point(14.0), stopovers: [
            Stopover(location: Location(lid: "a", name: "A", coordinate: F.point(14.0)), departure: StopEvent(planned: departure)),
            Stopover(location: Location(lid: "b", name: "B", coordinate: F.point(15.0)), arrival: StopEvent(planned: arrival)),
        ])
        let schedule = RadarSchedule(vehicle)
        let halfway = try XCTUnwrap(RadarProjection.position(of: schedule, anchor: nil, at: F.vienna(2026, 11, 13, 0, 5)))
        F.assertClose(halfway.coordinate, F.point(14.5), "00:05 is half way between 23:50 and 00:20")
        XCTAssertNil(RadarProjection.position(of: schedule, anchor: nil, at: F.vienna(2026, 11, 13, 0, 21)))
    }

    func testARunAcrossTheSwitchToSummerTimeTakesTheRealElapsedTime() throws {
        // 2026-03-29: 02:00 CET becomes 03:00 CEST. Leaves 01:30 CET, arrives 03:30 CEST: one hour on the clock of the train, not two.
        let departure = F.vienna(2026, 3, 29, 1, 30)
        let arrival = F.vienna(2026, 3, 29, 3, 30)
        XCTAssertEqual(arrival.timeIntervalSince(departure), 3600, "one real hour")
        let vehicle = RadarVehicle(tripID: "dst", coordinate: F.point(14.0), stopovers: [
            Stopover(location: Location(lid: "a", name: "A", coordinate: F.point(14.0)), departure: StopEvent(planned: departure)),
            Stopover(location: Location(lid: "b", name: "B", coordinate: F.point(15.0)), arrival: StopEvent(planned: arrival)),
        ])
        let schedule = RadarSchedule(vehicle)
        let halfway = try XCTUnwrap(RadarProjection.position(of: schedule, anchor: nil, at: departure.addingTimeInterval(1800)))
        F.assertClose(halfway.coordinate, F.point(14.5), "30 minutes after the departure, which is 03:00 CEST on the wall clock")
        XCTAssertEqual(Calendar.vienna.component(.hour, from: departure.addingTimeInterval(1800)), 3)
    }

    func testARunAcrossTheSwitchToWinterTimeTakesTheRealElapsedTime() throws {
        // 2026-10-25: 03:00 CEST becomes 02:00 CET. Leaves 02:30 CEST (first), arrives 02:30 CET (second): one real hour.
        let departure = Date(timeIntervalSince1970: 1_792_888_200)   // 02:30 CEST = 00:30 UTC
        let arrival = departure.addingTimeInterval(3600)               // 02:30 CET = 01:30 UTC
        let vehicle = RadarVehicle(tripID: "dst2", coordinate: F.point(14.0), stopovers: [
            Stopover(location: Location(lid: "a", name: "A", coordinate: F.point(14.0)), departure: StopEvent(planned: departure)),
            Stopover(location: Location(lid: "b", name: "B", coordinate: F.point(15.0)), arrival: StopEvent(planned: arrival)),
        ])
        let halfway = try XCTUnwrap(RadarProjection.position(of: RadarSchedule(vehicle), anchor: nil, at: departure.addingTimeInterval(1800)))
        F.assertClose(halfway.coordinate, F.point(14.5))
    }

    func testMalformedInputNeverTraps() {
        let empty = RadarSchedule()
        XCTAssertNil(RadarProjection.position(of: empty, anchor: nil, at: F.t0))
        XCTAssertNil(RadarProjection.validatedAnchor(for: empty, time: F.t0, coordinate: F.point(14)))
        let odd = RadarSchedule(stops: [
            RadarScheduleStop(coordinate: F.point(14), arrival: F.at(10), departure: F.at(10)),
            RadarScheduleStop(coordinate: F.point(15), arrival: F.at(10), departure: F.at(10)),
        ])
        XCTAssertNotNil(RadarProjection.position(of: odd, anchor: nil, at: F.at(10)), "two stops at the same minute: no division by zero")
    }
}
