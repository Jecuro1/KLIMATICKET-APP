import XCTest
@testable import KlimaCore

final class CockpitFeedTests: XCTestCase {
    typealias F = CockpitFixtures

    private let line = Line(name: "RJX 66", fullName: "RJX 66", category: "RJX", categoryShort: "RJX", trainNumber: "66", productClass: 1, mode: .train)

    /// The radar's answer for the fixture train: the position and the stops (all four in the fixture), at a longitude between B and C.
    private func vehicle(lon: Double, stops: [F.Stop] = F.fourStops(), cancelled: Bool = false) -> RadarVehicle {
        RadarVehicle(tripID: "T1", line: line, direction: "Ziel", coordinate: F.point(lon), stopovers: F.stopovers(stops), isCancelled: cancelled)
    }

    private func details(stops: [F.Stop] = F.fourStops(), polyline: [GeoPoint]? = F.straightPolyline(), cancelled: Bool = false) -> TripDetails {
        TripDetails(tripID: "T1", line: line, direction: "Ziel", stopovers: F.stopovers(stops), polyline: polyline, isCancelled: cancelled)
    }

    private func snapshot(_ vehicles: [RadarVehicle]) -> RadarSnapshot { RadarSnapshot(vehicles: vehicles) }

    private func at(_ seconds: Double) -> Date { F.at(47).addingTimeInterval(seconds) }

    // MARK: Merge

    func testFresherRadarEventsReplaceTheDetails() {
        var old = F.fourStops(); old[2].arrDelay = 2; old[2].depDelay = 2
        var new = F.fourStops(); new[2].arrDelay = 7; new[2].depDelay = 7
        let merged = CockpitMerge.stopovers(details: F.stopovers(old), radar: F.stopovers(new))
        XCTAssertEqual(merged[2].arrival?.delaySeconds, 420)
        XCTAssertEqual(merged[2].departure?.delaySeconds, 420)
        XCTAssertEqual(merged[1].arrival?.delaySeconds, nil, "B has no report in either")
        XCTAssertEqual(merged.count, 4, "the details' stops stay, whatever the radar lists")
    }

    func testARadarEventWithoutRealtimeKeepsTheDelayOfTheDetails() {
        var old = F.fourStops(); old[2].arrDelay = 6
        let merged = CockpitMerge.stopovers(details: F.stopovers(old), radar: F.stopovers(F.fourStops()))
        XCTAssertEqual(merged[2].arrival?.delaySeconds, 360)
    }

    func testACancellationInTheRadarWins() {
        var new = F.fourStops(); new[2].arrCancelled = true; new[2].depCancelled = true
        let merged = CockpitMerge.stopovers(details: F.stopovers(F.fourStops(delay: 0)), radar: F.stopovers(new))
        XCTAssertTrue(merged[2].arrival?.isCancelled == true)
    }

    func testStopsAreMatchedByIdExtIdOrPlace() {
        let a = Location(lid: "x", extId: "1", name: "A", coordinate: F.point(14.0))
        XCTAssertTrue(CockpitMerge.sameStop(a, Location(lid: "x", extId: nil, name: "other")))
        XCTAssertTrue(CockpitMerge.sameStop(a, Location(lid: "y", extId: "1", name: "other")))
        XCTAssertTrue(CockpitMerge.sameStop(a, Location(lid: "y", extId: "2", name: "other", coordinate: F.point(14.0005))))
        XCTAssertFalse(CockpitMerge.sameStop(a, Location(lid: "y", extId: "2", name: "other", coordinate: F.point(14.01))))
    }

    func testAnEventForAnotherPlannedTimeIsNotReplaced() {
        var shifted = F.fourStops(); shifted[2].arr = 70; shifted[2].arrDelay = 3
        let merged = CockpitMerge.stopovers(details: F.stopovers(F.fourStops(delay: 0)), radar: F.stopovers(shifted))
        XCTAssertEqual(merged[2].arrival?.planned, F.at(62))
    }

