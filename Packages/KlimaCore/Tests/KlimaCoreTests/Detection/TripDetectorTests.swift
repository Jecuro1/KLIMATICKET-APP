import XCTest
@testable import KlimaCore

final class TripDetectorTests: XCTestCase {
    typealias F = DetectFixtures

    // MARK: Train

    /// A regional train Innsbruck → Landeck: a visit at each station and a handful of cell-tower fixes in between.
    func testTrainRideFromVisitsAndCoarsePoints() throws {
        let dep = F.nov12("08:05"), arr = F.nov12("09:10")
        let track = CoarseTrack(
            points: ScriptedTrack.coarseLine(from: F.innsbruck.location, to: F.landeck.location, start: dep, end: arr, count: 5),
            visits: [F.visit(F.innsbruck, arrival: F.nov12("07:50"), departure: dep),
                     F.visit(F.landeck, arrival: arr, departure: nil, observed: F.nov12("09:22"))])
        let outcome = F.detector().detect(track, now: F.nov12("09:30"))
        let c = try outcome.onlyCandidate()

        XCTAssertEqual(c.from.station.id, F.innsbruck.id)
        XCTAssertEqual(c.to.station.id, F.landeck.id)
        XCTAssertEqual(c.departure, dep)
        XCTAssertEqual(c.arrival, arr)
        XCTAssertEqual(c.mode, .train)
        XCTAssertEqual(c.straightKm, F.km(F.innsbruck, F.landeck), accuracy: 0.01)
        XCTAssertEqual(c.averageSpeedKmh, F.km(F.innsbruck, F.landeck) / (65.0 / 60), accuracy: 0.5)
        XCTAssertEqual(c.confidence, .wahrscheinlich, "coarse data alone never reaches \"sicher\"")
        XCTAssertTrue(c.rank.reasons.contains { $0.code == "relation" })
        XCTAssertGreaterThanOrEqual(c.rank.score, CandidateRanking.likelyThreshold)
        XCTAssertFalse(c.sketch.isStraight)
        XCTAssertTrue(c.rank.carNotExcluded)
        XCTAssertTrue(outcome.rejections.isEmpty)
    }

    /// Dense GPS of a ride with a stop at every station on the way: the stops are evidence, the stays at the ends are points.
    func testTrainRideWithIntermediateStopsCountsThem() throws {
        let dep = F.nov12("08:05")
        let ride = ScriptedTrack.ride(waypoints: [F.innsbruck, F.telfs, F.imst, F.landeck].map(\.location), start: dep, cruiseKmh: 95,
                                      interval: 10, halts: [1: 100, 2: 100], source: .significantChange)
        let end = ride.last!.time
        var points = ScriptedTrack.stay(at: F.innsbruck.location, from: F.nov12("07:50"), to: dep.addingTimeInterval(-10), source: .significantChange)
        points += ride
        points += ScriptedTrack.stay(at: F.landeck.location, from: end.addingTimeInterval(60), to: end.addingTimeInterval(20 * 60), source: .significantChange)

        let outcome = F.detector().detect(CoarseTrack(points: points), now: end.addingTimeInterval(30 * 60))
        let c = try outcome.onlyCandidate()
        XCTAssertEqual(c.from.station.id, F.innsbruck.id)
        XCTAssertEqual(c.to.station.id, F.landeck.id)
        XCTAssertEqual(c.rank.reasons.first { $0.code == "halts" }?.weight ?? 0, 0.30, accuracy: 0.001, "two halts at rail stations on the way")
        XCTAssertGreaterThan(c.rank.score, 1.0 - 0.001)
        XCTAssertNotNil(c.pathKm)
        XCTAssertGreaterThanOrEqual(c.pathKm ?? 0, c.straightKm - 1)
        XCTAssertEqual(c.via.count, 0, "stops of the train are not vias")
    }

