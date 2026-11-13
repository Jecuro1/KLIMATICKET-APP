import XCTest
@testable import KlimaCore

/// Automatik: every trigger fires once and stays silent once, the follow threshold and its recovery, the milestone ledger,
/// cooldown, conditions, „Wochenende ruhig“, and the Testlauf's words equal the engine's decision.
final class AutomationEngineTests: XCTestCase {
    private typealias F = AutomationFixtures
    private let cal = Calendar.vienna
    /// Thursday 12 Nov 2026, 17:42.
    private let now = AutomationFixtures.at(2026, 11, 12, 17, 42)

    private func evaluate(_ rule: AutoRule, _ event: AutoEvent, _ state: AutoState, at date: Date? = nil) -> AutoVerdict {
        AutoRuleEngine.evaluate(rule, event: event, state: state, now: date ?? now, calendar: cal)
    }

    private func text(_ verdict: AutoVerdict) -> String { AutoText.explanation(verdict, calendar: cal) }

    // MARK: Follow delay

    func testFollowDelayFiresAtTheThreshold() {
        let rule = F.rule(.followDelay(minutes: 5), cooldown: 30)
        let verdict = evaluate(rule, .followUpdated, AutoState(follow: F.follow(delay: 8, at: now)))
        XCTAssertEqual(verdict.outcome, .now)
        XCTAssertEqual(text(verdict), "Würde jetzt auslösen: Verspätung 8 Min ist mindestens 5 Min (RJ 66, Ausstieg Innsbruck Hbf), kein Cooldown")
        XCTAssertEqual(verdict.firings.count, 1)
        XCTAssertEqual(verdict.firings.first?.title, "Verspätung 8 Min")
        XCTAssertEqual(verdict.firings.first?.body, "RJ 66 kommt in Innsbruck Hbf etwa 8 Min später an (ÖBB-Prognose).")
        XCTAssertEqual(verdict.firings.first?.explanation, text(verdict))
        XCTAssertTrue(verdict.marks.contains(.followReported(ruleID: rule.id, tripID: "1|RJ66|0")))
        XCTAssertTrue(verdict.marks.contains(.fired(ruleID: rule.id, at: now)))
    }

    func testFollowDelayStaysSilentBelowTheThreshold() {
        let verdict = evaluate(F.rule(.followDelay(minutes: 5)), .followUpdated, AutoState(follow: F.follow(delay: 3, at: now)))
        XCTAssertEqual(verdict.outcome, .silent)
        XCTAssertEqual(text(verdict), "Löst nicht aus: erst 3 Min Verspätung, ausgelöst wird ab 5 Min")
        XCTAssertTrue(verdict.firings.isEmpty)
    }

    func testFollowDelayNeedsAnActiveFollowAndRealtime() {
        let rule = F.rule(.followDelay(minutes: 10))
        XCTAssertEqual(evaluate(rule, .followUpdated, AutoState()).reason, .noFollow)
        XCTAssertEqual(evaluate(rule, .followUpdated, AutoState(follow: F.follow(delay: nil, at: now))).reason, .noDelayData)
        XCTAssertEqual(evaluate(rule, .followUpdated, AutoState(follow: F.follow(delay: 40, finished: true, at: now))).reason, .followEnded)
    }

    func testFollowDelayReportsOnceAndAgainAfterRecovery() {
        let rule = F.rule(.followDelay(minutes: 5))
        var ledger = AutoLedger()
        let first = evaluate(rule, .followUpdated, AutoState(follow: F.follow(delay: 7, at: now), ledger: ledger))
        XCTAssertTrue(first.fires)
        ledger.apply(first.marks)

        let again = evaluate(rule, .followUpdated, AutoState(follow: F.follow(delay: 9, at: now), ledger: ledger))
        XCTAssertEqual(again.reason, .alreadyReported(threshold: 5))
        XCTAssertFalse(again.fires)

        let recovered = evaluate(rule, .followUpdated, AutoState(follow: F.follow(delay: 2, at: now), ledger: ledger))
        XCTAssertFalse(recovered.fires)
        XCTAssertEqual(recovered.marks, [.followRecovered(ruleID: rule.id)])
        ledger.apply(recovered.marks)

        let risesAgain = evaluate(rule, .followUpdated, AutoState(follow: F.follow(delay: 6, at: now), ledger: ledger))
        XCTAssertTrue(risesAgain.fires)
    }