    // MARK: Request plan

    func testTheBoxIsAroundTheTrainAndAtLeastTenKilometresWide() {
        let box = CockpitRequestPlan.box(around: F.point(15.0), ageSeconds: 0, speedKmh: 100)
        XCTAssertTrue(box.isValid)
        XCTAssertEqual(box.center.latitude, 48.0, accuracy: 1e-9)
        XCTAssertEqual(box.center.longitude, 15.0, accuracy: 1e-9)
        XCTAssertEqual((box.north - box.south) * 110.574, 10, accuracy: 0.1)
        XCTAssertEqual((box.east - box.west) * 74.5, 10, accuracy: 0.2)
    }

    func testTheBoxGrowsWithTheAgeAndStaysBounded() {
        let young = CockpitRequestPlan.box(around: F.point(15.0), ageSeconds: 20, speedKmh: 200)
        let old = CockpitRequestPlan.box(around: F.point(15.0), ageSeconds: 110, speedKmh: 200)
        XCTAssertGreaterThan(old.north - old.south, young.north - young.south)
        let huge = CockpitRequestPlan.box(around: F.point(15.0), ageSeconds: 100_000, speedKmh: 300)
        XCTAssertEqual((huge.north - huge.south) * 110.574, 60, accuracy: 0.1, "30 km each way at most")
        // The train must be inside the box after a full refresh interval at speed: 250 km/h for 20 s is 1.4 km.
        XCTAssertGreaterThan((young.north - young.south) * 110.574 / 2, 1.4)
    }

    func testTheProductFilterIsTheTrainsOwnClass() {
        XCTAssertEqual(CockpitRequestPlan.products(for: line), ProductMask(rawValue: 1))
        XCTAssertEqual(CockpitRequestPlan.products(for: Line(name: "REX 51", productClass: 16)), ProductMask(rawValue: 16))
        XCTAssertEqual(CockpitRequestPlan.products(for: Line(name: "X", productClass: 0)), .rail)
        XCTAssertEqual(CockpitRequestPlan.products(for: nil), .rail)
    }

    // MARK: Scheduler

    func testTheFirstRoundAsksThePositionThenTheDetails() {
        var scheduler = CockpitScheduler()
        XCTAssertEqual(scheduler.next(now: at(0)), .request(.position))
        XCTAssertEqual(scheduler.next(now: at(0.5)), .request(.details))
        // Both are on their way: nothing more until one answers or its interval is over.
        XCTAssertEqual(scheduler.next(now: at(1)), .wait(until: at(0).addingTimeInterval(90)), "both are on their way: nothing before one answers or times out")
    }

    func testThePositionComesEveryTwentySeconds() {
        var scheduler = CockpitScheduler()
        _ = scheduler.next(now: at(0)); _ = scheduler.next(now: at(0))
        scheduler.recordAnswer(.position, at: at(2))
        scheduler.recordAnswer(.details, at: at(3))
        XCTAssertEqual(scheduler.next(now: at(10)), .wait(until: at(20)))
        XCTAssertEqual(scheduler.next(now: at(20)), .request(.position))
        scheduler.recordAnswer(.position, at: at(22))
        XCTAssertEqual(scheduler.next(now: at(30)), .wait(until: at(40)))
    }

    func testDetailsCometheNextTimeAfterThreeMinutes() {
        var scheduler = CockpitScheduler()
        _ = scheduler.next(now: at(0)); _ = scheduler.next(now: at(0))
        scheduler.recordAnswer(.position, at: at(1))
        scheduler.recordAnswer(.details, at: at(1))
        var requests = 0
        var details = 0
        var now = at(2)
        while now < at(400) {
            switch scheduler.next(now: now) {
            case .request(let kind):
                requests += 1
                if kind == .details { details += 1 }
                scheduler.recordAnswer(kind, at: now)
            case .wait: break
            }
            now = now.addingTimeInterval(1)
        }
        XCTAssertEqual(details, 2, "at about +181 s and +362 s")
        XCTAssertEqual(requests - details, 19, "one position every 20 s")
    }

