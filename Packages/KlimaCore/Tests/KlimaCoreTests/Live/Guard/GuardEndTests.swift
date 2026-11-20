import XCTest
@testable import KlimaCore

/// Anschluss-Wächter after the review (docs/CONNECTION_GUARD.md §3, §4, §8): every change ends cleanly – also when only the
/// walk did not fit –, nothing changes after the end, the card offers only what still works, „Live verfolgen“ again keeps the
/// guard, and a failed check names the side that failed (the Auskunft, the app's own limit or pause, the connection).
final class GuardEndTests: XCTestCase {
    private func at(_ hhmm: String, second: Int = 0) -> Date { GuardFixture.at(hhmm, second: second) }
    private let on = GuardConditions(followsFeeder: true, appActive: true, liveAvailable: true, lowPower: false, switchedOff: false)

    /// Feeder on time at 14:28, walk 3, the connection moved so that `buffer` minutes are left (planned 14:40).
    private func journey(buffer: Int, walk: Int = 3) -> Journey {
        let expected = at("14:28").addingTimeInterval(Double(walk + buffer) * 60)
        return GuardFixture.journey(feederDelay: 0, connectionDelay: expected.timeIntervalSince(at("14:40")), walk: walk)
    }

    private func engine(_ journey: Journey, journeyAt: String = "14:00", createdAt: String = "13:00") -> GuardEngine {
        var e = GuardEngine(record: GuardRecord(followTripID: "trip-feeder", journey: journey, journeyAt: at(journeyAt),
                                                products: .klimaTicket, klimaTicketOnly: true, createdAt: at(createdAt)))
        _ = e.reassess(now: at(journeyAt))
        return e
    }

    // MARK: Finding 3 – a change that is short only by the walk ends as „Umstieg vorbei“ and says why

    func testShortOnlyByTheWalkEndsAsOverWithAnHonestNote() {
        // Feeder 14:28, connection 14:30 (2 minutes between the trains), walk 3: one minute short.
        let j = journey(buffer: -1)
        var e = engine(j)
        XCTAssertEqual(e.state, .shaky)
        _ = e.reassess(now: at("14:31"))
        XCTAssertEqual(e.state, .shaky, "until two minutes after the departure")
        XCTAssertFalse(e.hasEnded(now: at("14:31")))
        _ = e.reassess(now: at("14:32"))
        XCTAssertEqual(e.state, .over, "the feeder was there before the connection left: the change is behind you")
        XCTAssertEqual(e.endReason(now: at("14:32")), .over)
        let a = e.assessment!
        XCTAssertTrue(a.overShort)
        XCTAssertEqual(a.gapMinutes, 2)
        XCTAssertEqual(GuardText.overShortNote(a), "Laut Prognose blieben 2 Min für 3 Min Fußweg. Ob du REX 2 erwischt hast, weiß die Auskunft nicht.")
        XCTAssertTrue(GuardText.accessibility(a, now: at("14:32")).hasSuffix(
            "Laut Prognose blieben 2 Minuten für 3 Minuten Fußweg. Ob du REX 2 erwischt hast, weiß die Auskunft nicht. "
            + "Der Wächter ist für diese Fahrt fertig."))
        XCTAssertNil(GuardText.toast(a), "the end is no warning")
        XCTAssertNil(GuardText.badge(a.state), "the badge goes")
        let actions = e.actions(now: at("14:32"))
        XCTAssertTrue(actions.continueFollow, "REX 2 weiter verfolgen – maybe you made it")
        XCTAssertEqual(actions.alternatives, .button, "maybe you did not")
        XCTAssertFalse(actions.hasRow)
    }