    func testAnotherFollowIsNewsEvenWhileTheLastOneWasReported() {
        let rule = F.rule(.followDelay(minutes: 5))
        var ledger = AutoLedger()
        ledger.apply([.followReported(ruleID: rule.id, tripID: "1|RJ66|0")])
        let other = evaluate(rule, .followUpdated, AutoState(follow: F.follow(delay: 12, trip: "2|REX5|0", at: now), ledger: ledger))
        XCTAssertTrue(other.fires)
    }

    func testCooldownHoldsTheRuleBackUntilItEnds() {
        let rule = F.rule(.followDelay(minutes: 5), cooldown: 30)
        var ledger = AutoLedger()
        ledger.apply([.fired(ruleID: rule.id, at: now)])
        let soon = evaluate(rule, .followUpdated, AutoState(follow: F.follow(delay: 9, trip: "2|REX5|0", at: now), ledger: ledger),
                            at: now.addingTimeInterval(10 * 60))
        XCTAssertEqual(soon.reason, .cooldown(until: now.addingTimeInterval(30 * 60)))
        XCTAssertEqual(text(soon), "Löst nicht aus: Cooldown bis 18:12")
        let later = evaluate(rule, .followUpdated, AutoState(follow: F.follow(delay: 9, trip: "2|REX5|0", at: now), ledger: ledger),
                             at: now.addingTimeInterval(31 * 60))
        XCTAssertTrue(later.fires)
    }

    // MARK: Milestone

    func testMilestoneFiresOncePerTicket() {
        let rule = F.rule(.milestone(percents: [50, 75, 100]))
        var ledger = AutoLedger()
        let state = AutoState(ticket: F.ticket(fraction: 0.52), ledger: ledger)
        let verdict = evaluate(rule, .committed, state)
        XCTAssertTrue(verdict.fires)
        XCTAssertEqual(verdict.firings.first?.title, "50 % geschafft")
        XCTAssertEqual(text(verdict), "Würde jetzt auslösen: 52 % amortisiert – 50 % ist erreicht und für dieses Ticket noch nicht gefeiert")
        ledger.apply(verdict.marks)
        ledger.apply(verdict.marks)   // applying twice changes nothing
        XCTAssertEqual(ledger.celebrated(ruleID: rule.id, ticketID: "T-2026"), [50])
        let again = evaluate(rule, .committed, AutoState(ticket: F.ticket(fraction: 0.55), ledger: ledger))
        XCTAssertFalse(again.fires)
        XCTAssertEqual(text(again), "Löst nicht aus: erst 55 % amortisiert, nächster Meilenstein 75 %")
        // The next ticket year starts over.
        let nextTicket = evaluate(rule, .committed, AutoState(ticket: F.ticket(fraction: 0.52, id: "T-2027"), ledger: ledger))
        XCTAssertTrue(nextTicket.fires)
    }

    func testMilestonesFireInOrderAndAJumpCelebratesTheHighest() {
        let rule = F.rule(.milestone(percents: [25, 50, 75, 100]))
        var ledger = AutoLedger()
        var titles: [String] = []
        for fraction in [0.10, 0.26, 0.30, 0.51, 1.04] {
            let verdict = evaluate(rule, .committed, AutoState(ticket: F.ticket(fraction: fraction), ledger: ledger))
            titles += verdict.firings.map(\.title)
            ledger.apply(verdict.marks)
        }
        XCTAssertEqual(titles, ["25 % geschafft", "50 % geschafft", "Dein Ticket hat sich rentiert"])
        XCTAssertEqual(ledger.celebrated(ruleID: rule.id, ticketID: "T-2026"), [25, 50, 75, 100])
        let done = evaluate(rule, .committed, AutoState(ticket: F.ticket(fraction: 1.2), ledger: ledger))
        XCTAssertEqual(done.reason, .milestonesDone(current: 120))
    }

