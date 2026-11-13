import XCTest
@testable import KlimaCore

/// Radar time travel: the timeline of snapshots (docs/RADAR_TIMETRAVEL.md §3). Interpolation between neighbouring snapshots per trip,
/// vehicles that start later or end earlier, dedup of snapshots, bounded memory. Synthetic runs, no network.
final class RadarTimelineTests: XCTestCase {
    private typealias F = RadarTimeFixtures

    /// The run of `RadarTimeFixtures.threeStops`, with the server's position at minute `at` taken from the timetable (so the answer is consistent).
    private func answer(_ id: String, at minute: Double, delay: Double? = nil, stops: [F.Stop]? = nil) -> RadarVehicle {
        let stops = stops ?? F.threeStops(delay: delay)
        let schedule = RadarSchedule(F.vehicle(id, stops: stops))
        let position = RadarProjection.position(of: schedule, anchor: nil, at: F.at(minute))?.coordinate ?? F.point(stops[0].lon)
        return F.vehicle(id, stops: stops, position: position)
    }

    // MARK: One answer, forward

    func testAnAnswerIsProjectedForwardAndIsExactAtItsOwnTime() throws {
        var timeline = RadarTimeline()
        timeline.addFrame([answer("a", at: 12)], time: F.at(12), fetchedAt: F.at(12))
        let atAnswer = try XCTUnwrap(timeline.pin(for: "a", at: F.at(12)))
        F.assertClose(atAnswer.coordinate, RadarProjection.position(of: RadarSchedule(F.vehicle("a", stops: F.threeStops())), anchor: nil, at: F.at(12))!.coordinate)
        XCTAssertEqual(atAnswer.distanceToAnswer, 0)
        XCTAssertFalse(atAnswer.isCalculated, "at its own time the position is the server's")
        let later = try XCTUnwrap(timeline.pin(for: "a", at: F.at(47)))
        F.assertClose(later.coordinate, F.point(15.5), "35 minutes later by the timetable")
        XCTAssertTrue(later.isCalculated)
        XCTAssertEqual(later.distanceToAnswer, 35 * 60)
    }

    func testARunThatIsOverIsDroppedAndOneThatNeverStartedIsNotThere() {
        var timeline = RadarTimeline()
        timeline.addFrame([answer("a", at: 12)], time: F.at(12), fetchedAt: F.at(12))
        XCTAssertNotNil(timeline.pin(for: "a", at: F.at(62)), "arrives at 62")
        XCTAssertNil(timeline.pin(for: "a", at: F.at(63)), "the run is over")
        XCTAssertTrue(timeline.pins(at: F.at(90)).isEmpty)
        XCTAssertNil(timeline.pin(for: "unknown", at: F.at(10)))
    }

    // MARK: Two answers: blend

    func testBetweenTwoAnswersThePositionBlendsFromOneToTheOther() throws {
        // The train is a little slower than its timetable at the first answer and a little faster at the second.
        var timeline = RadarTimeline()
        let slow = F.vehicle("a", stops: F.threeStops(), position: F.point(14.3))
        let fast = F.vehicle("a", stops: F.threeStops(), position: F.point(15.4))   // minute 40: timetable says 15.0 + 8/30 = 15.27
        timeline.addFrame([slow], time: F.at(12), fetchedAt: F.at(12))
        timeline.addFrame([fast], time: F.at(40), fetchedAt: F.at(40))
        F.assertClose(timeline.pin(for: "a", at: F.at(12))?.coordinate, F.point(14.3))
        F.assertClose(timeline.pin(for: "a", at: F.at(40))?.coordinate, F.point(15.4))
        // In between: continuous, and moving east.
        var last = 14.3
        for minute in stride(from: 12.0, through: 40.0, by: 1) {
            let pin = try XCTUnwrap(timeline.pin(for: "a", at: F.at(minute)), "minute \(minute)")
            XCTAssertGreaterThanOrEqual(pin.coordinate.longitude, last - 1e-9, "minute \(minute): never backwards")
            XCTAssertLessThan(abs(pin.coordinate.longitude - last), 0.2, "no jump at minute \(minute)")
            last = pin.coordinate.longitude
        }
    }