    func testTheBudgetOfTheCockpitIsAboutThreeAndAHalfRequestsAMinute() {
        var scheduler = CockpitScheduler()
        var count = 0
        var now = at(0)
        while now < at(600) {
            if case .request(let kind) = scheduler.next(now: now) { count += 1; scheduler.recordAnswer(kind, at: now) }
            now = now.addingTimeInterval(1)
        }
        XCTAssertLessThanOrEqual(Double(count) / 10, 3.7, "requests per minute over ten minutes")
        XCTAssertGreaterThanOrEqual(Double(count) / 10, 3.0)
    }

    func testAFailureBacksOffAndRateLimitPausesBoth() {
        var scheduler = CockpitScheduler()
        _ = scheduler.next(now: at(0)); _ = scheduler.next(now: at(0))
        scheduler.recordFailure(.position, error: LiveError.offline, at: at(1))
        scheduler.recordAnswer(.details, at: at(1))
        XCTAssertEqual(scheduler.next(now: at(10)), .wait(until: at(20)), "the position is due at 20 s anyway: the backoff of 15 s is shorter")
        XCTAssertEqual(scheduler.failures(.position), 1)
        scheduler.recordFailure(.position, error: LiveError.offline, at: at(20))
        scheduler.recordFailure(.position, error: LiveError.offline, at: at(21))
        XCTAssertEqual(scheduler.next(now: at(30)), .wait(until: at(81)), "the third failure: 60 s")
        scheduler.recordFailure(.position, error: LiveError.rateLimited(.oebbHafas, retryAfter: 45), at: at(60))
        guard case .wait(let until) = scheduler.next(now: at(61)) else { return XCTFail("paused") }
        XCTAssertGreaterThanOrEqual(until, at(105))
    }

    func testLostMeansSlowerAsking() {
        var scheduler = CockpitScheduler()
        _ = scheduler.next(now: at(0)); _ = scheduler.next(now: at(0))
        scheduler.recordAnswer(.position, at: at(1))
        scheduler.recordAnswer(.details, at: at(1))
        XCTAssertEqual(scheduler.next(now: at(25), lost: true), .wait(until: at(30)))
        XCTAssertEqual(scheduler.next(now: at(30), lost: true), .request(.position))
    }

    func testLostMeansDetailsMoreOften() {
        var scheduler = CockpitScheduler()
        _ = scheduler.next(now: at(0)); _ = scheduler.next(now: at(0))
        scheduler.recordAnswer(.position, at: at(1))
        scheduler.recordAnswer(.details, at: at(1))
        XCTAssertEqual(scheduler.next(now: at(40), lost: true), .request(.position))
        XCTAssertEqual(scheduler.next(now: at(46), lost: true), .request(.details), "45 s instead of 3 minutes")
    }

    func testNothingIsAskedOnceTheRunHasEnded() {
        var scheduler = CockpitScheduler()
        XCTAssertEqual(scheduler.next(now: at(0), ended: true), .wait(until: .distantFuture))
    }

    func testARequestThatNeverReportsBackFreesItsSlot() {
        var scheduler = CockpitScheduler()
        XCTAssertEqual(scheduler.next(now: at(0)), .request(.position))
        XCTAssertEqual(scheduler.next(now: at(0)), .request(.details))
        scheduler.recordAnswer(.details, at: at(1))
        XCTAssertEqual(scheduler.next(now: at(30)), .wait(until: at(0).addingTimeInterval(90)), "the position is still on its way")
        XCTAssertEqual(scheduler.next(now: at(89)), .wait(until: at(0).addingTimeInterval(90)))
        XCTAssertEqual(scheduler.next(now: at(91)), .request(.position))
    }

