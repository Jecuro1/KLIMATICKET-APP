import XCTest
@testable import KlimaCore

/// Anschluss-Wächter: states, thresholds, trend, hysteresis and the sources of the numbers (docs/CONNECTION_GUARD.md §2–3).
final class ConnectionGuardStateTests: XCTestCase {
    private func at(_ hhmm: String, second: Int = 0) -> Date { GuardFixture.at(hhmm, second: second) }

    /// The connection with a given spare time (feeder on time at 14:28, walk 3, connection moved by realtime).
    private func journey(buffer: Int, walk: Int? = 3, reachable: Bool? = true) -> Journey {
        // 14:28 + walk + buffer = expected departure; planned 14:40.
        let expected = at("14:28").addingTimeInterval(Double((walk ?? 0) + buffer) * 60)
        return GuardFixture.journey(feederDelay: 0, connectionDelay: expected.timeIntervalSince(at("14:40")), walk: walk,
                                    reachable: reachable)
    }

    private func state(buffer: Int, now: String = "14:00", reachable: Bool? = true) -> GuardState {
        GuardFixture.assess(journey(buffer: buffer, reachable: reachable), now: at(now)).assessment.state
    }

    func testThresholdsWithASteadyBuffer() {
        let expected: [(Int, GuardState)] = [(10, .safe), (9, .safe), (5, .safe), (4, .tighter), (2, .tighter), (1, .shaky),
                                             (0, .shaky), (-1, .shaky), (-2, .likelyMissed), (-6, .likelyMissed)]
        for (buffer, state) in expected {
            XCTAssertEqual(self.state(buffer: buffer), state, "buffer \(buffer)")
            XCTAssertEqual(GuardFixture.assess(journey(buffer: buffer), now: at("14:00")).assessment.bufferMinutes, buffer)
        }
    }

    /// Two answers: `from` minutes `ago` minutes before, then `to` now.
    private func sequence(from: Int, to: Int, ago: Int = 4, reachable: Bool? = true) -> GuardAssessment {
        let first = GuardFixture.assess(journey(buffer: from, reachable: reachable), now: at("14:00").addingTimeInterval(Double(-ago) * 60))
        return GuardFixture.assess(journey(buffer: to, reachable: reachable), now: at("14:00"), memory: first.memory).assessment
    }

    func testFallingTrend() {
        let a = sequence(from: 9, to: 6)
        XCTAssertEqual(a.trend, .falling)
        XCTAssertEqual(a.state, .tighter, "five or more but falling below ten: „Wird knapper“")
        XCTAssertEqual(a.trendReference, GuardSample(at: at("13:56"), minutes: 9))
        XCTAssertEqual(GuardText.trend(a, now: at("14:00")), "Wird knapper: vor 4 Min waren es 9 Min")

        XCTAssertEqual(sequence(from: 12, to: 10).state, .safe, "falling but still ten: „Sicher“")
        XCTAssertEqual(sequence(from: 11, to: 9).state, .tighter)
        XCTAssertEqual(sequence(from: 7, to: 5).state, .tighter)
        XCTAssertEqual(sequence(from: 6, to: 5).trend, .steady, "one minute is no trend")
        XCTAssertEqual(sequence(from: 6, to: 5).state, .safe)
    }

    func testRisingTrendNeedsTwoAnswersToTurnBetter() {
        let a = sequence(from: 2, to: 5, ago: 3)
        XCTAssertEqual(a.trend, .rising)
        XCTAssertEqual(a.rawState, .safe)
        XCTAssertEqual(a.state, .tighter, "one better answer is not enough")
        XCTAssertEqual(GuardText.trend(a, now: at("14:00")), "Entspannt sich: vor 3 Min waren es 2 Min")
    }

    func testSamplesOlderThanTenMinutesAreForgotten() {
        let a = sequence(from: 12, to: 6, ago: 11)
        XCTAssertEqual(a.trend, .steady)
        XCTAssertEqual(a.rawState, .safe)
    }