    func testShortByTheWalkWithNoMinuteBetweenTheTrains() {
        var e = engine(journey(buffer: -3))   // feeder 14:28, connection 14:28, walk 3
        XCTAssertEqual(e.state, .likelyMissed)
        _ = e.reassess(now: at("14:30"))
        XCTAssertEqual(e.state, .over, "„Wahrscheinlich verpasst“ ends too")
        XCTAssertEqual(GuardText.overShortNote(e.assessment!),
                       "Laut Prognose blieb keine Minute für 3 Min Fußweg. Ob du REX 2 erwischt hast, weiß die Auskunft nicht.")
        var one = engine(journey(buffer: -2))
        _ = one.reassess(now: at("14:31"))
        XCTAssertEqual(GuardText.overShortNote(one.assessment!),
                       "Laut Prognose blieb 1 Min für 3 Min Fußweg. Ob du REX 2 erwischt hast, weiß die Auskunft nicht.")
    }

    func testAnOrdinaryEndHasNoShortNote() {
        var e = engine(journey(buffer: 4))
        _ = e.reassess(now: at("14:37"))
        XCTAssertEqual(e.state, .over)
        XCTAssertFalse(e.assessment!.overShort)
        XCTAssertNil(GuardText.overShortNote(e.assessment!))
        XCTAssertEqual(e.actions(now: at("14:37")).alternatives, .none)
    }

    func testWithoutRealtimeTheShortNoteSaysTimetable() {
        // No realtime on either train, by the timetable 14:28 → 14:30 with a walk of 3.
        let j = GuardFixture.journey(feederDelay: nil, departure: at("14:30"), connectionDelay: nil)
        var e = engine(j)
        XCTAssertEqual(e.state, .scheduled)
        _ = e.reassess(now: at("14:32"))
        XCTAssertEqual(e.state, .over, "before, „Nach Fahrplan“ stayed for good")
        XCTAssertTrue(GuardText.overShortNote(e.assessment!)!.hasPrefix("Laut Fahrplan blieben 2 Min für 3 Min Fußweg."))
    }

    func testAFeederAfterTheDepartureIsStillMissed() {
        var e = engine(GuardFixture.journey(feederDelay: 13 * 60, connectionDelay: 0))   // 14:41 vs 14:40
        _ = e.reassess(now: at("14:43"))
        XCTAssertEqual(e.state, .missed)
        XCTAssertFalse(e.assessment!.overShort)
    }

    // MARK: Findings 2 and 5 – after the end nothing is offered that does nothing, and nothing changes

    func testAfterTheWindowNoCheckNoSwitchButAlternatives() {
        // REX 2 leaves 14:40 while RJX 66 is 24 minutes late (14:52): „Verpasst“; the window ends 14:45.
        var e = engine(GuardFixture.journey(feederDelay: 24 * 60, connectionDelay: 0))
        _ = e.reassess(now: at("14:41"))
        XCTAssertEqual(e.state, .missed)
        let running = e.actions(now: at("14:41"))
        XCTAssertTrue(running.checkNow)
        XCTAssertTrue(running.toggleSwitch)
        XCTAssertEqual(running.alternatives, .prominent)
        XCTAssertNil(e.endReason(now: at("14:45")))
        _ = e.reassess(now: at("14:46"))
        XCTAssertEqual(e.endReason(now: at("14:46")), .windowPassed)
        let ended = e.actions(now: at("14:46"))
        XCTAssertFalse(ended.checkNow, "„Jetzt prüfen“ would do nothing now")
        XCTAssertFalse(ended.toggleSwitch, "„Wächter an/aus“ would rewrite a deleted record")
        XCTAssertFalse(ended.hasMenu)
        XCTAssertEqual(ended.alternatives, .prominent, "how to go on")
        XCTAssertTrue(ended.alarm, "RJX 66 has not reached the transfer station yet")
        XCTAssertFalse(e.actions(now: at("14:53")).alarm, "after its arrival there is nothing to wake you for")
        XCTAssertEqual(e.manualDecision(conditions: on, now: at("14:46")), .unavailable(.ended))
        XCTAssertEqual(GuardText.endedNote(e.assessment!, reason: .windowPassed),
                       "Der Wächter prüft nicht mehr: Die Umstiegszeit ist vorbei. Wie du weiterkommst, zeigen die Alternativen.")
        XCTAssertNil(GuardText.endedNote(e.assessment!, reason: .over))
    }