    /// A tunnel: no fixes for a quarter of an hour. The ride is one ride.
    func testRegionalTrainWithGPSGapInTunnel() throws {
        let dep = F.nov12("08:05")
        var ride = ScriptedTrack.ride(waypoints: [F.innsbruck, F.telfs, F.imst, F.landeck].map(\.location), start: dep, cruiseKmh: 70, interval: 20,
                                      halts: [1: 100], source: .significantChange)
        let tunnelStart = dep.addingTimeInterval(25 * 60)
        ride.removeAll { $0.time > tunnelStart && $0.time < tunnelStart.addingTimeInterval(15 * 60) }
        let end = ride.last!.time
        var points = ScriptedTrack.stay(at: F.innsbruck.location, from: F.nov12("07:48"), to: dep.addingTimeInterval(-20), source: .significantChange)
        points += ride
        points += ScriptedTrack.stay(at: F.landeck.location, from: end.addingTimeInterval(30), to: end.addingTimeInterval(12 * 60), source: .significantChange)

        let outcome = F.detector().detect(CoarseTrack(points: points), now: end.addingTimeInterval(20 * 60))
        let c = try outcome.onlyCandidate()
        XCTAssertEqual(c.from.station.id, F.innsbruck.id)
        XCTAssertEqual(c.to.station.id, F.landeck.id)
        XCTAssertGreaterThanOrEqual(c.rank.confidence, .wahrscheinlich)
    }

    // MARK: Not a train

    /// The main false positive: a car from one town to the other, beside the rail line. Start and end lie within 500 m of the
    /// stations, so every rule passes – and the ranking says "vielleicht", with the car named as possible.
    func testCarOnMotorwayBesideRailLineIsOnlyMaybe() throws {
        let dep = F.nov12("08:00"), arr = F.nov12("08:50")
        // 450 m and 480 m from the stations (home and office), not at the platform.
        let home = DetectionGeo.offset(F.innsbruck.location, meters: 450, bearingDegrees: 90)
        let office = DetectionGeo.offset(F.landeck.location, meters: 480, bearingDegrees: 270)
        let track = CoarseTrack(
            points: ScriptedTrack.coarseLine(from: home, to: office, start: dep, end: arr, count: 6),
            visits: [VisitRecord(at: home, accuracyMeters: 80, arrival: F.nov12("00:10"), departure: dep, observedAt: dep),
                     VisitRecord(at: office, accuracyMeters: 80, arrival: arr, departure: nil, observedAt: F.nov12("09:05"))])
        let outcome = F.detector().detect(track, now: F.nov12("09:30"))
        let c = try outcome.onlyCandidate()
        XCTAssertEqual(c.confidence, .vielleicht)
        XCTAssertTrue(c.rank.carNotExcluded)
        XCTAssertTrue(c.rank.negatives.contains { $0.code == "start.far" })
        XCTAssertTrue(c.rank.negatives.contains { $0.code == "end.far" })

        // The same ride by train, from the platform, ranks higher – that is the whole point of the score.
        let train = CoarseTrack(
            points: ScriptedTrack.coarseLine(from: F.innsbruck.location, to: F.landeck.location, start: dep, end: arr, count: 6),
            visits: [F.visit(F.innsbruck, arrival: F.nov12("07:45"), departure: dep), F.visit(F.landeck, arrival: arr, departure: nil, observed: F.nov12("09:05"))])
        let rail = try F.detector().detect(train, now: F.nov12("09:30")).onlyCandidate()
        XCTAssertGreaterThan(rail.rank.score, c.rank.score + 0.3)
        XCTAssertGreaterThan(rail.confidence, c.confidence)
    }

    /// The limit that no data can remove (docs/TRIP_DETECTION.md §4): a car parked at the station is a train rider's track.
    func testCarFromTheStationForecourtCanNotBeToldApart() throws {
        let dep = F.nov12("08:00"), arr = F.nov12("08:50")
        let track = CoarseTrack(
            points: ScriptedTrack.coarseLine(from: F.innsbruck.location, to: F.landeck.location, start: dep, end: arr, count: 6),
            visits: [F.visit(F.innsbruck, arrival: F.nov12("07:40"), departure: dep), F.visit(F.landeck, arrival: arr, departure: nil, observed: F.nov12("09:05"))])
        let c = try F.detector().detect(track, now: F.nov12("09:30")).onlyCandidate()
        XCTAssertLessThan(c.confidence, .sicher, "without the timetable nothing is \"sicher\"")
        XCTAssertTrue(c.rank.carNotExcluded, "the card must always say that a car is not excluded")
    }