    func testMilestoneBelowStaysSilent() {
        let verdict = evaluate(F.rule(.milestone(percents: [50])), .committed, AutoState(ticket: F.ticket(fraction: 0.4999)))
        XCTAssertFalse(verdict.fires)
        XCTAssertEqual(text(verdict), "Löst nicht aus: erst 49 % amortisiert, nächster Meilenstein 50 %")
        XCTAssertEqual(evaluate(F.rule(.milestone(percents: [50])), .committed, AutoState()).reason, .noTicket)
    }

    func testARuleSwitchedOnLateCelebratesWhatComesNext() {
        let rule = F.rule(.milestone(percents: [50, 75, 100]))
        var ledger = AutoLedger()
        ledger.seedMilestones(rule: rule, ticket: F.ticket(fraction: 0.61))
        XCTAssertFalse(evaluate(rule, .committed, AutoState(ticket: F.ticket(fraction: 0.62), ledger: ledger)).fires)
        let reached = evaluate(rule, .committed, AutoState(ticket: F.ticket(fraction: 0.76), ledger: ledger))
        XCTAssertEqual(reached.firings.map(\.title), ["75 % geschafft"])
    }

    // MARK: Trip logged

    func testTripLoggedFiresForAMatchingNewTrip() {
        let rule = F.rule(.tripLogged(AutoTripFilter(minValueEUR: 20)))
        let trip = F.trip(23.5, at: now)
        let verdict = evaluate(rule, .committed, AutoState(newTrips: [trip]))
        XCTAssertTrue(verdict.fires)
        XCTAssertEqual(verdict.firings.first?.title, "Fahrt ab € 20 erfasst")
        XCTAssertEqual(verdict.firings.first?.body, "St. Anton am Arlberg → Innsbruck Hbf · € 23,50")
        XCTAssertEqual(text(verdict), "Würde jetzt auslösen: St. Anton am Arlberg → Innsbruck Hbf · € 23,50 – passt zu „ab € 20“")
    }

    func testTripLoggedStaysSilentBelowTheMinimum() {
        let rule = F.rule(.tripLogged(AutoTripFilter(minValueEUR: 20)))
        let verdict = evaluate(rule, .committed, AutoState(newTrips: [F.trip(4.6, at: now)]))
        XCTAssertFalse(verdict.fires)
        XCTAssertEqual(text(verdict), "Löst nicht aus: die neue Fahrt (€ 4,60) liegt unter € 20")
        XCTAssertEqual(evaluate(rule, .committed, AutoState()).reason, .noNewTrip)
    }

    func testTripFilterRouteWorksInBothDirectionsAndModesMatchAnyLeg() {
        let route = AutoRouteRef(fromName: "Innsbruck Hbf", toName: "St. Anton am Arlberg", fromStationID: "at:81:2", toStationID: "at:81:1")
        let filter = AutoTripFilter(modes: [.bus], route: route)
        XCTAssertEqual(AutoRuleEngine.mismatch(of: F.trip(9, at: now), filter: filter), .mode(found: [.train], wanted: [.bus]))
        XCTAssertNil(AutoRuleEngine.mismatch(of: F.trip(9, at: now, modes: [.train, .bus]), filter: filter))
        let elsewhere = F.trip(9, at: now, from: "Linz Hbf", to: "Wien Hbf", fromID: "at:44:1", toID: "at:49:1", modes: [.bus])
        XCTAssertEqual(AutoRuleEngine.mismatch(of: elsewhere, filter: filter), .route(route))
        // Without station ids the names decide (case and spaces do not matter).
        let named = AutoRouteRef(fromName: "innsbruck hbf ", toName: "St. Anton am Arlberg")
        XCTAssertNil(AutoRuleEngine.mismatch(of: F.trip(9, at: now, fromID: nil, toID: nil), filter: AutoTripFilter(route: named)))
    }