    func testExpiredGuardSaysSo() {
        var e = engine(journey(buffer: 7), createdAt: "01:30")
        _ = e.reassess(now: at("13:45"))
        XCTAssertEqual(e.endReason(now: at("13:45")), .expired)
        XCTAssertEqual(GuardText.endedNote(e.assessment!, reason: .expired), "Der Wächter prüft nicht mehr: Er läuft höchstens 12 Stunden.")
        let actions = e.actions(now: at("13:45"))
        XCTAssertFalse(actions.checkNow)
        XCTAssertEqual(actions.alternatives, .none, "„Sicher“ needs no alternatives")
        XCTAssertTrue(actions.alarm, "the feeder arrives 14:28")
    }

    func testRunningActions() {
        var e = engine(journey(buffer: 7))
        var a = e.actions(now: at("14:00"))
        XCTAssertEqual(a, GuardActions(alternatives: .menu, checkNow: true, alarm: true, toggleSwitch: true))
        XCTAssertTrue(a.hasMenu)
        XCTAssertTrue(e.setSwitchedOff(true))
        a = e.actions(now: at("14:00"))
        XCTAssertFalse(a.checkNow, "„Wächter aus“: only „Wächter an“ in the menu")
        XCTAssertTrue(a.toggleSwitch)
        XCTAssertEqual(engine(journey(buffer: 1)).actions(now: at("14:00")).alternatives, .prominent)
    }

    func testAfterTheEndNoRequestNoSwitchButFresherDataStillCounts() {
        // REX 2 expected 14:35, RJX 66 on time 14:28 by the last answer: „Umstieg vorbei“ at 14:37, the guard ends.
        var e = engine(journey(buffer: 4))
        _ = e.reassess(now: at("14:37"))
        XCTAssertEqual(e.state, .over)
        e.finish()
        let record = e.record
        XCTAssertFalse(e.setSwitchedOff(true), "the record is gone and stays gone")
        XCTAssertEqual(e.record, record)
        XCTAssertEqual(e.decision(conditions: on, now: at("14:38")), .idle(.ended))
        XCTAssertEqual(e.manualDecision(conditions: on, now: at("14:38")), .unavailable(.ended))
        // A check still on its way when the guard ended: it lands, nothing is asked again.
        e.begin()
        e.applyFailure(kind: .reconstruction, error: .timeout, sentAt: at("14:38"))
        XCTAssertFalse(e.requests.inFlight)
        XCTAssertEqual(e.decision(conditions: on, now: at("14:39")), .idle(.ended))
        // The follow's fresher answer (no request): RJX 66 came at 14:38, after REX 2 left at 14:35. The old answer's
        // „Umstieg vorbei“ gives way to „Verpasst“; the guard stays ended and offers the alternatives, not „weiter verfolgen“.
        let change = e.followUpdated(GuardFixture.followSnapshot(delay: 10 * 60, now: at("14:39")), at: at("14:39"), now: at("14:39"))
        XCTAssertEqual(e.state, .missed)
        XCTAssertTrue(change.worsened)
        XCTAssertTrue(e.hasEnded(now: at("14:39")), "also before the window's end (14:40)")
        XCTAssertEqual(e.endReason(now: at("14:39")), .windowPassed)
        XCTAssertEqual(e.decision(conditions: on, now: at("14:39")), .idle(.ended))
        let actions = e.actions(now: at("14:39"))
        XCTAssertFalse(actions.checkNow)
        XCTAssertFalse(actions.toggleSwitch)
        XCTAssertFalse(actions.continueFollow)
        XCTAssertEqual(actions.alternatives, .prominent)
        XCTAssertFalse(e.setSwitchedOff(false))
    }

    // MARK: Finding 1 – „Live verfolgen“ again on the same connection keeps the guard