    func testCancelledMeansDueAgain() {
        var scheduler = CockpitScheduler()
        XCTAssertEqual(scheduler.next(now: at(0)), .request(.position))
        scheduler.recordCancelled(.position)
        XCTAssertEqual(scheduler.next(now: at(1)), .request(.position))
    }

    func testRefreshNowAsksAtOnceButNotTwice() {
        var scheduler = CockpitScheduler()
        _ = scheduler.next(now: at(0)); _ = scheduler.next(now: at(0))
        scheduler.recordAnswer(.position, at: at(1))
        scheduler.recordAnswer(.details, at: at(1))
        XCTAssertNotEqual(scheduler.next(now: at(5)), .request(.position))
        scheduler.refreshNow()
        XCTAssertEqual(scheduler.next(now: at(6)), .request(.position))
        XCTAssertNotEqual(scheduler.next(now: at(7)), .request(.position), "the position is on its way")
    }

    // MARK: Feed

    func testTheFirstFrameIsProvisionalWithTheRadarsStops() throws {
        let feed = CockpitFeed(vehicle: vehicle(lon: 15.5), seenAt: at(0), now: at(2))
        let frame = try XCTUnwrap(feed.frame(now: at(2)))
        XCTAssertTrue(frame.isProvisional)
        XCTAssertNil(frame.km)
        XCTAssertEqual(frame.summary?.nextStop, "Halt 2")
        XCTAssertEqual(frame.state, .following)
        XCTAssertEqual(frame.coordinate.longitude, 15.5, accuracy: 1e-6)
    }

    func testDetailsMakeTheRouteComplete() throws {
        var feed = CockpitFeed(vehicle: vehicle(lon: 15.5), seenAt: at(0), now: at(2))
        feed.applyDetails(details(), at: at(3))
        let frame = try XCTUnwrap(feed.frame(now: at(3)))
        XCTAssertFalse(frame.isProvisional)
        let km = try XCTUnwrap(frame.km)
        let route = try XCTUnwrap(frame.route)
        XCTAssertEqual(km, route.stops[1].km + 0.5 * 74.5, accuracy: 0.4)
        XCTAssertFalse(route.isStraightLine)
        XCTAssertEqual(frame.summary?.progress ?? -1, 0.5 * 74.5 / route.runKm + route.stops[1].km / route.runKm - route.firstKm / route.runKm, accuracy: 0.02)
    }

    func testStartingWithCachedDetails() throws {
        let feed = CockpitFeed(vehicle: vehicle(lon: 15.5), seenAt: at(0), now: at(2), details: details(), detailsAt: at(-30))
        XCTAssertFalse(try XCTUnwrap(feed.frame(now: at(2))).isProvisional)
    }

    func testTheMarkerMovesBetweenTwoAnswersWithTheRadarsLag() throws {
        var feed = CockpitFeed(vehicle: vehicle(lon: 15.50), seenAt: at(0), now: at(0), details: details(), detailsAt: at(0))
        feed.applyRadar(snapshot([vehicle(lon: 15.50 + 0.7 / 74.5)]), requestedAt: at(20))   // 700 m in 20 s
        // At +30 s the marker is 20 s behind the clock: at +10 s of the interval, halfway.
        let half = try XCTUnwrap(feed.frame(now: at(30)))
        XCTAssertEqual(half.coordinate.longitude, 15.50 + 0.35 / 74.5, accuracy: 0.0005)
        XCTAssertTrue(half.isEstimate)
        // At +40 s it has reached the latest answer, and holds there.
        let done = try XCTUnwrap(feed.frame(now: at(40)))
        XCTAssertEqual(done.coordinate.longitude, 15.50 + 0.7 / 74.5, accuracy: 0.0002)
        XCTAssertFalse(done.isEstimate)
        let later = try XCTUnwrap(feed.frame(now: at(55)))
        XCTAssertEqual(later.coordinate.longitude, done.coordinate.longitude, accuracy: 1e-6)
    }