    func testWalkingBetweenTwoStationsIsRejectedAsTooSlow() {
        let dep = F.nov12("10:00"), arr = F.nov12("11:36")   // Innsbruck → Hall, 8 km in 96 min = 5 km/h
        let track = CoarseTrack(
            points: ScriptedTrack.coarseLine(from: F.innsbruck.location, to: F.hall.location, start: dep, end: arr, count: 8, accuracy: 60),
            visits: [F.visit(F.innsbruck, arrival: F.nov12("09:30"), departure: dep), F.visit(F.hall, arrival: arr, departure: F.nov12("12:30"))])
        let outcome = F.detector().detect(track, now: F.nov12("13:00"))
        XCTAssertTrue(outcome.candidates.isEmpty)
        let r = outcome.rejections.first
        XCTAssertEqual(r?.code, "tooSlow")
        XCTAssertEqual(r?.fromName, F.innsbruck.name)
        XCTAssertEqual(r?.toName, F.hall.name)
        if case .tooSlow(let kmh)? = r?.reason { XCTAssertEqual(kmh, 5, accuracy: 0.6) } else { XCTFail("tooSlow expected") }
    }

    func testCyclingIsRejectedAsTooSlow() {
        let dep = F.nov12("14:00"), arr = F.nov12("14:25")   // 8.0 km in 25 min = 19 km/h
        let track = CoarseTrack(
            points: ScriptedTrack.coarseLine(from: F.hall.location, to: F.innsbruck.location, start: dep, end: arr, count: 4, accuracy: 40),
            visits: [F.visit(F.hall, arrival: F.nov12("13:20"), departure: dep), F.visit(F.innsbruck, arrival: arr, departure: F.nov12("15:00"))])
        let outcome = F.detector().detect(track, now: F.nov12("16:00"))
        XCTAssertTrue(outcome.candidates.isEmpty)
        XCTAssertEqual(outcome.rejections.map(\.code), ["tooSlow"])
    }

    /// A tram in the city: 3.3 km is under the 5 km floor, however fast.
    func testTramInTheCityIsTooShort() {
        let dep = F.nov12("17:00"), arr = F.nov12("17:14")
        let track = CoarseTrack(
            points: ScriptedTrack.coarseLine(from: F.schottentor.location, to: F.suedtirolerPlatz.location, start: dep, end: arr, count: 3, accuracy: 60),
            visits: [F.visit(F.schottentor, arrival: F.nov12("16:40"), departure: dep), F.visit(F.suedtirolerPlatz, arrival: arr, departure: F.nov12("17:40"))])
        let outcome = F.detector().detect(track, now: F.nov12("18:00"))
        XCTAssertTrue(outcome.candidates.isEmpty)
        XCTAssertEqual(outcome.rejections.map(\.code), ["tooShort"])
    }

    /// Sitting in a station café for 40 minutes: no ride, and nothing to explain either.
    func testStationDwellAloneIsNothing() {
        let track = CoarseTrack(points: ScriptedTrack.stay(at: F.innsbruck.location, from: F.nov12("12:00"), to: F.nov12("12:40")),
                                visits: [F.visit(F.innsbruck, arrival: F.nov12("12:00"), departure: nil, observed: F.nov12("12:20"))])
        let outcome = F.detector().detect(track, now: F.nov12("13:00"))
        XCTAssertTrue(outcome.candidates.isEmpty)
        XCTAssertTrue(outcome.rejections.isEmpty)
    }

    func testRideWithoutAStationAtTheEndIsRejectedWithNearestDistance() {
        let dep = F.nov12("08:05"), arr = F.nov12("09:00")
        // The end is on a field 4 km from Landeck.
        let field = DetectionGeo.offset(F.landeck.location, meters: 4000, bearingDegrees: 200)
        let track = CoarseTrack(
            points: ScriptedTrack.coarseLine(from: F.innsbruck.location, to: field, start: dep, end: arr, count: 4),
            visits: [F.visit(F.innsbruck, arrival: F.nov12("07:50"), departure: dep),
                     VisitRecord(at: field, accuracyMeters: 80, arrival: arr, departure: nil, observedAt: F.nov12("09:30"))])
        let outcome = F.detector().detect(track, now: F.nov12("10:00"))
        XCTAssertTrue(outcome.candidates.isEmpty)
        guard case .noStationAtEnd(let nearest)? = outcome.rejections.first?.reason else { return XCTFail("noStationAtEnd expected: \(outcome.rejections)") }
        XCTAssertEqual(nearest ?? 0, 4.0, accuracy: 0.3)
    }