    func testSameChangeIsRecognised() {
        let record = GuardFixture.record
        XCTAssertTrue(record.watchesSameChange(GuardFixture.journey(), followTripID: "trip-feeder", feederRide: 0))
        // A newer answer of the same connection (other delays, new handle, slim) is still the same change.
        var newer = GuardFixture.journey(feederDelay: 600, connectionDelay: 0, token: "ctx-2")
        newer = GuardRecord.slim(newer)
        XCTAssertTrue(record.watchesSameChange(newer, followTripID: "trip-feeder", feederRide: 0))
        XCTAssertFalse(record.watchesSameChange(GuardFixture.journey(), followTripID: "trip-other", feederRide: 0))
        XCTAssertFalse(record.watchesSameChange(GuardFixture.journey(), followTripID: "trip-feeder", feederRide: 1))
        var otherConnection = GuardFixture.journey()
        otherConnection.legs[2].tripID = "trip-later-connection"
        XCTAssertFalse(record.watchesSameChange(otherConnection, followTripID: "trip-feeder", feederRide: 0),
                       "a later connecting train is a new change")
        XCTAssertFalse(record.watchesSameChange(GuardFixture.journey(laterChange: true), followTripID: "trip-feeder", feederRide: 0),
                       "another destination")
        var unknown = GuardFixture.journey()
        unknown.legs[2].tripID = nil
        let unknownRecord = GuardRecord(followTripID: "trip-feeder", journey: unknown, journeyAt: at("14:00"), products: .klimaTicket,
                                        klimaTicketOnly: true, createdAt: at("13:00"))
        XCTAssertFalse(unknownRecord.watchesSameChange(unknown, followTripID: "trip-feeder", feederRide: 0),
                       "without trip ids nothing is known to be the same")
    }

    // MARK: Finding 4 – a failed check names the side that failed

    func testFailureReasons() {
        let until = at("14:32")
        let cases: [(LiveError, GuardFailure, Bool)] = [
            (.http(status: 502, excerpt: ""), .auskunft, true),
            (.blocked(.oebbHafas), .refused, false),
            (.hafas(code: "H9380", message: nil), .answerUnusable, true),
            (.noConnection, .answerUnusable, true),
            (.decoding("x"), .answerUnusable, true),
            (.rateLimited(.oebbHafas, retryAfter: nil), .appLimit, false),
            (.rateLimited(.oebbHafas, retryAfter: 30), .auskunftPause(until: nil), false),
            (.circuitOpen(.oebbHafas, until: until), .paused(until: until), false),
            (.timeout, .noAnswer, false),
            (.network("lost"), .connection, false),
            (.offline, .connection, false),
            (.disabled(.oebbHafas), .liveOff, false),
        ]
        for (error, reason, counts) in cases {
            XCTAssertEqual(GuardFailure(error), reason, "\(error)")
            XCTAssertEqual(GuardFailure.countsForFallback(error), counts, "\(error)")
        }
    }