    func testHysteresisWorseAtOnceBetterAfterTwoAgreeingAnswers() {
        var memory = GuardMemory()
        func step(_ buffer: Int, _ minute: Int) -> GuardAssessment {
            let r = GuardFixture.assess(journey(buffer: buffer), now: at("13:40").addingTimeInterval(Double(minute) * 60), memory: memory)
            memory = r.memory
            return r.assessment
        }
        XCTAssertEqual(step(8, 0).state, .safe)
        XCTAssertEqual(step(1, 1).state, .shaky, "worse shows at once")
        XCTAssertEqual(step(8, 2).state, .shaky, "first better answer: still „Wackelt“")
        XCTAssertEqual(step(3, 3).state, .tighter, "second better answer: the more careful of the two")
        XCTAssertEqual(step(7, 4).state, .tighter)
        XCTAssertEqual(step(7, 5).state, .safe)
    }

    func testNothingTurnsBetterWithoutANewAnswer() {
        let j = journey(buffer: 1)
        var r = GuardFixture.assess(j, now: at("13:40"), journeyAt: at("13:40"))
        r = GuardFixture.assess(journey(buffer: 8), now: at("13:41"), journeyAt: at("13:41"), memory: r.memory)
        XCTAssertEqual(r.assessment.state, .shaky)
        // Same answer again, later: no new data, no second vote.
        r = GuardFixture.assess(journey(buffer: 8), now: at("13:43"), journeyAt: at("13:41"), memory: r.memory)
        XCTAssertEqual(r.assessment.state, .shaky)
    }

    func testFollowArrivalWinsOnlyWhenNewer() {
        let j = GuardFixture.journey(feederDelay: 180, connectionDelay: 0)   // 14:31 → 14:40, walk 3: 6
        let late = GuardFixture.followSnapshot(delay: 6 * 60, now: at("14:10"))   // the follow says 14:34
        let newer = GuardFixture.assess(j, now: at("14:10"), journeyAt: at("14:05"), follow: late, followAt: at("14:09")).assessment
        XCTAssertEqual(newer.bufferMinutes, 3)
        XCTAssertEqual(newer.feeder.delayMinutes, 6)
        XCTAssertEqual(newer.dataAt, at("14:09"))
        let older = GuardFixture.assess(j, now: at("14:10"), journeyAt: at("14:09"), follow: late, followAt: at("14:05")).assessment
        XCTAssertEqual(older.bufferMinutes, 6)
        XCTAssertEqual(older.dataAt, at("14:09"))
    }

    func testFallbackTripOfTheConnectionWinsWhenNewer() throws {
        let j = GuardFixture.journey(feederDelay: 0, connectionDelay: 0)   // 14:28 → 14:40: 9
        let trip = TripDetails(tripID: "trip-connection", stopovers: [
            Stopover(location: GuardFixture.stPoelten, departure: GuardFixture.event(at("14:40"), delay: 4 * 60, platform: "5")),
        ])
        let a = ConnectionGuard.assess(journey: j, followSnapshot: nil, followAt: nil, journeyAt: at("13:50"), connectionTrip: trip,
                                       connectionTripAt: at("14:00"), previous: GuardMemory(), now: at("14:00"))!.assessment
        XCTAssertEqual(a.bufferMinutes, 13)
        let stale = ConnectionGuard.assess(journey: j, followSnapshot: nil, followAt: nil, journeyAt: at("14:01"), connectionTrip: trip,
                                           connectionTripAt: at("14:00"), previous: GuardMemory(), now: at("14:02"))!.assessment
        XCTAssertEqual(stale.bufferMinutes, 9)
    }