    /// An open stay at the end that has lasted only two minutes may be a stop of the train – not a destination yet.
    func testOpenStayAtTheEndNeedsFiveMinutes() {
        let dep = F.nov12("08:05"), arr = F.nov12("09:10")
        let track = CoarseTrack(
            points: ScriptedTrack.coarseLine(from: F.innsbruck.location, to: F.landeck.location, start: dep, end: arr, count: 5),
            visits: [F.visit(F.innsbruck, arrival: F.nov12("07:50"), departure: dep), F.visit(F.landeck, arrival: arr, departure: nil, observed: arr)])
        XCTAssertTrue(F.detector().detect(track, now: arr.addingTimeInterval(2 * 60)).candidates.isEmpty)
        XCTAssertEqual(F.detector().detect(track, now: arr.addingTimeInterval(6 * 60)).candidates.count, 1)
    }

    /// Going back and forth on a long loop is no ride from A to B.
    func testWindingPathIsRejected() {
        let dep = F.nov12("08:05"), arr = F.nov12("09:15")
        // Innsbruck → Landeck (63 km) by way of a point 150 km to the north: about 270 km of track for 63 km of line.
        let far = DetectionGeo.offset(DetectionGeo.lerp(F.innsbruck.location, F.landeck.location, 0.5), meters: 150_000, bearingDegrees: 0)
        var points = ScriptedTrack.coarseLine(from: F.innsbruck.location, to: far, start: dep, end: dep.addingTimeInterval(35 * 60), count: 4)
        points += ScriptedTrack.coarseLine(from: far, to: F.landeck.location, start: dep.addingTimeInterval(36 * 60), end: arr, count: 4)
        let track = CoarseTrack(points: points,
                                visits: [F.visit(F.innsbruck, arrival: F.nov12("07:50"), departure: dep), F.visit(F.landeck, arrival: arr, departure: F.nov12("10:30"))])
        let outcome = F.detector().detect(track, now: F.nov12("11:00"))
        XCTAssertTrue(outcome.candidates.isEmpty)
        XCTAssertEqual(outcome.rejections.first?.code, "winding")
    }

    // MARK: Days

    func testDayWithTwoRides() throws {
        let track = CoarseTrack(
            points: ScriptedTrack.coarseLine(from: F.innsbruck.location, to: F.landeck.location, start: F.nov12("07:05"), end: F.nov12("08:10"), count: 4)
                + ScriptedTrack.coarseLine(from: F.landeck.location, to: F.innsbruck.location, start: F.nov12("17:20"), end: F.nov12("18:25"), count: 4),
            visits: [F.visit(F.innsbruck, arrival: F.nov12("06:50"), departure: F.nov12("07:05")),
                     F.visit(F.landeck, arrival: F.nov12("08:10"), departure: F.nov12("17:05")),   // the whole workday
                     F.visit(F.landeck, arrival: F.nov12("17:05"), departure: F.nov12("17:20")),
                     F.visit(F.innsbruck, arrival: F.nov12("18:25"), departure: nil, observed: F.nov12("18:40"))])
        let outcome = F.detector().detect(track, now: F.nov12("19:00"))
        XCTAssertEqual(outcome.candidates.count, 2, "rejections: \(outcome.rejections.map { "\($0.code) \($0.text) \($0.departure)→\($0.arrival) \($0.fromName ?? "-") \($0.toName ?? "-")" })")
        guard outcome.candidates.count == 2 else { return }
        let morning = outcome.candidates[0], evening = outcome.candidates[1]
        XCTAssertEqual(morning.from.station.id, F.innsbruck.id)
        XCTAssertEqual(morning.to.station.id, F.landeck.id)
        XCTAssertEqual(evening.from.station.id, F.landeck.id)
        XCTAssertEqual(evening.to.station.id, F.innsbruck.id)
        XCTAssertLessThan(morning.arrival, evening.departure)
    }