    func testTheSpeedComesFromTwoAnswers() throws {
        var feed = CockpitFeed(vehicle: vehicle(lon: 15.50), seenAt: at(0), now: at(0), details: details(), detailsAt: at(0))
        XCTAssertEqual(feed.frame(now: at(1))?.speed, .unknown)
        feed.applyRadar(snapshot([vehicle(lon: 15.50 + 0.7 / 74.5)]), requestedAt: at(20))
        let kmh = try XCTUnwrap(feed.frame(now: at(21))?.speed.kmh)
        XCTAssertEqual(kmh, 126, accuracy: 4)
        XCTAssertEqual(feed.frame(now: at(21))?.summary?.speed.kmh ?? -1, kmh, accuracy: 1e-9)
    }

    func testTheFreshRadarDelayReachesTheSummary() throws {
        var feed = CockpitFeed(vehicle: vehicle(lon: 15.5), seenAt: at(0), now: at(0), details: details(), detailsAt: at(0))
        XCTAssertEqual(feed.frame(now: at(1))?.summary?.delayState, .unknown)
        var late = F.fourStops(); late[2].arrDelay = 8; late[2].depDelay = 8; late[3].arrDelay = 8
        feed.applyRadar(snapshot([vehicle(lon: 15.5, stops: late)]), requestedAt: at(20))
        let summary = try XCTUnwrap(feed.frame(now: at(21))?.summary)
        XCTAssertEqual(summary.delaySeconds, 480)
        XCTAssertEqual(summary.delayState, .late)
        XCTAssertEqual(summary.eta, F.at(70))
    }

    func testOlderDetailsDoNotReplaceNewerRadarDelays() throws {
        var feed = CockpitFeed(vehicle: vehicle(lon: 15.5), seenAt: at(0), now: at(0))
        var late = F.fourStops(); late[2].arrDelay = 8; late[2].depDelay = 8
        feed.applyRadar(snapshot([vehicle(lon: 15.5, stops: late)]), requestedAt: at(20))
        // The details were asked for at +5 s and arrive now, with an older delay for C.
        var old = F.fourStops(); old[2].arrDelay = 1; old[2].depDelay = 1
        feed.applyDetails(details(stops: old), at: at(5))
        XCTAssertEqual(feed.frame(now: at(25))?.summary?.delaySeconds, 480)
    }

    func testAnAnswerWithoutTheTrainAndTheStateAfterwards() throws {
        var feed = CockpitFeed(vehicle: vehicle(lon: 15.5), seenAt: at(0), now: at(0), details: details(), detailsAt: at(0))
        feed.applyRadar(snapshot([]), requestedAt: at(100))
        feed.tick(now: at(110))
        XCTAssertEqual(feed.session.state, .following, "less than two minutes without a position")
        feed.tick(now: at(121))
        XCTAssertEqual(feed.session.state, .lost)
        XCTAssertEqual(feed.session.lostReason(now: at(121)), .notListed, "the service answers, without the train")
        XCTAssertEqual(feed.session.lostReason(now: at(300)), .noAnswers, "and then it stops answering")
        let frame = try XCTUnwrap(feed.frame(now: at(121)))
        XCTAssertEqual(frame.state, .lost, "the marker stays where it was")
        feed.applyRadar(snapshot([vehicle(lon: 15.52)]), requestedAt: at(130))
        XCTAssertEqual(feed.frame(now: at(131))?.state, .following)
    }