    func testMissedIsAFactOfTheDataEvenAtBufferZero() {
        // Feeder 20 s after the connecting departure, no walk: rounded buffer 0, but the train had not arrived.
        let j = GuardFixture.journey(feederDelay: 12 * 60 + 20, connectionDelay: 0, walk: nil)
        let before = GuardFixture.assess(j, now: at("14:39")).assessment
        XCTAssertEqual(before.bufferMinutes, 0)
        XCTAssertEqual(before.state, .shaky, "before the departure it is a forecast")
        let after = GuardFixture.assess(j, now: at("14:40", second: 10)).assessment
        XCTAssertEqual(after.state, .missed)
        XCTAssertEqual(GuardText.missedNote(after), "REX 2 ist laut Prognose um 14:40 abgefahren.")
    }

    func testLikelyMissedBeforeDepartureMissedAfter() {
        let j = GuardFixture.journey(feederDelay: 13 * 60, connectionDelay: 0)   // 14:41 vs 14:40, walk 3: −4
        var r = GuardFixture.assess(j, now: at("14:30"))
        XCTAssertEqual(r.assessment.state, .likelyMissed)
        XCTAssertEqual(GuardText.headline(r.assessment).full, "Es fehlen dir 4 Min")
        r = GuardFixture.assess(j, now: at("14:40", second: 30), journeyAt: at("14:40"), memory: r.memory)
        XCTAssertEqual(r.assessment.state, .missed, "the departure has passed and the feeder had not arrived")
    }

    func testLikelyMissedIsNotSticky() {
        var r = GuardFixture.assess(journey(buffer: -3), now: at("14:00"))
        XCTAssertEqual(r.assessment.state, .likelyMissed)
        r = GuardFixture.assess(journey(buffer: 2), now: at("14:01"), memory: r.memory)
        XCTAssertEqual(r.assessment.state, .likelyMissed)
        r = GuardFixture.assess(journey(buffer: 2), now: at("14:02"), memory: r.memory)
        XCTAssertEqual(r.assessment.state, .tighter, "a later prediction says the connection holds")
    }

    func testMissedNeverTurnsBetterByTimeAlone() {
        let j = GuardFixture.journey(feederDelay: 13 * 60, connectionDelay: 0)
        var r = GuardFixture.assess(j, now: at("14:41"), journeyAt: at("14:41"))
        XCTAssertEqual(r.assessment.state, .missed)
        for minute in 42...44 {
            r = GuardFixture.assess(j, now: at("14:\(minute)"), journeyAt: at("14:41"), memory: r.memory)
            XCTAssertEqual(r.assessment.state, .missed)
        }
        // A new answer that clearly says otherwise (the connection is now 8 minutes late), twice.
        let later = GuardFixture.journey(feederDelay: 13 * 60, connectionDelay: 8 * 60)
        r = GuardFixture.assess(later, now: at("14:45"), journeyAt: at("14:45"), memory: r.memory)
        XCTAssertEqual(r.assessment.state, .missed)
        r = GuardFixture.assess(later, now: at("14:46"), journeyAt: at("14:46"), memory: r.memory)
        XCTAssertEqual(r.assessment.bufferMinutes, 4)
        XCTAssertEqual(r.assessment.state, .tighter)
    }

    func testCancellations() {
        let feeder = GuardFixture.assess(GuardFixture.journey(feederCancelled: true), now: at("14:00")).assessment
        XCTAssertEqual(feeder.state, .cancelled)
        XCTAssertEqual(feeder.cancelledLeg, .feeder)
        XCTAssertEqual(GuardText.headline(feeder).full, "RJX 66 fällt aus")

        let stop = GuardFixture.assess(GuardFixture.journey(arrivalCancelled: true), now: at("14:00")).assessment
        XCTAssertEqual(stop.state, .cancelled, "the feeder does not stop at the transfer station")

        let connection = GuardFixture.assess(GuardFixture.journey(connectionCancelled: true), now: at("14:00")).assessment
        XCTAssertEqual(connection.cancelledLeg, .connection)
        XCTAssertEqual(GuardText.headline(connection).full, "REX 2 fällt aus")
        XCTAssertEqual(GuardText.toast(connection), "REX 2 fällt aus")

        let departure = GuardFixture.assess(GuardFixture.journey(departureCancelled: true), now: at("14:00")).assessment
        XCTAssertEqual(departure.state, .cancelled)

        let follow = GuardFixture.followSnapshot(delay: 0, now: at("14:00"), cancelled: true)
        let viaFollow = GuardFixture.assess(GuardFixture.journey(), now: at("14:00"), journeyAt: at("13:50"),
                                            follow: follow, followAt: at("14:00")).assessment
        XCTAssertEqual(viaFollow.cancelledLeg, .feeder)
    }