    /// A ride that starts on one day and ends on the next (Vienna time).
    func testRideAcrossMidnight() throws {
        let dep = F.nov12("23:25"), arr = F.date("2026-11-13T00:20:00+01:00")
        let track = CoarseTrack(
            points: ScriptedTrack.coarseLine(from: F.wienHbf.location, to: F.stPoelten.location, start: dep, end: arr, count: 3),
            visits: [F.visit(F.wienHbf, arrival: F.nov12("23:05"), departure: dep),
                     F.visit(F.stPoelten, arrival: arr, departure: nil, observed: F.date("2026-11-13T00:35:00+01:00"))])
        let c = try F.detector().detect(track, now: F.date("2026-11-13T01:00:00+01:00")).onlyCandidate()
        XCTAssertEqual(c.duration, 55 * 60, accuracy: 0.1)
        XCTAssertEqual(c.averageSpeedKmh, F.km(F.wienHbf, F.stPoelten) / (55.0 / 60), accuracy: 0.5)
        let cal = Calendar.vienna
        XCTAssertNotEqual(cal.component(.day, from: c.departure), cal.component(.day, from: c.arrival))
        XCTAssertEqual(cal.component(.day, from: c.departure), 12)
        XCTAssertEqual(cal.component(.day, from: c.arrival), 13)
    }

    /// 29 March 2026: the clock jumps from 02:00 to 03:00. 01:40 → 03:10 is 30 minutes of travel, not 90.
    func testRideOverTheSpringDSTChangeUsesRealTime() throws {
        let dep = F.date("2026-03-29T01:40:00+01:00"), arr = F.date("2026-03-29T03:10:00+02:00")
        XCTAssertEqual(arr.timeIntervalSince(dep), 30 * 60)
        let track = CoarseTrack(
            points: ScriptedTrack.coarseLine(from: F.wienHbf.location, to: F.stPoelten.location, start: dep, end: arr, count: 3),
            visits: [F.visit(F.wienHbf, arrival: F.date("2026-03-29T01:25:00+01:00"), departure: dep),
                     F.visit(F.stPoelten, arrival: arr, departure: nil, observed: F.date("2026-03-29T03:25:00+02:00"))])
        let c = try F.detector().detect(track, now: F.date("2026-03-29T04:00:00+02:00")).onlyCandidate()
        XCTAssertEqual(c.duration, 30 * 60, accuracy: 0.1)
        XCTAssertEqual(c.averageSpeedKmh, F.km(F.wienHbf, F.stPoelten) * 2, accuracy: 0.5)   // km per half hour
    }

    /// 25 October 2026: 02:00–03:00 happens twice. 01:50 (summer time) → 02:30 (winter time) is 100 minutes.
    func testRideOverTheAutumnDSTChangeUsesRealTime() throws {
        let dep = F.date("2026-10-25T01:50:00+02:00"), arr = F.date("2026-10-25T02:30:00+01:00")
        XCTAssertEqual(arr.timeIntervalSince(dep), 100 * 60)
        let track = CoarseTrack(
            points: ScriptedTrack.coarseLine(from: F.innsbruck.location, to: F.landeck.location, start: dep, end: arr, count: 4),
            visits: [F.visit(F.innsbruck, arrival: F.date("2026-10-25T01:30:00+02:00"), departure: dep),
                     F.visit(F.landeck, arrival: arr, departure: nil, observed: F.date("2026-10-25T02:50:00+01:00"))])
        let c = try F.detector().detect(track, now: F.date("2026-10-25T03:30:00+01:00")).onlyCandidate()
        XCTAssertEqual(c.duration, 100 * 60, accuracy: 0.1)
        XCTAssertEqual(c.averageSpeedKmh, F.km(F.innsbruck, F.landeck) / (100.0 / 60), accuracy: 0.5)
    }

    // MARK: Changes