    func testAStopThatAnAnswerReplacesIsReplacedNotAddedBeside() throws {
        // A diversion: the later answer has a stop at the same planned minute somewhere else. Only the fresher answer's stop is real.
        var timeline = RadarTimeline()
        timeline.addFrame([answer("a", at: 10)], time: F.at(10), fetchedAt: F.at(10))
        var diverted = F.threeStops()
        diverted[1].lat = 49.0
        let divertedPosition = RadarProjection.position(of: RadarSchedule(F.vehicle("a", stops: diverted)), anchor: nil, at: F.at(20))?.coordinate
        timeline.addFrame([F.vehicle("a", stops: diverted, position: divertedPosition)], time: F.at(20), fetchedAt: F.at(20))
        let stops = try XCTUnwrap(timeline.trips["a"]).run.stops
        XCTAssertEqual(stops.count, 3, "no fourth stop")
        XCTAssertEqual(stops[1].coordinate.latitude, 49.0, "the fresher answer's stop")
        let atStop = try XCTUnwrap(timeline.pin(for: "a", at: F.at(31)))
        XCTAssertEqual(atStop.coordinate.latitude, 49.0, accuracy: 1e-9)
    }

    // MARK: Merging the windows of several answers

    /// A run of eight stops on the line, one every 10 minutes (1 minute standing), as the real run is.
    private var longRun: [F.Stop] {
        var stops: [F.Stop] = []
        for index in 0..<8 {
            let minute = Double(index) * 10
            let arrival: Double? = index == 0 ? nil : minute
            let departure: Double? = index == 7 ? nil : minute + 1
            // The line zigzags 22 km north and south, so a straight line across several stops is wrong by kilometres.
            stops.append(F.Stop(lon: 14.0 + Double(index) * 0.2, arr: arrival, dep: departure, lat: index % 2 == 0 ? 48.0 : 48.2))
        }
        return stops
    }