    func testDetailsPositionStandsInWhenTheRadarHasNoneForAWhile() throws {
        var feed = CockpitFeed(vehicle: vehicle(lon: 15.5), seenAt: at(0), now: at(0))
        var trip = details()
        trip.currentPosition = F.point(15.52)
        // 20 s after the radar's position: the radar is fresh, the position of the details is not used.
        feed.applyDetails(trip, at: at(20))
        XCTAssertEqual(try XCTUnwrap(feed.frame(now: at(300))).coordinate.longitude, 15.5, accuracy: 1e-4)
        // 100 s after it: the train was missing from the radar, the details' position is taken.
        var second = CockpitFeed(vehicle: vehicle(lon: 15.5), seenAt: at(0), now: at(0))
        second.applyDetails(trip, at: at(100))
        XCTAssertEqual(try XCTUnwrap(second.frame(now: at(300))).coordinate.longitude, 15.52, accuracy: 1e-4)
        second.tick(now: at(101))
        XCTAssertEqual(second.session.state, .following, "a position is a position: not lost")
        // A details answer without a position of its own changes nothing about the position.
        var third = CockpitFeed(vehicle: vehicle(lon: 15.5), seenAt: at(0), now: at(0))
        third.applyDetails(details(), at: at(100))
        XCTAssertEqual(try XCTUnwrap(third.frame(now: at(300))).coordinate.longitude, 15.5, accuracy: 1e-4)
    }

    func testAnOlderAnswerIsIgnored() throws {
        var feed = CockpitFeed(vehicle: vehicle(lon: 15.5), seenAt: at(0), now: at(0), details: details(), detailsAt: at(0))
        feed.applyRadar(snapshot([vehicle(lon: 15.6)]), requestedAt: at(20))
        feed.applyRadar(snapshot([vehicle(lon: 15.4)]), requestedAt: at(10))   // arrived late
        let frame = try XCTUnwrap(feed.frame(now: at(60)))
        XCTAssertEqual(frame.coordinate.longitude, 15.6, accuracy: 1e-4)
    }

    func testTheRunEndsAtTheLastStop() throws {
        let base = F.at(94)
        var feed = CockpitFeed(vehicle: vehicle(lon: 16.99), seenAt: base, now: base, details: details(), detailsAt: base)
        feed.applyRadar(snapshot([vehicle(lon: 17.0)]), requestedAt: base.addingTimeInterval(20))
        feed.tick(now: base.addingTimeInterval(30))
        XCTAssertNotEqual(feed.session.state, .ended, "the marker is still on its way to the last stop")
        feed.tick(now: base.addingTimeInterval(41))   // the marker is 20 s behind the clock: now it is at the last stop
        XCTAssertEqual(feed.session.state, .ended)
        XCTAssertEqual(feed.frame(now: base.addingTimeInterval(42))?.state, .ended)
    }

    func testATrainThatLeavesTheRadarNearItsEndHasArrived() {
        let base = F.at(93)
        var feed = CockpitFeed(vehicle: vehicle(lon: 16.97), seenAt: base, now: base, details: details(), detailsAt: base)
        feed.applyRadar(snapshot([]), requestedAt: base.addingTimeInterval(20))   // taken off the radar, 2.2 km before the last stop
        feed.tick(now: base.addingTimeInterval(30))
        XCTAssertNotEqual(feed.session.state, .ended, "only a moment without the train")
        feed.tick(now: base.addingTimeInterval(60))
        XCTAssertEqual(feed.session.state, .ended)
    }

    func testATrainThatLeavesTheRadarInTheMiddleIsLostNotEnded() {
        var feed = CockpitFeed(vehicle: vehicle(lon: 15.5), seenAt: F.at(40), now: F.at(40), details: details(), detailsAt: F.at(40))
        feed.applyRadar(snapshot([]), requestedAt: F.at(41))
        feed.tick(now: F.at(41).addingTimeInterval(60))
        XCTAssertNotEqual(feed.session.state, .ended)
        feed.tick(now: F.at(40).addingTimeInterval(125))
        XCTAssertEqual(feed.session.state, .lost)
    }