    /// A change at a hub: one ride "über Imst", not two.
    func testChangeAtAHubBecomesOneRideWithVia() throws {
        let t0 = F.nov12("08:00")
        let track = CoarseTrack(
            points: ScriptedTrack.coarseLine(from: F.innsbruck.location, to: F.imst.location, start: t0, end: F.nov12("08:50"), count: 3)
                + ScriptedTrack.coarseLine(from: F.imst.location, to: F.landeck.location, start: F.nov12("09:05"), end: F.nov12("09:25"), count: 2),
            visits: [F.visit(F.innsbruck, arrival: F.nov12("07:40"), departure: t0),
                     F.visit(F.imst, arrival: F.nov12("08:52"), departure: F.nov12("09:04")),
                     F.visit(F.landeck, arrival: F.nov12("09:26"), departure: nil, observed: F.nov12("09:40"))])
        let c = try F.detector().detect(track, now: F.nov12("10:00")).onlyCandidate()
        XCTAssertEqual(c.from.station.id, F.innsbruck.id)
        XCTAssertEqual(c.to.station.id, F.landeck.id)
        XCTAssertEqual(c.via.map(\.id), [F.imst.id])
    }

    /// A long wait at the hub (an hour) is a break between two rides.
    func testLongStayAtTheHubKeepsTwoRides() {
        let t0 = F.nov12("08:00")
        let track = CoarseTrack(
            points: ScriptedTrack.coarseLine(from: F.innsbruck.location, to: F.imst.location, start: t0, end: F.nov12("08:50"), count: 3)
                + ScriptedTrack.coarseLine(from: F.imst.location, to: F.landeck.location, start: F.nov12("10:05"), end: F.nov12("10:25"), count: 2),
            visits: [F.visit(F.innsbruck, arrival: F.nov12("07:40"), departure: t0),
                     F.visit(F.imst, arrival: F.nov12("08:52"), departure: F.nov12("10:04")),
                     F.visit(F.landeck, arrival: F.nov12("10:26"), departure: nil, observed: F.nov12("10:40"))])
        let outcome = F.detector().detect(track, now: F.nov12("11:00"))
        XCTAssertEqual(outcome.candidates.map { "\($0.from.station.id)>\($0.to.station.id)" }, ["\(F.innsbruck.id)>\(F.imst.id)", "\(F.imst.id)>\(F.landeck.id)"])
    }

    // MARK: Bus stops

    /// Between two towns by car: both ends have only bus stops near them, which every town has – not proposed.
    func testRideBetweenBusStopsOnlyIsTooUncertain() {
        let dep = F.nov12("07:30"), arr = F.nov12("07:45")
        let home = DetectionGeo.offset(F.miemingBus.location, meters: 200, bearingDegrees: 90)
        let work = DetectionGeo.offset(F.tarrenzBus.location, meters: 220, bearingDegrees: 90)
        let track = CoarseTrack(
            points: ScriptedTrack.coarseLine(from: home, to: work, start: dep, end: arr, count: 4),
            visits: [VisitRecord(at: home, accuracyMeters: 60, arrival: F.nov12("00:00"), departure: dep, observedAt: dep),
                     VisitRecord(at: work, accuracyMeters: 60, arrival: arr, departure: nil, observedAt: F.nov12("08:40"))])
        let outcome = F.detector().detect(track, now: F.nov12("09:00"))
        XCTAssertTrue(outcome.candidates.isEmpty, "\(outcome.candidates.map(\.rank.score))")
        XCTAssertEqual(outcome.rejections.first?.code, "tooUncertain")
    }

    // MARK: History

    func testDismissedPairIsDownWeighted() throws {
        let dep = F.nov12("08:05"), arr = F.nov12("09:10")
        let track = CoarseTrack(
            points: ScriptedTrack.coarseLine(from: F.innsbruck.location, to: F.landeck.location, start: dep, end: arr, count: 5),
            visits: [F.visit(F.innsbruck, arrival: F.nov12("07:50"), departure: dep), F.visit(F.landeck, arrival: arr, departure: nil, observed: F.nov12("09:22"))])
        let base = try F.detector().detect(track, now: F.nov12("09:30")).onlyCandidate()
        var history = PairHistory()
        history.dismissed[PairHistory.key(F.landeck.id, F.innsbruck.id)] = 1   // the other direction counts as well
        let once = try F.detector().detect(track, now: F.nov12("09:30"), history: history).onlyCandidate()
        XCTAssertEqual(once.rank.score, base.rank.score - 0.2, accuracy: 0.001)
        XCTAssertTrue(once.rank.negatives.contains { $0.code == "history.dismissed" })
        history.dismissed[PairHistory.key(F.landeck.id, F.innsbruck.id)] = 2
        let twice = try F.detector().detect(track, now: F.nov12("09:30"), history: history).onlyCandidate()
        XCTAssertLessThan(twice.confidence, base.confidence)
    }