    func testTheTestlaufOfTripLoggedReadsTheLastTrip() {
        let rule = F.rule(.tripLogged(AutoTripFilter(minValueEUR: 20)))
        let probe = evaluate(rule, .probe, AutoState(lastTrip: F.trip(4.6, at: now)))
        XCTAssertEqual(text(probe), "Löst nicht aus: deine letzte Fahrt (€ 4,60) liegt unter € 20")
        XCTAssertEqual(evaluate(rule, .probe, AutoState()).reason, .noTrip)
        let matched = evaluate(rule, .probe, AutoState(lastTrip: F.trip(31, at: now)))
        XCTAssertEqual(text(matched), "Würde jetzt auslösen: deine letzte Fahrt St. Anton am Arlberg → Innsbruck Hbf · € 31 – passt zu „ab € 20“")
    }

    // MARK: Ticket deadline

    func testDeadlineIsPlannedForNineOClockThirtyDaysBefore() {
        let rule = F.rule(.ticketDeadline(daysBefore: 30))
        let verdict = evaluate(rule, .probe, AutoState(ticket: F.ticket()))
        XCTAssertEqual(verdict.outcome, .at(F.at(2027, 1, 29, 9, 0)))
        XCTAssertEqual(text(verdict), "Würde am 29. Jän. um 09:00 auslösen: 30 Tage vor Ablauf von KlimaTicket Ö Klassik (gültig bis 28. Feb.)")
        let due = evaluate(rule, .slotDue(F.at(2027, 1, 29, 9, 0)), AutoState(ticket: F.ticket()), at: F.at(2027, 1, 29, 9, 0))
        XCTAssertTrue(due.fires)
        XCTAssertEqual(due.firings.first?.title, "Noch 30 Tage gültig")
        XCTAssertEqual(due.firings.first?.body, "KlimaTicket Ö Klassik gilt bis 28. Feb. – denk rechtzeitig an Verlängerung oder Kündigung.")
    }

    func testDeadlineAtMonthEndsAndOverDaylightSaving() {
        let rule = F.rule(.ticketDeadline(daysBefore: 30))
        // A ticket that ends on 31 March: 30 days before is 1 March (2027 has no 29 Feb).
        let march = F.ticket(start: F.at(2026, 4, 1), end: F.at(2027, 3, 31, 23, 59, 59))
        XCTAssertEqual(evaluate(rule, .probe, AutoState(ticket: march)).outcome, .at(F.at(2027, 3, 1, 9, 0)))
        // A ticket that ends on 28 April 2026: 30 days before is 29 March, the day clocks go forward – still 09:00 (07:00 UTC).
        let april = F.ticket(start: F.at(2025, 4, 29), end: F.at(2026, 4, 28, 23, 59, 59))
        let spring = evaluate(rule, .probe, AutoState(ticket: april), at: F.at(2026, 3, 1))
        guard case let .at(moment) = spring.outcome else { return XCTFail("planned") }
        XCTAssertEqual(F.utc(moment), "2026-03-29 07:00")
        // One day before the end of a leap February.
        let leap = F.ticket(start: F.at(2027, 3, 1), end: F.at(2028, 2, 29, 23, 59, 59))
        XCTAssertEqual(evaluate(F.rule(.ticketDeadline(daysBefore: 1)), .probe, AutoState(ticket: leap)).outcome, .at(F.at(2028, 2, 28, 9, 0)))
    }