    func testRequestBoxContainsTheTrainAndItsEstimate() throws {
        var feed = CockpitFeed(vehicle: vehicle(lon: 15.50), seenAt: at(0), now: at(0), details: details(), detailsAt: at(0))
        feed.applyRadar(snapshot([vehicle(lon: 15.50 + 0.7 / 74.5)]), requestedAt: at(20))
        let box = try XCTUnwrap(feed.requestBox(now: at(35)))
        let frame = try XCTUnwrap(feed.frame(now: at(35)))
        XCTAssertTrue(box.isValid)
        XCTAssertTrue(box.contains(frame.coordinate))
        XCTAssertTrue(box.contains(F.point(15.50 + 0.7 / 74.5)))
        XCTAssertEqual(feed.products, ProductMask(rawValue: 1))
    }

    func testTheCameraInputFollowsTheRouteAndHoldsStillAtAStop() throws {
        var feed = CockpitFeed(vehicle: vehicle(lon: 15.5), seenAt: at(0), now: at(0), details: details(), detailsAt: at(0))
        feed.applyRadar(snapshot([vehicle(lon: 15.5 + 0.7 / 74.5)]), requestedAt: at(20))
        let frame = try XCTUnwrap(feed.frame(now: at(45)))
        let input = frame.cameraInput(mode: .follow, reduceMotion: false)
        XCTAssertNotNil(input.path)
        XCTAssertNotNil(input.trainKm)
        XCTAssertEqual(try XCTUnwrap(frame.heading), 90, accuracy: 1)
        // Standing at B (the stop's own times): the camera input says 0 km/h.
        let stand = CockpitFeed(vehicle: vehicle(lon: 15.0), seenAt: F.at(31), now: F.at(31), details: details(), detailsAt: F.at(31))
        let held = try XCTUnwrap(stand.frame(now: F.at(31).addingTimeInterval(1)))
        XCTAssertEqual(held.cameraInput(mode: .follow, reduceMotion: false).speedKmh, 0)
        XCTAssertEqual(held.summary?.phase, .atStop(stop: "Halt 1", departure: F.at(32)))
    }

    func testTheMarkerIsDrawnOnTheRouteWhenItIsNearIt() throws {
        // 100 m north of the line: the marker is put on it. 1 km north: it stays where the server put it.
        var feed = CockpitFeed(vehicle: RadarVehicle(tripID: "T1", line: line, direction: "Ziel", coordinate: GeoPoint(latitude: 48.0009, longitude: 15.5),
                                                      stopovers: F.stopovers(F.fourStops())), seenAt: at(0), now: at(0), details: details(), detailsAt: at(0))
        XCTAssertEqual(try XCTUnwrap(feed.frame(now: at(1))).coordinate.latitude, 48.0, accuracy: 1e-6)
        feed = CockpitFeed(vehicle: RadarVehicle(tripID: "T1", line: line, direction: "Ziel", coordinate: GeoPoint(latitude: 48.009, longitude: 15.5),
                                                  stopovers: F.stopovers(F.fourStops())), seenAt: at(0), now: at(0), details: details(), detailsAt: at(0))
        XCTAssertEqual(try XCTUnwrap(feed.frame(now: at(1))).coordinate.latitude, 48.009, accuracy: 1e-6)
    }

    func testRouteLinesSplitAtTheTrain() throws {
        let route = F.route(F.fourStops(delay: 0))
        let km = (route.stops[1].km + route.stops[2].km) / 2
        let lines = route.lines(atKm: km)
        XCTAssertGreaterThan(lines.passed.count, 3)
        F.assertClose(lines.passed.last, route.point(atKm: km))
        XCTAssertEqual(lines.ahead.map(\.id), [1, 2], "the leg the train is on, cut at the train, and the last one")
        F.assertClose(lines.ahead.first?.points.first, route.point(atKm: km))
        F.assertClose(lines.ahead.last?.points.last, route.stops[3].coordinate, accuracy: 1e-3)
        XCTAssertTrue(lines.ahead.allSatisfy { $0.state == .onTime })
        let end = route.lines(atKm: route.lastKm)
        XCTAssertTrue(end.ahead.isEmpty)
    }
}