    func testBorderlineRideVanishesAfterADismissal() {
        let dep = F.nov12("08:00"), arr = F.nov12("08:50")
        let home = DetectionGeo.offset(F.innsbruck.location, meters: 450, bearingDegrees: 90)
        let office = DetectionGeo.offset(F.landeck.location, meters: 480, bearingDegrees: 270)
        let track = CoarseTrack(
            points: ScriptedTrack.coarseLine(from: home, to: office, start: dep, end: arr, count: 6),
            visits: [VisitRecord(at: home, accuracyMeters: 80, arrival: F.nov12("00:10"), departure: dep, observedAt: dep),
                     VisitRecord(at: office, accuracyMeters: 80, arrival: arr, departure: nil, observedAt: F.nov12("09:05"))])
        let history = PairHistory(dismissed: [PairHistory.key(F.innsbruck.id, F.landeck.id): 1])
        let outcome = F.detector().detect(track, now: F.nov12("09:30"), history: history)
        XCTAssertTrue(outcome.candidates.isEmpty)
        XCTAssertEqual(outcome.rejections.first?.code, "tooUncertain")
    }

    // MARK: Robustness

    func testGarbageInputNeverCrashes() {
        let junk = CoarseTrack(points: [CoarsePoint(time: F.nov12("08:00"), latitude: .nan, longitude: 11, accuracyMeters: 10),
                                        CoarsePoint(time: F.nov12("08:01"), latitude: 91, longitude: 11, accuracyMeters: 10),
                                        CoarsePoint(time: F.nov12("08:02"), latitude: 47, longitude: 11, accuracyMeters: 99_999)],
                               visits: [VisitRecord(latitude: .infinity, longitude: 0, arrival: nil, departure: nil, observedAt: F.nov12("08:00"))])
        XCTAssertEqual(F.detector().detect(junk, now: F.nov12("09:00")), DetectionOutcome.empty)
        XCTAssertEqual(F.detector().detect(CoarseTrack(), now: F.nov12("09:00")), DetectionOutcome.empty)
    }

    /// The geofence exit at the start station was never delivered: the ride starts at the first fix clearly away from it.
    func testStayWithoutRecordedDepartureEndsAtTheFirstFixAwayFromIt() throws {
        let dep = F.nov12("08:05"), arr = F.nov12("09:10")
        let track = CoarseTrack(
            points: ScriptedTrack.coarseLine(from: F.innsbruck.location, to: F.landeck.location, start: dep, end: arr, count: 5),
            visits: [F.visit(F.innsbruck, arrival: F.nov12("07:50"), departure: nil, observed: F.nov12("07:50")),
                     F.visit(F.landeck, arrival: arr, departure: nil, observed: F.nov12("09:22"))])
        let c = try F.detector().detect(track, now: F.nov12("09:30")).onlyCandidate()
        XCTAssertEqual(c.from.station.id, F.innsbruck.id)
        XCTAssertEqual(c.to.station.id, F.landeck.id)
        // The first cell fix (1/6 of the way, 10 km from the station) is the earliest evidence of leaving.
        XCTAssertEqual(c.departure, dep.addingTimeInterval(65.0 * 60 / 6))
        // Without any fix away from it the person has not left: no ride.
        let still = CoarseTrack(points: [], visits: track.visits)
        XCTAssertTrue(F.detector().detect(still, now: F.nov12("09:30")).candidates.isEmpty)
    }