    /// The app's own limit (`RequestThrottle`) and a 429 of the Auskunft both arrive as `.rateLimited`; only the 429 opens the
    /// app's circuit (`LiveHealth`), and that is what the guard reads right after the failure.
    func testTheAppsOwnLimitIsToldFromTheAuskunftsPause() {
        let until = at("14:01")
        XCTAssertEqual(GuardFailure(.rateLimited(.oebbHafas, retryAfter: nil), circuitOpenUntil: until), .auskunftPause(until: until),
                       "a 429 without Retry-After still opened the circuit")
        XCTAssertEqual(GuardFailure(.rateLimited(.oebbHafas, retryAfter: 60), circuitOpenUntil: until), .auskunftPause(until: until))
        XCTAssertEqual(GuardFailure(.rateLimited(.oebbHafas, retryAfter: nil), circuitOpenUntil: nil), .appLimit)
        XCTAssertNil(GuardFailure.appLimit.pauseEnd, "the app's limit holds a few seconds, the backoff is enough")
        XCTAssertEqual(GuardFailure.auskunftPause(until: until).pauseEnd, until)
        XCTAssertNil(GuardFailure.auskunftPause(until: nil).pauseEnd)
        // The guard keeps the Auskunft's pause like the app's own one: no automatic try, and „Jetzt prüfen“ says why.
        var e = engine(journey(buffer: 7))
        e.begin()
        e.applyFailure(kind: .reconstruction, error: .rateLimited(.oebbHafas, retryAfter: nil), circuitOpenUntil: until, sentAt: at("14:00"))
        XCTAssertEqual(e.decision(conditions: on, now: at("14:00", second: 20)), .wait(until))
        XCTAssertEqual(e.manualDecision(conditions: on, now: at("14:00", second: 30)), .paused(until: until))
        XCTAssertEqual(GuardText.pauseNote(e.requests.lastFailure, until: until), "Die Auskunft bittet um eine Pause bis 14:01")
        XCTAssertEqual(GuardText.status(.failed(lastAt: at("13:58"), retry: until, reason: e.requests.lastFailure!), now: at("14:00", second: 30)),
                       "Stand 13:58 · Die Auskunft bittet um eine Pause bis 14:01")
        // The app's own limit: the usual backoff, said as the app's doing.
        var f = engine(journey(buffer: 7))
        f.begin()
        f.applyFailure(kind: .reconstruction, error: .rateLimited(.oebbHafas, retryAfter: nil), sentAt: at("14:00"))
        XCTAssertEqual(f.decision(conditions: on, now: at("14:00", second: 5)), .wait(at("14:00", second: 15)))
        XCTAssertEqual(GuardText.status(.failed(lastAt: at("13:58"), retry: at("14:00", second: 15), reason: f.requests.lastFailure!),
                                        now: at("14:00", second: 5)),
                       "Stand 13:58 · Die App hält ihr Limit von 40 Abfragen pro Minute ein · neuer Versuch in 1 Min")
    }

    func testStatusSaysWhoseDoingItWas() {
        let now = at("14:27", second: 10)
        func line(_ reason: GuardFailure) -> String {
            GuardText.status(.failed(lastAt: at("14:25"), retry: at("14:28"), reason: reason), now: now)
        }
        XCTAssertEqual(line(.auskunft), "Stand 14:25 · Die Auskunft antwortet gerade nicht · neuer Versuch in 1 Min")
        XCTAssertEqual(line(.refused), "Stand 14:25 · Die Auskunft lehnt Abfragen gerade ab · neuer Versuch in 1 Min")
        XCTAssertEqual(line(.answerUnusable), "Stand 14:25 · Die Auskunft liefert die Verbindung gerade nicht · neuer Versuch in 1 Min")
        XCTAssertEqual(line(.appLimit), "Stand 14:25 · Die App hält ihr Limit von 40 Abfragen pro Minute ein · neuer Versuch in 1 Min")
        XCTAssertEqual(line(.auskunftPause(until: nil)), "Stand 14:25 · Die Auskunft hat um eine kurze Pause gebeten · neuer Versuch in 1 Min")
        XCTAssertEqual(line(.noAnswer), "Stand 14:25 · Keine Antwort: schwacher Empfang oder die Auskunft ist langsam · neuer Versuch in 1 Min")
        XCTAssertEqual(line(.connection), "Stand 14:25 · Gerade keine Verbindung, vielleicht schwacher Empfang · neuer Versuch in 1 Min")
        XCTAssertEqual(line(.liveOff), "Stand 14:25 · Live-Daten sind gerade aus · neuer Versuch in 1 Min")
        XCTAssertEqual(line(.paused(until: at("14:32"))), "Stand 14:25 · Die App pausiert ihre Abfragen bis 14:32")
        XCTAssertEqual(line(.paused(until: at("14:27"))), "Stand 14:25 · Die App hat ihre Abfragen kurz pausiert · neuer Versuch in 1 Min")
        XCTAssertEqual(line(.auskunftPause(until: at("14:32"))), "Stand 14:25 · Die Auskunft bittet um eine Pause bis 14:32")
        for reason in [GuardFailure.appLimit, .auskunftPause(until: nil), .paused(until: at("14:32")), .noAnswer, .connection, .liveOff] {
            XCTAssertFalse(line(reason).contains("Auskunft antwortet"), "not the Auskunft's silence: \(reason)")
        }
        for reason in [GuardFailure.appLimit, .paused(until: at("14:32")), .connection, .liveOff] {
            XCTAssertFalse(line(reason).contains("Auskunft"), "the Auskunft had nothing to do with it: \(reason)")
        }
    }

