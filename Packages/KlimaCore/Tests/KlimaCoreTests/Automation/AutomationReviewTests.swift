import XCTest
@testable import KlimaCore

/// Automatik review: the rules show the Übersicht's percent and euros, a milestone fires on the real value, a past ticket
/// year celebrates nothing, a deadline moved to Friday says the days that are really left, the Testlauf and a save agree
/// on what „switching on“ forgets, and only the rules that reach their owner through iOS ask for the permission.
final class AutomationReviewTests: XCTestCase {
    private typealias F = AutomationFixtures
    private let cal = Calendar.vienna
    /// Thursday 12 Nov 2026, 17:42.
    private let now = AutomationFixtures.at(2026, 11, 12, 17, 42)

    private func evaluate(_ rule: AutoRule, _ event: AutoEvent, _ state: AutoState, at date: Date? = nil) -> AutoVerdict {
        AutoRuleEngine.evaluate(rule, event: event, state: state, now: date ?? now, calendar: cal)
    }

    private func text(_ verdict: AutoVerdict) -> String { AutoText.explanation(verdict, calendar: cal) }

    // MARK: Percent and euros as the Übersicht shows them

    func testPercentIsTheUbersichtsRounding() {
        // SummitFigures.percent: rounded below the break-even, never 100 before it, rounded down after it.
        let cases: [(Double, Int)] = [(0.614, 61), (0.616, 62), (0.495, 50), (0.996, 99), (0.999999, 99), (1.0, 100),
                                      (1.2, 120), (1.497, 149), (-0.1, 0), (.nan, 0), (.infinity, 0)]
        for (fraction, shown) in cases {
            XCTAssertEqual(F.ticket(fraction: fraction).percent, shown, "\(fraction)")
        }
    }

    func testShownValueNeverReachesThePriceBeforeTheBreakEven() {
        XCTAssertEqual(F.ticket(fraction: 0.614).shownValueEUR, 860)
        let almost = AutoTicketFact(id: "T", name: "T", start: now, end: now, amortizedFraction: 1399.6 / 1400, price: 1400, value: 1399.6)
        XCTAssertEqual(almost.shownValueEUR, 1399)
        let paid = AutoTicketFact(id: "T", name: "T", start: now, end: now, amortizedFraction: 1.0, price: 1400, value: 1400)
        XCTAssertEqual(paid.shownValueEUR, 1400)
    }

    // MARK: Milestones

    func testAMilestoneFiresOnTheRealValueAndSaysTheShownPercent() {
        let rule = F.rule(.milestone(percents: [50, 100]))
        // 49,6 %: the Übersicht says 50 %, the milestone is still ahead – and the row says so instead of „jetzt 50 %“.
        let close = AutoState(ticket: F.ticket(fraction: 0.496))
        XCTAssertFalse(evaluate(rule, .committed, close).fires)
        XCTAssertEqual(AutoText.nextLine(rule: rule, plan: AutoPlan(), state: close, now: now, calendar: cal),
                       "nächster Meilenstein: 50 % · knapp davor")
        // 61,6 %: celebrated with the 62 % of the Übersicht.
        let reached = evaluate(rule, .committed, AutoState(ticket: F.ticket(fraction: 0.616)))
        XCTAssertEqual(reached.firings.first?.body, "KlimaTicket Ö Klassik ist zu 62 % amortisiert. Weiter so!")
        XCTAssertEqual(AutoText.nextLine(rule: rule, plan: AutoPlan(), state: AutoState(ticket: F.ticket(fraction: 0.616)), now: now, calendar: cal),
                       "nächster Meilenstein: 100 % · jetzt 62 %")
        // 99,7 %: never „rentiert“ before the break-even.
        var ledger = AutoLedger()
        ledger.apply([.milestones(ruleID: rule.id, ticketID: "T-2026", percents: [50])])
        let summit = evaluate(rule, .committed, AutoState(ticket: F.ticket(fraction: 0.997), ledger: ledger))
        XCTAssertFalse(summit.fires)
        XCTAssertEqual(text(summit), "Löst nicht aus: erst 99 % amortisiert, nächster Meilenstein 100 %")
        let paid = evaluate(rule, .committed, AutoState(ticket: F.ticket(fraction: 1.0), ledger: ledger))
        XCTAssertEqual(paid.firings.first?.title, "Dein Ticket hat sich rentiert")
    }