    /// What the radar really sends of a run (measured, docs/RADAR_TIMETRAVEL.md §R12): the origin, the stop last left, the stop heading for, the destination.
    private func window(_ minute: Double, last: Int) -> RadarVehicle {
        let stops = longRun
        let kept = [0, last, last + 1, 7].reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }
        let truth = RadarSchedule(F.vehicle("w", stops: stops))
        let position = RadarProjection.position(of: truth, anchor: nil, at: F.at(minute))?.coordinate ?? F.point(14)
        return F.vehicle("w", stops: kept.map { stops[$0] }, position: position)
    }

    func testTheWindowsOfSeveralAnswersAreMergedIntoOneRun() throws {
        var timeline = RadarTimeline()
        timeline.addFrame([window(15, last: 1)], time: F.at(15), fetchedAt: F.at(15))
        XCTAssertEqual(timeline.trips["w"]?.run.stops.count, 4, "origin, last, next, destination")
        timeline.addFrame([window(55, last: 5)], time: F.at(55), fetchedAt: F.at(55))
        let run = try XCTUnwrap(timeline.trips["w"]).run
        XCTAssertEqual(run.stops.count, 6, "origin, 1, 2, 5, 6, destination: the stops of both answers once each")
        XCTAssertEqual(run.stops.map { Int((($0.coordinate.longitude - 14.0) / 0.2).rounded()) }, [0, 1, 2, 5, 6, 7], "in run order")
        XCTAssertEqual(run.stops.map(\.planned), run.stops.map(\.planned).sorted())
    }

    func testMoreAnswersMakeThePositionsBetweenThemBetter() throws {
        // The truth is the full eight-stop run. One answer knows the current leg and then a straight line to the destination; two answers
        // know the stops around both times and the position at both.
        let truth = RadarSchedule(F.vehicle("w", stops: longRun))
        func error(_ timeline: RadarTimeline, at minute: Double) -> Double {
            let real = RadarProjection.position(of: truth, anchor: nil, at: F.at(minute))!.coordinate
            return timeline.pin(for: "w", at: F.at(minute))!.coordinate.distanceKm(to: real)
        }
        var one = RadarTimeline()
        one.addFrame([window(15, last: 1)], time: F.at(15), fetchedAt: F.at(15))
        var two = one
        two.addFrame([window(55, last: 5)], time: F.at(55), fetchedAt: F.at(55))
        var three = two
        three.addFrame([window(35, last: 3)], time: F.at(35), fetchedAt: F.at(35))
        var worst = (one: 0.0, two: 0.0, three: 0.0)
        for minute in stride(from: 16.0, through: 60.0, by: 4) {
            worst = (max(worst.one, error(one, at: minute)), max(worst.two, error(two, at: minute)), max(worst.three, error(three, at: minute)))
        }
        XCTAssertGreaterThan(worst.one, 3, "from one answer the stretch after the next stop is a straight line to the destination")
        XCTAssertGreaterThan(worst.two, 3, "two answers leave stops 3 and 4 unknown")
        XCTAssertLessThan(worst.three, 1.5, "three answers know every stop of this run: only the 1 minute standing at each is off")
        XCTAssertLessThan(worst.three, worst.one)
        XCTAssertEqual(try XCTUnwrap(three.pin(for: "w", at: F.at(35))).distanceToAnswer, 0)
    }

    func testTheWholeStopListOfTheSelectedTrainMakesItsPathExact() throws {
        var timeline = RadarTimeline()
        timeline.addFrame([window(15, last: 1)], time: F.at(15), fetchedAt: F.at(15))
        let truth = RadarSchedule(F.vehicle("w", stops: longRun))
        func worstError() throws -> Double {
            try stride(from: 20.0, through: 60, by: 2).map { minute -> Double in
                let real = try XCTUnwrap(RadarProjection.position(of: truth, anchor: nil, at: F.at(minute))).coordinate
                return try XCTUnwrap(timeline.pin(for: "w", at: F.at(minute))).coordinate.distanceKm(to: real)
            }.max() ?? 0
        }
        XCTAssertGreaterThan(try worstError(), 3, "four stops: a straight line from the next stop to the destination")
        timeline.addDetails(F.vehicle("w", stops: longRun), fetchedAt: F.at(16))
        XCTAssertEqual(timeline.trips["w"]?.run.stops.count, 8, "every stop of the run")
        XCTAssertLessThan(try worstError(), 1.5, "all stops known: only the minute standing at each is off")
        timeline.addDetails(F.vehicle("unknown", stops: longRun), fetchedAt: F.at(16))
        XCTAssertNil(timeline.trips["unknown"], "a trip the timeline does not know stays unknown")
    }

    func testAReportedDelayBeatsACarriedOneWhateverTheOrder() throws {
        var timeline = RadarTimeline()
        let reported = F.vehicle("d", stops: [F.Stop(lon: 14, arr: nil, dep: 0, depDelay: 4), F.Stop(lon: 15, arr: 30, dep: 32, arrDelay: 4, depDelay: 4),
                                              F.Stop(lon: 16, arr: 62, dep: nil, arrDelay: 6)])
        let silent = F.vehicle("d", stops: F.threeStops())   // fetched later, but with no report at all
        timeline.addFrame([reported], time: F.at(5), fetchedAt: F.at(5))
        timeline.addFrame([silent], time: F.at(25), fetchedAt: F.at(25))
        XCTAssertEqual(timeline.trips["d"]?.run.stops[2].arrivalDelay, 360, "the destination keeps the reported delay")
        XCTAssertEqual(timeline.pin(for: "d", at: F.at(40))?.delaySeconds, 360)
    }

    // MARK: Vehicles that start later, vehicles that are gone

    func testATrainThatStartsLaterAppearsFromItsFirstDeparture() throws {
        // Not in the answer for now; the answer for minute +40 has it running (left at +25, 15 minutes into its first leg).
        let stops = [F.Stop(lon: 14, arr: nil, dep: 25), F.Stop(lon: 15, arr: 55, dep: nil)]
        var timeline = RadarTimeline()
        timeline.addFrame([], time: F.at(0), fetchedAt: F.at(0))
        timeline.addFrame([answer("late", at: 40, stops: stops)], time: F.at(40), fetchedAt: F.at(0.5))
        XCTAssertNil(timeline.pin(for: "late", at: F.at(24)), "not started yet at 24")
        let atStart = try XCTUnwrap(timeline.pin(for: "late", at: F.at(25)))
        F.assertClose(atStart.coordinate, F.point(14.0), "projected back to its departure")
        let middle = try XCTUnwrap(timeline.pin(for: "late", at: F.at(30)))
        F.assertClose(middle.coordinate, F.point(14.0 + 5.0 / 30.0), accuracy: 1e-6)
        XCTAssertEqual(timeline.pins(at: F.at(10)).count, 0)
        XCTAssertEqual(timeline.pins(at: F.at(30)).count, 1)
    }

    func testATrainHeldAtItsFirstStopIsOnlyThereFromTheAnswerThatSaidSo() throws {
        let stops = [F.Stop(lon: 14, arr: nil, dep: 25), F.Stop(lon: 15, arr: 55, dep: nil)]
        var timeline = RadarTimeline()
        // The answer for minute 15 has the train standing at its first stop, 10 minutes before departure.
        timeline.addFrame([F.vehicle("held", stops: stops, position: F.point(14.0))], time: F.at(15), fetchedAt: F.at(0.5))
        XCTAssertNil(timeline.pin(for: "held", at: F.at(10)), "before that answer the timetable alone does not put it on the map")
        let held = try XCTUnwrap(timeline.pin(for: "held", at: F.at(20)))
        F.assertClose(held.coordinate, F.point(14.0), "held at the first stop until it leaves")
        let leaving = try XCTUnwrap(timeline.pin(for: "held", at: F.at(40)))
        F.assertClose(leaving.coordinate, F.point(14.5))
    }

    func testAVehicleInTheLiveStoreAndInALaterFrameIsOneTrip() throws {
        var timeline = RadarTimeline()
        timeline.addLive([(vehicle: answer("a", at: -1), time: F.at(-1))])
        timeline.addFrame([answer("a", at: 40)], time: F.at(40), fetchedAt: F.at(0.5))
        XCTAssertEqual(timeline.tripCount, 1)
        XCTAssertEqual(timeline.trips["a"]?.observations.count, 2)
        XCTAssertNotNil(timeline.pin(for: "a", at: F.at(20)))
    }

    func testACompleteAnswerRemovesWhatItDoesNotContainAPartialOneDoesNot() {
        var timeline = RadarTimeline()
        timeline.addFrame([answer("a", at: 10), answer("b", at: 10)], time: F.at(10), fetchedAt: F.at(10))
        // A newer complete answer for the same minute that lacks "b" (it left): "b" is not projected on from the older one.
        timeline.addFrame([answer("a", at: 11)], time: F.at(11), fetchedAt: F.at(11), isComplete: false)
        XCTAssertNotNil(timeline.trips["b"], "a cut-off or partial answer proves nothing about the others")
        timeline.addFrame([answer("a", at: 11)], time: F.at(11), fetchedAt: F.at(12), isComplete: true)
        XCTAssertNil(timeline.trips["b"], "a complete answer without it: it is gone")
        XCTAssertNotNil(timeline.trips["a"])
    }

    // MARK: Dedup of snapshots

    func testANewerAnswerForTheSameMinuteReplacesTheOlderOne() throws {
        var timeline = RadarTimeline()
        timeline.addFrame([answer("a", at: 20, delay: 0)], time: F.at(20), fetchedAt: F.at(0))
        timeline.addFrame([answer("a", at: 20.5, delay: 6)], time: F.at(20.5), fetchedAt: F.at(1))
        XCTAssertEqual(timeline.trips["a"]?.observations.count, 1, "30 seconds apart: one observation")
        XCTAssertEqual(timeline.frames.count, 1)
        let pin = try XCTUnwrap(timeline.pin(for: "a", at: F.at(40)))
        XCTAssertEqual(pin.delaySeconds, 360, "the newer answer's delay")
        // An older answer never replaces a newer one, whatever its time.
        timeline.addFrame([answer("a", at: 20, delay: 0)], time: F.at(20), fetchedAt: F.at(0.5))
        XCTAssertEqual(timeline.trips["a"]?.observations.first?.fetchedAt, F.at(1))
    }

    func testAnswersFurtherApartThanTheWindowAreKeptSeparately() {
        var timeline = RadarTimeline()
        for minute in [0.0, 20, 40, 60] {
            timeline.addFrame([answer("a", at: minute)], time: F.at(minute), fetchedAt: F.at(0))
        }
        XCTAssertEqual(timeline.trips["a"]?.observations.count, 4)
        XCTAssertEqual(timeline.frames.map(\.time), [0, 20, 40, 60].map { F.at(Double($0)) })
    }

    func testTheVehicleOfAnAnswerIsTheNewestOne() {
        var timeline = RadarTimeline()
        var old = answer("a", at: 10)
        old.direction = "alt"
        var new = answer("a", at: 40)
        new.direction = "neu"
        timeline.addFrame([new], time: F.at(40), fetchedAt: F.at(5))
        timeline.addFrame([old], time: F.at(10), fetchedAt: F.at(1))
        XCTAssertEqual(timeline.vehicle("a")?.direction, "neu", "the answer fetched last is the one the line plate and the sheet come from")
    }

    // MARK: Memory

    func testTheNumberOfTripsIsBounded() {
        var limits = RadarTimeline.Limits()
        limits.maxTrips = 100
        var timeline = RadarTimeline(limits: limits)
        // 250 runs that end one minute apart: the 100 that end last stay.
        let vehicles = (0..<250).map { index -> RadarVehicle in
            let stops = [F.Stop(lon: 14, arr: nil, dep: 0), F.Stop(lon: 15, arr: 100 + Double(index), dep: nil)]
            return F.vehicle("t\(index)", stops: stops)
        }
        timeline.addFrame(vehicles, time: F.at(0), fetchedAt: F.at(0))
        XCTAssertEqual(timeline.tripCount, 100)
        XCTAssertNotNil(timeline.trips["t249"])
        XCTAssertNil(timeline.trips["t0"])
    }

    func testTheObservationsOfATripAreBoundedAndTheNewestAnswersStay() {
        var timeline = RadarTimeline()
        for index in 0..<30 {
            let minute = Double(index) * 3
            timeline.addFrame([answer("a", at: minute)], time: F.at(minute), fetchedAt: F.at(minute))
        }
        let observations = timeline.trips["a"]?.observations ?? []
        XCTAssertEqual(observations.count, timeline.limits.maxObservationsPerTrip)
        XCTAssertEqual(observations.last?.time, F.at(87), "the newest stays")
        XCTAssertEqual(observations, observations.sorted { $0.time < $1.time }, "still sorted")
        XCTAssertLessThanOrEqual(timeline.frames.count, timeline.limits.maxFrames)
    }

    func testAZeitreiseOfADayOfAustrianRailStaysSmall() {
        // 1 200 vehicles, 12 stops each, 10 snapshots: the observations are compact (64 bytes a stop), the stop names exist once per trip.
        var timeline = RadarTimeline()
        let stops = (0..<12).map { F.Stop(lon: 14 + Double($0) * 0.1, arr: Double($0) * 5, dep: Double($0) * 5 + 1) }
        for frame in 0..<10 {
            let minute = Double(frame) * 20
            let vehicles = (0..<1200).map { F.vehicle("t\($0)", stops: stops, position: F.point(14.2)) }
            timeline.addFrame(vehicles, time: F.at(minute), fetchedAt: F.at(minute))
        }
        XCTAssertEqual(timeline.tripCount, 1200)
        XCTAssertEqual(timeline.observationCount, 12_000)
        let bytes = timeline.observationCount * (12 * MemoryLayout<RadarScheduleStop>.stride + MemoryLayout<RadarTimeline.Observation>.stride)
        XCTAssertLessThan(bytes, 12_000_000, "twelve thousand observations are about 8 MB, not the 100 MB that full vehicles would be")
        XCTAssertLessThanOrEqual(MemoryLayout<RadarScheduleStop>.stride, 64)
        // Asking for every vehicle is cheap enough for 12 frames a second (a debug build on Linux here; a device build is several times faster).
        let started = Date()
        var count = 0
        for step in 0..<10 { count += timeline.pins(at: F.at(10 + Double(step))).count }
        let perCall = Date().timeIntervalSince(started) / 10
        print("RADAR_TIME_PERF pins(at:) for 1200 vehicles: \(Int(perCall * 1000)) ms per call (debug, Linux)")
        XCTAssertGreaterThan(count, 0)
        XCTAssertLessThan(perCall, 0.25, "under a quarter second even unoptimised")
    }

    func testPruneDropsEndedTripsAndObservationsNoOneNeeds() {
        var timeline = RadarTimeline()
        timeline.addFrame([answer("a", at: -30), answer("short", at: -30,
                                                          stops: [F.Stop(lon: 14, arr: nil, dep: -40), F.Stop(lon: 15, arr: -10, dep: nil)])],
                          time: F.at(-30), fetchedAt: F.at(-30))
        timeline.addFrame([answer("a", at: -1)], time: F.at(-1), fetchedAt: F.at(-1))
        timeline.addFrame([answer("a", at: 40)], time: F.at(40), fetchedAt: F.at(0))
        timeline.prune(now: F.at(0))
        XCTAssertNil(timeline.trips["short"], "ended 10 minutes ago")
        XCTAssertEqual(timeline.trips["a"]?.observations.map(\.time), [F.at(-1), F.at(40)], "the newest observation before now is the anchor for everything after")
    }

    func testPruningForAZeitreiseKeepsWhatTheScrubberCanReach() {
        // Review 1: entering a Zeitreise again pruned at "now", so the trains of the last half hour that had ended were gone while their
        // snapshots still counted as fetched. The scrubber reaches 30 minutes back: everything from there stays.
        var timeline = RadarTimeline()
        let ended = [F.Stop(lon: 14, arr: nil, dep: -40), F.Stop(lon: 15, arr: -10, dep: nil)]
        timeline.addFrame([answer("ended", at: -30, stops: ended), answer("a", at: -30)], time: F.at(-30), fetchedAt: F.at(0))
        timeline.addFrame([answer("a", at: -10)], time: F.at(-10), fetchedAt: F.at(0))
        timeline.addFrame([answer("a", at: 20)], time: F.at(20), fetchedAt: F.at(0))
        let before = timeline.pin(for: "ended", at: F.at(-20))
        XCTAssertNotNil(before)
        timeline.prune(forRangeAt: F.at(5))
        XCTAssertEqual(timeline.pin(for: "ended", at: F.at(-20))?.coordinate, before?.coordinate, "25 minutes back is in the range")
        XCTAssertEqual(timeline.trips["a"]?.observations.map(\.time), [F.at(-30), F.at(-10), F.at(20)], "-30 is the newest at the left edge")
        timeline.prune(forRangeAt: F.at(45))
        XCTAssertNil(timeline.trips["ended"], "ended 25 minutes before the left edge")
        XCTAssertEqual(timeline.trips["a"]?.observations.map(\.time), [F.at(-10), F.at(20)])
    }

    // MARK: What the screen needs

    func testPinsAreOrderedAndCarryTheDelayStateAtThatTime() throws {
        var timeline = RadarTimeline()
        timeline.addFrame([answer("b", at: 5, delay: 7), answer("a", at: 5, delay: 1), answer("c", at: 5)], time: F.at(5), fetchedAt: F.at(5))
        let pins = timeline.pins(at: F.at(20))
        XCTAssertEqual(pins.map(\.tripID), ["a", "b", "c"])
        XCTAssertEqual(pins.map(\.delayState), [.onTime, .late, .unknown], "1 minute, 7 minutes, no report")
        let cancelled = F.vehicle("x", stops: F.threeStops(delay: 0), cancelled: true)
        timeline.addFrame([cancelled], time: F.at(5), fetchedAt: F.at(5))
        XCTAssertEqual(timeline.pin(for: "x", at: F.at(10))?.delayState, .cancelled)
    }

    func testTheFilterAsksThePinsDelayNotTheOneOfNow() throws {
        var timeline = RadarTimeline()
        timeline.addFrame([answer("late", at: 5, delay: 9), answer("fine", at: 5, delay: 0)], time: F.at(5), fetchedAt: F.at(5))
        let pins = timeline.pins(at: F.at(20))
        XCTAssertEqual(pins.filter { RadarFilter(onlyLate: true).matches($0) }.map(\.tripID), ["late"])
        XCTAssertEqual(pins.filter { RadarFilter(categories: ["REX"]).matches($0) }.count, 0)
        XCTAssertEqual(pins.filter { RadarFilter(categories: ["RJX"]).matches($0) }.count, 2)
        XCTAssertEqual(pins.filter { RadarFilter(delays: [.onTime]).matches($0) }.map(\.tripID), ["fine"])
    }

    func testTheAgeOfTheDelaysIsThatOfTheOlderAnswerAroundTheTime() {
        var timeline = RadarTimeline()
        timeline.addFrame([answer("a", at: 20)], time: F.at(20), fetchedAt: F.at(0))
        timeline.addFrame([answer("a", at: 40)], time: F.at(40), fetchedAt: F.at(0.5))
        XCTAssertEqual(timeline.delayDataAge(at: F.at(30), now: F.at(2)), 120, "the answer for 20 arrived at minute 0")
        XCTAssertEqual(timeline.delayDataAge(at: F.at(50), now: F.at(2)) ?? -1, 90, accuracy: 1e-9, "after the last: only that one")
        XCTAssertNil(RadarTimeline().delayDataAge(at: F.at(1), now: F.at(2)))
    }

    // MARK: The trail

    func testTheTrailIsTheLastTenMinutesOfThePath() throws {
        var timeline = RadarTimeline()
        timeline.addFrame([answer("a", at: 12)], time: F.at(12), fetchedAt: F.at(12))
        let trail = timeline.trail(for: "a", endingAt: F.at(25))
        XCTAssertEqual(trail.count, 11, "one point a minute: 15 ... 25")
        F.assertClose(trail.last, timeline.pin(for: "a", at: F.at(25))!.coordinate)
        F.assertClose(trail.first, timeline.pin(for: "a", at: F.at(15))!.coordinate)
        XCTAssertEqual(trail, trail.sorted { $0.longitude < $1.longitude }, "eastbound")
    }

    func testTheTrailStartsWhereTheRunStartsAndStandingTrainsHaveNoDuplicatePoints() throws {
        var timeline = RadarTimeline()
        timeline.addFrame([answer("a", at: 12)], time: F.at(12), fetchedAt: F.at(12))
        let early = timeline.trail(for: "a", endingAt: F.at(4))
        XCTAssertEqual(early.count, 5, "minutes 0 to 4: the run began at 0")
        let standing = timeline.trail(for: "a", endingAt: F.at(32))
        XCTAssertEqual(Set(standing.map { "\($0.latitude),\($0.longitude)" }).count, standing.count, "the 2 minutes at B are one point")
        XCTAssertTrue(timeline.trail(for: "a", endingAt: F.at(80)).isEmpty, "not on its way then: no trail")
        XCTAssertTrue(timeline.trail(for: "nobody", endingAt: F.at(10)).isEmpty)
    }

    func testTheTrailFollowsTheRouteOfTheSelectedTrain() throws {
        // The route bends 22 km north between A and B. The server's position at minute 12 is on it (40 % of the 87 km), not on the straight line.
        let route = try XCTUnwrap(RadarRoute([F.point(14.0), F.point(14.5, lat: 48.2), F.point(15.0), F.point(16.0)]))
        var timeline = RadarTimeline()
        timeline.addFrame([F.vehicle("a", stops: F.threeStops(), position: GeoPoint(latitude: 48.16, longitude: 14.4))], time: F.at(12), fetchedAt: F.at(12))
        XCTAssertNotNil(timeline.trips["a"]?.observations.first?.anchor, "a position on the route bend is within the anchor's tolerance")
        let straight = timeline.trail(for: "a", endingAt: F.at(25))
        let along = timeline.trail(for: "a", endingAt: F.at(25), route: route)
        XCTAssertGreaterThan(along.map(\.latitude).max() ?? 0, 48.19, "the trail reaches the bend of the route")
        XCTAssertLessThan(straight.map(\.latitude).max() ?? 99, 48.15, "the straight line does not")
    }
}