    func testNoRealtimeOnEitherLegIsScheduled() {
        let a = GuardFixture.assess(GuardFixture.journey(feederDelay: nil, connectionDelay: nil), now: at("14:00")).assessment
        XCTAssertEqual(a.state, .scheduled)
        XCTAssertTrue(a.basedOnPlan)
        XCTAssertEqual(a.bufferMinutes, 9)
        XCTAssertEqual(GuardText.legTime(a.feeder), "14:28 laut Fahrplan")
        // One leg with realtime is enough for a state.
        let one = GuardFixture.assess(GuardFixture.journey(feederDelay: nil, connectionDelay: 0), now: at("14:00")).assessment
        XCTAssertEqual(one.state, .safe)
    }

    func testNotReachableCapsAtShakyAndNeverMakesMissed() {
        let a = GuardFixture.assess(journey(buffer: 8, reachable: false), now: at("14:00")).assessment
        XCTAssertEqual(a.state, .shaky)
        XCTAssertTrue(a.flaggedUnreachable)
        XCTAssertEqual(state(buffer: 3, reachable: false), .shaky)
        XCTAssertEqual(state(buffer: -3, reachable: false), .likelyMissed, "the buffer decides, not the flag")
        XCTAssertEqual(state(buffer: 8, reachable: nil), .safe, "a missing flag is no warning")
        let scheduled = GuardFixture.assess(GuardFixture.journey(feederDelay: nil, connectionDelay: nil, reachable: false), now: at("14:00"))
        XCTAssertEqual(scheduled.assessment.state, .shaky)
    }

    func testOverTwoMinutesAfterTheDeparture() {
        let j = journey(buffer: 4)   // expected departure 14:35
        XCTAssertNotEqual(GuardFixture.assess(j, now: at("14:36")).assessment.state, .over)
        XCTAssertEqual(GuardFixture.assess(j, now: at("14:37")).assessment.state, .over)
        let short = journey(buffer: -1)
        XCTAssertEqual(GuardFixture.assess(short, now: at("14:40")).assessment.state, .shaky, "no „Umstieg vorbei“ when short")
    }

    /// A delayed connection (expected 5 minutes after planned) keeps the guard after the follow's stage turned `.arrived`
    /// (at the planned departure) and ends with „Umstieg vorbei“ at the expected departure + 2 min.
    func testDelayedConnectionOutlivesTheFollowStage() {
        let j = GuardFixture.journey(feederDelay: 0, connectionDelay: 5 * 60)   // 14:28 → 14:45
        let follow = GuardFixture.followSnapshot(delay: 0, now: at("14:41"))
        XCTAssertEqual(follow.stage, .arrived, "the follow ends at the planned departure 14:40")
        var engine = GuardEngine(record: GuardRecord(followTripID: "trip-feeder", journey: j, journeyAt: at("14:30"),
                                                     products: .klimaTicket, klimaTicketOnly: true, createdAt: at("13:00")))
        _ = engine.followUpdated(follow, at: at("14:41"), now: at("14:41"))
        XCTAssertEqual(engine.state, .safe)
        let conditions = GuardConditions(followsFeeder: true, appActive: true, liveAvailable: true, lowPower: false, switchedOff: false)
        XCTAssertEqual(engine.decision(conditions: conditions, now: at("14:41")), .ask(.reconstruction))
        _ = engine.reassess(now: at("14:46"))
        XCTAssertNotEqual(engine.state, .over)
        _ = engine.reassess(now: at("14:47"))
        XCTAssertEqual(engine.state, .over)
        XCTAssertTrue(engine.hasEnded(now: at("14:47")))
        XCTAssertEqual(engine.decision(conditions: conditions, now: at("14:47")), .idle(.ended))
    }