    func testAPastTicketYearCelebratesNothing() {
        // Last year's ticket, still selected in the Ticket tab, at 120 %: no „rentiert“ for something long gone.
        let rule = F.rule(.milestone(percents: [25, 50, 75, 100]))
        let past = F.ticket(fraction: 1.2, id: "T-2025", start: F.at(2025, 3, 1), end: F.at(2026, 2, 28, 23, 59, 59))
        let verdict = evaluate(rule, .committed, AutoState(ticket: past))
        XCTAssertFalse(verdict.fires)
        XCTAssertEqual(text(verdict), "Löst nicht aus: dein Ticket ist abgelaufen")
        XCTAssertEqual(AutoText.nextLine(rule: rule, plan: AutoPlan(), state: AutoState(ticket: past), now: now, calendar: cal),
                       "dein Ticket ist abgelaufen")
        // The last second of the ticket still counts.
        let lastSecond = F.ticket(fraction: 0.3, end: now)
        XCTAssertTrue(evaluate(rule, .committed, AutoState(ticket: lastSecond)).fires)
    }

    func testSwitchingOnIsOneQuestionForTheSaveAndTheTestlauf() {
        let on = F.rule(.milestone(percents: [50, 75]))
        var off = on
        off.isEnabled = false
        var wider = on
        wider.trigger = .milestone(percents: [25, 50, 75])
        XCTAssertTrue(AutoLedger.switchesOn(previous: nil, next: on))
        XCTAssertTrue(AutoLedger.switchesOn(previous: off, next: on))
        XCTAssertTrue(AutoLedger.switchesOn(previous: on, next: wider))
        XCTAssertFalse(AutoLedger.switchesOn(previous: on, next: on))
        XCTAssertFalse(AutoLedger.switchesOn(previous: nil, next: off))
        // What a rule switched on at 61 % remembers: 50 % is not news, 75 % is.
        var ledger = AutoLedger()
        ledger.seedMilestones(rule: on, ticket: F.ticket(fraction: 0.61))
        let probe = evaluate(on, .probe, AutoState(ticket: F.ticket(fraction: 0.61), ledger: ledger))
        XCTAssertEqual(text(probe), "Löst nicht aus: erst 61 % amortisiert, nächster Meilenstein 75 %")
        // 49,6 % is not reached yet, so it stays news after switching on.
        var close = AutoLedger()
        close.seedMilestones(rule: on, ticket: F.ticket(fraction: 0.496))
        XCTAssertEqual(close.celebrated(ruleID: on.id, ticketID: "T-2026"), [])
    }

    // MARK: Deadline moved for „Wochenende ruhig“

    func testADeadlineMovedToFridaySaysTheDaysReallyLeft() {
        // The ticket ends on Saturday 27 Feb 2027. „läuft heute ab“ would ring on Saturday; quiet weekends move it to Friday,
        // when the ticket still has one more day.
        let saturdayEnd = F.ticket(end: F.at(2027, 2, 27, 23, 59, 59))
        let today = F.rule(.ticketDeadline(daysBefore: 0))
        let state = AutoState(ticket: saturdayEnd, quietWeekend: true)
        let probe = evaluate(today, .probe, state)
        XCTAssertEqual(probe.outcome, .at(F.at(2027, 2, 26, 9, 0)))
        XCTAssertEqual(text(probe), "Würde am 26. Feb. um 09:00 auslösen: KlimaTicket Ö Klassik läuft morgen ab (27. Feb.), wegen „Wochenende ruhig“ schon am Freitag")
        let due = evaluate(today, .slotDue(F.at(2027, 2, 26, 9, 0)), state, at: F.at(2027, 2, 26, 9, 0))
        XCTAssertEqual(due.firings.first?.title, "Dein Ticket läuft morgen ab")
        let slot = AutoRuleScheduler.candidates(for: today, state: state, now: now, calendar: cal).first
        XCTAssertEqual(slot?.title, "Dein Ticket läuft morgen ab")
        // 36 days before 28 Feb is Saturday 23 Jan: on Friday 22 Jan there are 37 days left.
        let far = AutoRuleScheduler.candidates(for: F.rule(.ticketDeadline(daysBefore: 36)),
                                               state: AutoState(ticket: F.ticket(), quietWeekend: true), now: now, calendar: cal).first
        XCTAssertEqual(far?.fireAt, F.at(2027, 1, 22, 9, 0))
        XCTAssertEqual(far?.title, "Noch 37 Tage gültig")
        // Not moved: the chosen days, as before.
        XCTAssertEqual(AutoRuleScheduler.candidates(for: F.rule(.ticketDeadline(daysBefore: 30)),
                                                    state: AutoState(ticket: F.ticket(), quietWeekend: true), now: now, calendar: cal).first?.title,
                       "Noch 30 Tage gültig")
    }

    // MARK: Notifications

    func testOnlyRulesThatReachTheirOwnerThroughIOSNeedThePermission() {
        XCTAssertEqual(AutoTriggerKind.allCases.filter(\.needsNotifications), [.ticketDeadline, .dayWithoutTrip, .followDelay])
        XCTAssertEqual(AutoText.notificationsBlockedLine(denied: true), "Mitteilungen in iOS aus – meldet sich nicht")
        XCTAssertEqual(AutoText.notificationsBlockedLine(denied: false), "braucht die Erlaubnis für Mitteilungen")
    }
}