    func testDeadlineThatPassedOrNoTicketStaysSilent() {
        let rule = F.rule(.ticketDeadline(daysBefore: 30))
        let passed = evaluate(rule, .probe, AutoState(ticket: F.ticket()), at: F.at(2027, 2, 10, 12, 0))
        XCTAssertEqual(text(passed), "Löst nicht aus: der Termin war am 29. Jän.")
        XCTAssertEqual(evaluate(rule, .probe, AutoState(ticket: F.ticket()), at: F.at(2027, 3, 5)).reason, .ticketEnded)
        XCTAssertEqual(evaluate(rule, .probe, AutoState()).reason, .noTicket)
    }

    func testQuietWeekendMovesADeadlineToFriday() {
        // 30 days before 28 Feb 2027 is Friday 29 Jan; 31 days before is Thursday 28 Jan; 36 days before is Saturday 23 Jan.
        let rule = F.rule(.ticketDeadline(daysBefore: 36))
        let quiet = evaluate(rule, .probe, AutoState(ticket: F.ticket(), quietWeekend: true))
        XCTAssertEqual(quiet.outcome, .at(F.at(2027, 1, 22, 9, 0)))
        XCTAssertTrue(text(quiet).hasSuffix("wegen „Wochenende ruhig“ schon am Freitag"))
        XCTAssertEqual(evaluate(rule, .probe, AutoState(ticket: F.ticket())).outcome, .at(F.at(2027, 1, 23, 9, 0)))
    }

    // MARK: Day without a trip

    func testDayWithoutTripFiresWhenTheDayHasNoTrip() {
        let rule = F.rule(.dayWithoutTrip(weekdays: AutoClock.workdays, minuteOfDay: 19 * 60),
                          actions: [.notify(title: "", body: ""), .openAddTrip(fromStationID: nil, toStationID: nil)])
        let probe = evaluate(rule, .probe, AutoState())
        XCTAssertEqual(text(probe), "Würde heute um 19:00 auslösen: heute ist noch keine Fahrt erfasst")
        let due = evaluate(rule, .slotDue(F.at(2026, 11, 12, 19, 0)), AutoState(), at: F.at(2026, 11, 12, 19, 0))
        XCTAssertTrue(due.fires)
        XCTAssertEqual(due.firings.first?.opensAddTrip, true)
        XCTAssertEqual(due.firings.first?.body, "Warst du heute mit den Öffis unterwegs? Tippe hier und trag die Fahrt nach.")
    }

    func testDayWithoutTripStaysQuietOnADayWithATrip() {
        let rule = F.rule(.dayWithoutTrip(weekdays: AutoClock.workdays, minuteOfDay: 19 * 60))
        let state = AutoState(tripDays: F.dayKeys(F.at(2026, 11, 12, 7, 20)))
        let probe = evaluate(rule, .probe, state)
        XCTAssertFalse(probe.fires)
        XCTAssertEqual(text(probe), "Löst heute nicht aus: heute ist schon eine Fahrt erfasst. Nächster Termin: morgen 19:00")
        XCTAssertFalse(evaluate(rule, .slotDue(F.at(2026, 11, 12, 19, 0)), state, at: F.at(2026, 11, 12, 19, 0)).fires)
    }

    func testDayWithoutTripAfterTodaysMomentNamesTheNextWeekday() {
        let rule = F.rule(.dayWithoutTrip(weekdays: AutoClock.workdays, minuteOfDay: 19 * 60))
        // Friday 13 Nov 20:10: the next working day is Monday.
        let probe = evaluate(rule, .probe, AutoState(), at: F.at(2026, 11, 13, 20, 10))
        XCTAssertEqual(probe.outcome, .at(F.at(2026, 11, 16, 19, 0)))
        XCTAssertEqual(text(probe), "Würde am Mo um 19:00 auslösen: wenn bis dahin keine Fahrt für diesen Tag erfasst ist")
        XCTAssertEqual(evaluate(F.rule(.dayWithoutTrip(weekdays: [], minuteOfDay: 600)), .probe, AutoState()).reason, .noWeekday)
    }

    // MARK: Conditions and quiet weekend