    func testAcrossMidnight() {
        let j = GuardFixture.journey(arrival: GuardFixture.at("23:56"), feederDelay: 0,
                                     departure: GuardFixture.at("00:08", day: 13), connectionDelay: 0)
        let a = GuardFixture.assess(j, now: GuardFixture.at("23:30")).assessment
        XCTAssertEqual(a.bufferMinutes, 9)
        XCTAssertEqual(a.state, .safe)
    }

    func testAcrossTheDSTChange() {
        // 2026-10-25: 03:00 CEST becomes 02:00 CET. Arrival 02:50 CEST (00:50 UTC), departure 02:05 CET (01:05 UTC): 15 minutes.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let arrival = cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 0, minute: 50))!
        let departure = cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 1, minute: 5))!
        let j = GuardFixture.journey(arrival: arrival, feederDelay: 0, departure: departure, connectionDelay: 0)
        let a = GuardFixture.assess(j, now: arrival.addingTimeInterval(-600)).assessment
        XCTAssertEqual(a.bufferMinutes, 12)
        XCTAssertEqual(GuardText.legTime(a.feeder), "02:50 (pünktlich)")
        XCTAssertEqual(GuardText.legTime(a.connection), "02:05 (pünktlich)")
    }

    func testWalkSubtractionEqualsTheConnectionDetail() throws {
        var checked = 0
        for (name, journey) in try GuardFixture.plannerJourneysWithChanges() {
            let rides = journey.legs.indices.filter { journey.legs[$0].kind == .ride }
            for i in 0..<(rides.count - 1) {
                let detail = JourneyPresentation.transfer(journey, from: rides[i], to: rides[i + 1])
                let card = ConnectionGuard.assess(journey: journey, feederRide: i, followSnapshot: nil, followAt: nil,
                                                  journeyAt: Vienna.date("2026-10-09 05:00"), previous: GuardMemory(),
                                                  now: Vienna.date("2026-10-09 05:00"))?.assessment
                XCTAssertEqual(card?.bufferMinutes, detail?.bufferMinutes, "\(name) change \(i)")
                if let detail { XCTAssertEqual(card?.walkMinutes, detail.walkMinutes, "\(name) change \(i)") }
                XCTAssertEqual(card?.stationName, detail?.stationName ?? card?.stationName)
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 10, "the fixtures hold enough changes")
    }

    func testLaterChangesArePlainLines() {
        let a = GuardFixture.assess(GuardFixture.journey(laterChange: true), now: at("14:00")).assessment
        XCTAssertEqual(a.laterTransfers, [GuardLaterTransfer(stationName: "Linz/Donau Hbf", plannedBufferMinutes: 12)])
        XCTAssertEqual(GuardText.laterTransfer(a.laterTransfers[0]), "Danach: Umstieg in Linz/Donau Hbf, 12 Min laut Fahrplan")
    }

    func testCanWatch() {
        XCTAssertTrue(ConnectionGuard.canWatch(GuardFixture.journey(), followTripID: "trip-feeder"))
        XCTAssertFalse(ConnectionGuard.canWatch(GuardFixture.journey(), followTripID: "trip-connection"), "not the first ride")
        XCTAssertFalse(ConnectionGuard.canWatch(GuardFixture.journey(token: nil), followTripID: "trip-feeder"))
        var single = GuardFixture.journey()
        single.legs = [single.legs[0]]
        XCTAssertFalse(ConnectionGuard.canWatch(single, followTripID: "trip-feeder"))
    }
}