    func testTheGuardWaitsForTheAppsOwnPause() {
        var e = engine(journey(buffer: 7))
        e.begin()
        e.applyFailure(kind: .reconstruction, error: .circuitOpen(.oebbHafas, until: at("14:05")), sentAt: at("14:00"))
        XCTAssertEqual(e.requests.lastFailure, .paused(until: at("14:05")))
        XCTAssertFalse(e.requests.usesFallback)
        XCTAssertEqual(e.decision(conditions: on, now: at("14:00", second: 20)), .wait(at("14:05")), "not after 15 s: the app pauses anyway")
        XCTAssertEqual(e.manualDecision(conditions: on, now: at("14:01")), .paused(until: at("14:05")))
        XCTAssertEqual(GuardText.paused(at("14:05")), "Die App pausiert ihre Abfragen bis 14:05")
        XCTAssertEqual(e.decision(conditions: on, now: at("14:05")), .ask(.reconstruction))
        XCTAssertEqual(e.manualDecision(conditions: on, now: at("14:05")), .ask(.reconstruction))
        // A short pause does not stretch the backoff.
        var f = engine(journey(buffer: 7))
        f.begin()
        f.applyFailure(kind: .reconstruction, error: .circuitOpen(.oebbHafas, until: at("14:00", second: 5)), sentAt: at("14:00"))
        XCTAssertEqual(f.decision(conditions: on, now: at("14:00", second: 6)), .wait(at("14:00", second: 15)))
        // An answer clears the reason.
        f.begin()
        _ = f.applyReconstruction(journey(buffer: 7), sentAt: at("14:01"), now: at("14:01"))
        XCTAssertNil(f.requests.lastFailure)
    }

    func testAnAnswerWithoutTheChangeIsUnusableNotSilent() {
        var e = engine(journey(buffer: 7))
        var broken = GuardFixture.journey()
        broken.legs = [broken.legs[0]]
        e.begin()
        _ = e.applyReconstruction(broken, sentAt: at("14:00"), now: at("14:00"))
        XCTAssertEqual(e.requests.lastFailure, .answerUnusable)
        XCTAssertEqual(e.requests.reconstructionFailures, 1)
    }

    func testSpokenStatus() {
        let now = at("14:27", second: 10)
        XCTAssertEqual(GuardText.spokenStatus(.updated(at: at("14:27"), next: at("14:28")), now: now), "Stand 14:27, nächste Prüfung in 1 Min.")
        XCTAssertEqual(GuardText.spokenStatus(.checking(lastAt: nil), now: now), "Prüfe gerade …")
        XCTAssertEqual(GuardText.spokenStatus(.switchedOff, now: now), "Wächter für diese Fahrt aus.")
        XCTAssertEqual(GuardText.spokenStatus(.ended(lastAt: at("14:43")), now: now), "Stand 14:43, Prüfung beendet.")
    }

    /// Honesty: none of the new texts claims that a train waits or that the change worked.
    func testNewTextsMakeNoClaims() {
        var e = engine(journey(buffer: -1))
        _ = e.reassess(now: at("14:32"))
        let a = e.assessment!
        var strings = [GuardText.overShortNote(a)!, GuardText.endedNote(a, reason: .windowPassed)!,
                       GuardText.endedNote(a, reason: .expired)!, GuardText.paused(at("14:40"))]
        strings += [GuardFailure.auskunft, .refused, .answerUnusable, .appLimit, .auskunftPause(until: nil), .paused(until: at("14:40")),
                    .noAnswer, .connection, .liveOff].map(GuardText.failure)
        strings.append(GuardText.pauseNote(.auskunftPause(until: at("14:40")), until: at("14:40")))
        for s in strings {
            XCTAssertFalse(s.lowercased().contains("wartet"), s)
            XCTAssertFalse(s.lowercased().contains("gesichert"), s)
            XCTAssertFalse(s.lowercased().contains("geschafft"), s)
        }
    }
}