    /// Confirming or dismissing deletes the points of the ride – but not the first fix of the open destination: a phone that stands still
    /// sends no more, and with one fix left the stay the next ride starts from would be gone.
    func testDeletingTheEvidenceLeavesTheOpenDestinationStayIntact() throws {
        let dep = F.nov12("08:05"), arr = F.nov12("09:10")
        var points = ScriptedTrack.stay(at: F.innsbruck.location, from: F.nov12("07:40"), to: dep.addingTimeInterval(-60))
        points += ScriptedTrack.coarseLine(from: F.innsbruck.location, to: F.landeck.location, start: dep, end: arr, count: 5)
        points += [CoarsePoint(time: arr, at: F.landeck.location, accuracyMeters: 40),
                   CoarsePoint(time: arr.addingTimeInterval(8 * 60), at: F.landeck.location, accuracyMeters: 40)]
        let c = try F.detector().detect(CoarseTrack(points: points), now: F.nov12("09:30")).onlyCandidate()

        var buffer = RollingPointBuffer(points: points, visits: [])
        buffer.remove(from: c.evidenceStart, to: c.evidenceEnd)
        XCTAssertTrue(buffer.points.filter { $0.time < arr }.isEmpty, "everything of the ride and its start is gone")
        XCTAssertEqual(buffer.points.filter { $0.time >= arr }.count, 2, "the destination stay is not part of the evidence")
        // The stay is still a stay for the next ride.
        let again = F.detector().detect(buffer.track, now: F.nov12("09:30"))
        XCTAssertTrue(again.candidates.isEmpty)
    }

    /// iOS reports an unknown arrival as `distantPast`: with no measured dwell the stay is neither a destination nor a start.
    func testVisitWithoutArrivalCanNeitherEndNorStartARide() throws {
        let dep = F.nov12("08:05"), arr = F.nov12("09:10")
        let points = ScriptedTrack.coarseLine(from: F.innsbruck.location, to: F.landeck.location, start: dep, end: arr, count: 5)
        let noEnd = CoarseTrack(
            points: points,
            visits: [F.visit(F.innsbruck, arrival: F.nov12("07:50"), departure: dep), F.visit(F.landeck, arrival: nil, departure: nil, observed: F.nov12("09:22"))])
        XCTAssertTrue(F.detector().detect(noEnd, now: F.nov12("09:30")).candidates.isEmpty)
        let noStart = CoarseTrack(
            points: points,
            visits: [F.visit(F.innsbruck, arrival: nil, departure: dep), F.visit(F.landeck, arrival: arr, departure: nil, observed: F.nov12("09:22"))])
        XCTAssertTrue(F.detector().detect(noStart, now: F.nov12("09:30")).candidates.isEmpty)
        // The same ride with both arrivals known is found – the dwell is what was missing.
        let both = CoarseTrack(
            points: points,
            visits: [F.visit(F.innsbruck, arrival: F.nov12("07:50"), departure: dep), F.visit(F.landeck, arrival: arr, departure: nil, observed: F.nov12("09:22"))])
        XCTAssertEqual(F.detector().detect(both, now: F.nov12("09:30")).candidates.count, 1)
    }

    func testRouteSketchIsRelativeAndRoundTrips() throws {
        let sketch = RouteSketch.make(from: F.innsbruck.location, to: F.landeck.location,
                                      track: ScriptedTrack.coarseLine(from: F.innsbruck.location, to: F.landeck.location, start: F.nov12("08:00"), end: F.nov12("09:00"), count: 4).map(\.geo))
        XCTAssertEqual(sketch.points.count, 6)
        XCTAssertFalse(sketch.isStraight)
        for p in sketch.points { XCTAssertTrue((0...1).contains(p.x) && (0...1).contains(p.y)) }
        XCTAssertGreaterThan(sketch.points[0].y, sketch.points[5].y - 0.5)
        // Innsbruck lies east of Landeck: the start is on the right.
        XCTAssertGreaterThan(sketch.points[0].x, sketch.points[5].x)
        let decoded = try XCTUnwrap(RouteSketch(encoded: sketch.encoded))
        XCTAssertEqual(decoded, sketch)
        XCTAssertNil(RouteSketch(encoded: "X|0.1,0.2;0.3,0.4"))
        XCTAssertNil(RouteSketch(encoded: "T|0.1,0.2"))
        let straight = RouteSketch.make(from: F.innsbruck.location, to: F.landeck.location, track: [])
        XCTAssertTrue(straight.isStraight)
        XCTAssertEqual(straight.points.count, 2)
    }

    func testTooManySketchPointsAreThinned() {
        let track = (0..<200).map { DetectionGeo.lerp(F.innsbruck.location, F.landeck.location, Double($0) / 200) }
        let sketch = RouteSketch.make(from: F.innsbruck.location, to: F.landeck.location, track: track)
        XCTAssertEqual(sketch.points.count, RouteSketch.maxPoints)
    }
}