    func testWeekdayAndTimeWindowConditions() {
        let rule = F.rule(.followDelay(minutes: 5), conditions: [.weekdays(AutoClock.workdays), .timeWindow(startMinute: 22 * 60, endMinute: 6 * 60)])
        let state = AutoState(follow: F.follow(delay: 9, at: now))
        XCTAssertEqual(evaluate(rule, .followUpdated, state).reason, .outsideWindow(start: 22 * 60, end: 6 * 60))
        let lateNight = evaluate(rule, .followUpdated, state, at: F.at(2026, 11, 12, 23, 30))
        XCTAssertTrue(lateNight.fires)
        XCTAssertEqual(text(lateNight), "Würde jetzt auslösen: Verspätung 9 Min ist mindestens 5 Min (RJ 66, Ausstieg Innsbruck Hbf), Bedingungen erfüllt")
        let saturday = evaluate(rule, .followUpdated, state, at: F.at(2026, 11, 14, 23, 30))
        XCTAssertEqual(text(saturday), "Löst nicht aus: Samstag ist nicht gewählt")
    }

    func testValidTicketCondition() {
        let rule = F.rule(.tripLogged(AutoTripFilter()), conditions: [.validTicket])
        let trip = F.trip(5, at: now)
        XCTAssertEqual(evaluate(rule, .committed, AutoState(newTrips: [trip])).reason, .ticketInvalid)
        XCTAssertTrue(evaluate(rule, .committed, AutoState(ticket: F.ticket(), newTrips: [trip])).fires)
    }

    func testQuietWeekendSilencesEventsOnSaturday() {
        let rule = F.rule(.tripLogged(AutoTripFilter()))
        let saturday = F.at(2026, 11, 14, 10, 0)
        let verdict = evaluate(rule, .committed, AutoState(newTrips: [F.trip(5, at: saturday)], quietWeekend: true), at: saturday)
        XCTAssertEqual(text(verdict), "Löst nicht aus: „Wochenende ruhig“ ist an")
    }

    // MARK: Switch and Testlauf

    func testARuleThatIsOffIsSilentButTheTestlaufExplainsIt() {
        var rule = F.rule(.followDelay(minutes: 5))
        rule.isEnabled = false
        let state = AutoState(follow: F.follow(delay: 9, at: now))
        XCTAssertEqual(evaluate(rule, .followUpdated, state).reason, .ruleOff)
        XCTAssertTrue(evaluate(rule, .probe, state).fires)
    }

    func testTheTestlaufTextIsTheEnginesDecision() {
        let ledgerFired: AutoLedger = {
            var ledger = AutoLedger()
            ledger.apply([.followReported(ruleID: UUID(), tripID: "x")])
            return ledger
        }()
        let rules: [AutoRule] = AutoTriggerKind.allCases.map { F.rule($0.defaultTrigger) }
        let states = [
            AutoState(),
            AutoState(ticket: F.ticket(fraction: 0.8), tripDays: F.dayKeys(now), newTrips: [F.trip(25, at: now)], lastTrip: F.trip(25, at: now),
                      follow: F.follow(delay: 12, at: now), ledger: ledgerFired),
            AutoState(ticket: F.ticket(fraction: 0.1), newTrips: [F.trip(3, at: now)], lastTrip: F.trip(3, at: now),
                      follow: F.follow(delay: 1, at: now), quietWeekend: true),
        ]
        for rule in rules {
            for state in states {
                for event in [AutoEvent.probe, .committed, .followUpdated] {
                    let verdict = evaluate(rule, event, state)
                    let words = text(verdict)
                    XCTAssertEqual(words.hasPrefix("Würde"), verdict.fires, words)
                    XCTAssertEqual(words.hasPrefix("Löst"), !verdict.fires, words)
                    XCTAssertEqual(verdict.firings.isEmpty, verdict.outcome != .now, words)
                    XCTAssertTrue(verdict.firings.allSatisfy { $0.explanation == words }, words)
                }
            }
        }
    }
}
