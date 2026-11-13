import XCTest
@testable import KlimaCore

/// Automatik: the planned notices – identifiers, 14 days, Vienna time over both daylight-saving changes, the 16-place ceiling
/// with its warning (40 rules), the fair share between rules, and reconcile after a logged trip.
final class AutomationSchedulerTests: XCTestCase {
    private typealias F = AutomationFixtures
    private let cal = Calendar.vienna
    private let now = AutomationFixtures.at(2026, 11, 12, 17, 42)   // Thursday

    private func evening(_ days: Set<RouteWeekday> = AutoClock.workdays, minute: Int = 19 * 60, id: UUID = UUID()) -> AutoRule {
        F.rule(.dayWithoutTrip(weekdays: days, minuteOfDay: minute), name: "Abendcheck", id: id)
    }

    // MARK: Identifiers

    func testIdentifierFormat() {
        let id = UUID(uuidString: "6F1A2B3C-0000-4000-8000-000000000001")!
        let identifier = AutoRuleScheduler.identifier(ruleID: id, day: F.at(2026, 11, 16, 19, 0), calendar: cal)
        XCTAssertEqual(identifier, "rule.6F1A2B3C-0000-4000-8000-000000000001.20261116")
        XCTAssertEqual(AutoRuleScheduler.parse(identifier)?.ruleID, id)
        XCTAssertEqual(AutoRuleScheduler.parse(identifier)?.dayKey, "20261116")
        let immediate = AutoRuleScheduler.immediateIdentifier(ruleID: id, at: F.at(2026, 11, 16, 7, 5, 9), calendar: cal)
        XCTAssertEqual(immediate, "rule.6F1A2B3C-0000-4000-8000-000000000001.20261116.070509")
        XCTAssertNil(AutoRuleScheduler.parse(immediate), "a notice sent at once is never mistaken for a planned one")
        XCTAssertEqual(AutoRuleScheduler.ruleID(of: immediate), id)
        XCTAssertNil(AutoRuleScheduler.parse("route.6F1A2B3C-0000-4000-8000-000000000001.20261116"))
        XCTAssertNil(AutoRuleScheduler.parse("rule.not-a-uuid.20261116"))
        XCTAssertNil(AutoRuleScheduler.parse("rule.6F1A2B3C-0000-4000-8000-000000000001.2026111"))
    }

    func testTheAlarmsScreenFilesRuleNoticesUnderAutomatik() {
        XCTAssertEqual(AlarmIdentifier.kind(of: "rule.6F1A2B3C-0000-4000-8000-000000000001.20261116"), .automation)
        XCTAssertEqual(AlarmIdentifier.groupKey(of: "rule.6F1A2B3C-0000-4000-8000-000000000001.20261116"),
                       "rule.6F1A2B3C-0000-4000-8000-000000000001")
        XCTAssertEqual(AlarmIdentifier.kind(of: "route.ABC.0"), .routeReminder)
    }

    // MARK: Fourteen days

    func testWorkdayEveningsForTwoWeeks() {
        let rule = evening()
        let slots = AutoRuleScheduler.candidates(for: rule, state: AutoState(), now: now, calendar: cal)
        // Thu 12 … Wed 25 Nov: 10 working days, today's 19:00 still ahead.
        XCTAssertEqual(slots.count, 10)
        XCTAssertEqual(slots.first?.fireAt, F.at(2026, 11, 12, 19, 0))
        XCTAssertEqual(slots.last?.fireAt, F.at(2026, 11, 25, 19, 0))
        XCTAssertTrue(slots.allSatisfy { AutoClock.minuteOfDay($0.fireAt, calendar: cal) == 19 * 60 })
        XCTAssertFalse(slots.contains { AutoClock.weekend.contains(AutoClock.weekday($0.fireAt, calendar: cal)) })
        XCTAssertEqual(slots.first?.id, AutoRuleScheduler.identifier(ruleID: rule.id, day: now, calendar: cal))
        XCTAssertEqual(slots.first?.title, "Heute noch keine Fahrt erfasst")
        // After 19:00 today is over.
        let late = AutoRuleScheduler.candidates(for: rule, state: AutoState(), now: F.at(2026, 11, 12, 19, 0), calendar: cal)
        XCTAssertEqual(late.first?.fireAt, F.at(2026, 11, 13, 19, 0))
    }

    func testEveningsKeepTheirClockOverTheSpringChange() {
        let daily = evening(Set(RouteWeekday.allCases))
        let slots = AutoRuleScheduler.candidates(for: daily, state: AutoState(), now: F.at(2026, 3, 27, 8, 0), calendar: cal)
        let utc = slots.prefix(4).map { F.utc($0.fireAt) }
        XCTAssertEqual(utc, ["2026-03-27 18:00", "2026-03-28 18:00", "2026-03-29 17:00", "2026-03-30 17:00"])
        XCTAssertEqual(Set(slots.map(\.id)).count, slots.count, "one notice per day")
    }

    func testEveningsKeepTheirClockOverTheAutumnChange() {
        let daily = evening(Set(RouteWeekday.allCases))
        let slots = AutoRuleScheduler.candidates(for: daily, state: AutoState(), now: F.at(2026, 10, 23, 8, 0), calendar: cal)
        let utc = slots.prefix(4).map { F.utc($0.fireAt) }
        XCTAssertEqual(utc, ["2026-10-23 17:00", "2026-10-24 17:00", "2026-10-25 18:00", "2026-10-26 18:00"])
    }

    func testAClockTimeInsideTheGapOrTheRepeatIsPlannedOnce() {
        // 02:30 does not exist on 29 March and exists twice on 25 October: one notice each day, never two.
        let night = evening(Set(RouteWeekday.allCases), minute: 2 * 60 + 30)
        let spring = AutoRuleScheduler.candidates(for: night, state: AutoState(), now: F.at(2026, 3, 28, 12, 0), calendar: cal)
        let onTheDay = spring.filter { AutoClock.dayKey($0.fireAt, calendar: cal) == "20260329" }
        XCTAssertEqual(onTheDay.count, 1)
        XCTAssertEqual(onTheDay.first.map { F.utc($0.fireAt) }, "2026-03-29 01:30")   // 03:30 summer time, after the gap
        let autumn = AutoRuleScheduler.candidates(for: night, state: AutoState(), now: F.at(2026, 10, 24, 12, 0), calendar: cal)
        XCTAssertEqual(autumn.filter { AutoClock.dayKey($0.fireAt, calendar: cal) == "20261025" }.count, 1)
    }

    func testADayWithATripIsNotPlannedAndQuietWeekendSkipsSaturday() {
        let daily = evening(Set(RouteWeekday.allCases))
        let state = AutoState(tripDays: F.dayKeys(F.at(2026, 11, 12, 7, 0), F.at(2026, 11, 13, 8, 0)), quietWeekend: true)
        let slots = AutoRuleScheduler.candidates(for: daily, state: state, now: now, calendar: cal)
        XCTAssertEqual(slots.first?.fireAt, F.at(2026, 11, 16, 19, 0))   // Thu and Fri have trips, Sat and Sun are quiet
    }

    func testTheDeadlineIsOneSlotHoweverFarAway() {
        let rule = F.rule(.ticketDeadline(daysBefore: 30))
        let slots = AutoRuleScheduler.candidates(for: rule, state: AutoState(ticket: F.ticket()), now: now, calendar: cal)
        XCTAssertEqual(slots.map(\.fireAt), [F.at(2027, 1, 29, 9, 0)])
        XCTAssertEqual(slots.first?.id, AutoRuleScheduler.identifier(ruleID: rule.id, day: F.at(2027, 1, 29), calendar: cal))
        XCTAssertTrue(AutoRuleScheduler.candidates(for: rule, state: AutoState(), now: now, calendar: cal).isEmpty)
    }

    func testEventTriggersAreNeverPlanned() {
        for kind in [AutoTriggerKind.milestone, .followDelay, .tripLogged] {
            XCTAssertTrue(AutoRuleScheduler.candidates(for: F.rule(kind.defaultTrigger), state: AutoState(ticket: F.ticket()), now: now, calendar: cal).isEmpty)
        }
    }

    // MARK: Ceiling

    func testFortyRulesStayUnderTheCeilingWithAVisibleWarning() {
        let rules = (0..<40).map { _ in evening(Set(RouteWeekday.allCases)) }
        let plan = AutoRuleScheduler.plan(rules: rules, state: AutoState(), now: now, calendar: cal)
        XCTAssertEqual(plan.slots.count, AutoRuleScheduler.slotCeiling)
        XCTAssertEqual(plan.slots.count, 16)
        XCTAssertEqual(Set(plan.slots.map(\.ruleID)).count, 16, "each rule gets its first moment before any rule gets a second")
        XCTAssertEqual(plan.rulesWithoutSlot.count, 24)
        XCTAssertEqual(plan.overflow.count, 40 * 14 - 16)
        XCTAssertTrue(plan.isOverCeiling)
        let names = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0.name) })
        XCTAssertEqual(AutoText.budgetWarning(plan, ruleNames: names),
                       "Mehr Termine als Plätze: 544 Termine warten auf einen der 16 Plätze. Sie rücken nach, wenn du die App öffnest und ein Platz frei ist. 24 Regeln haben gerade keinen Platz.")
        XCTAssertTrue(plan.slots == plan.slots.sorted { $0.fireAt < $1.fireAt || ($0.fireAt == $1.fireAt && $0.id < $1.id) })
    }

    func testAFarDeadlineIsNotPushedOutByDailyRules() {
        let daily = evening(Set(RouteWeekday.allCases))
        let deadline = F.rule(.ticketDeadline(daysBefore: 30))
        let plan = AutoRuleScheduler.plan(rules: [daily, daily.withID(UUID()), deadline], state: AutoState(ticket: F.ticket()), now: now, calendar: cal)
        XCTAssertEqual(plan.slots.count, 16)
        XCTAssertTrue(plan.slots.contains { $0.ruleID == deadline.id })
        XCTAssertEqual(plan.next(for: deadline.id), F.at(2027, 1, 29, 9, 0))
        XCTAssertNil(AutoText.budgetWarning(AutoRuleScheduler.plan(rules: [deadline], state: AutoState(ticket: F.ticket()), now: now, calendar: cal),
                                            ruleNames: [:]))
    }

    func testRulesThatAreOffOrTheMasterSwitchPlanNothing() {
        var off = evening()
        off.isEnabled = false
        XCTAssertTrue(AutoRuleScheduler.plan(rules: [off], state: AutoState(), now: now, calendar: cal).slots.isEmpty)
        let book = AutoRuleBook(isEnabled: false, rules: [evening()])
        XCTAssertTrue(AutoRuleScheduler.plan(rules: book.activeRules, state: AutoState(), now: now, calendar: cal).slots.isEmpty)
    }

    // MARK: Reconcile

    func testReconcileCancelsTodaysSlotOnceATripIsLogged() {
        let rule = evening()
        let before = AutoRuleScheduler.plan(rules: [rule], state: AutoState(), now: now, calendar: cal)
        let pending = before.slots.map { AutoPendingSlot(id: $0.id, title: $0.title, body: $0.body, fireAt: $0.fireAt) }
        let withTrip = AutoState(tripDays: F.dayKeys(now))
        let after = AutoRuleScheduler.plan(rules: [rule], state: withTrip, now: now, calendar: cal)
        let changes = AutoRuleScheduler.reconcile(pending: pending, plan: after, state: withTrip, calendar: cal)
        let today = AutoRuleScheduler.identifier(ruleID: rule.id, day: now, calendar: cal)
        XCTAssertEqual(changes.toRemove, [today])
        XCTAssertTrue(changes.toAdd.isEmpty)
        XCTAssertEqual(changes.cancelledForTrip.map(\.id), [today])
    }

    func testReconcileKeepsWhatIsRightReplacesWhatChangedAndLeavesOtherNoticesAlone() {
        let rule = evening()
        let plan = AutoRuleScheduler.plan(rules: [rule], state: AutoState(), now: now, calendar: cal)
        var pending = plan.slots.map { AutoPendingSlot(id: $0.id, title: $0.title, body: $0.body, fireAt: $0.fireAt) }
        pending[1].title = "Alter Titel"
        pending.append(AutoPendingSlot(id: "route.ABC.0", title: "Abfahrt in 10 Min", body: "", fireAt: now))
        pending.append(AutoPendingSlot(id: "rule.\(UUID().uuidString).20261113", title: "Gelöschte Regel", body: "", fireAt: F.at(2026, 11, 13, 19, 0)))
        let changes = AutoRuleScheduler.reconcile(pending: pending, plan: plan, state: AutoState(), calendar: cal)
        XCTAssertEqual(changes.toRemove.count, 2)
        XCTAssertTrue(changes.toRemove.contains(plan.slots[1].id))
        XCTAssertFalse(changes.toRemove.contains("route.ABC.0"))
        XCTAssertEqual(changes.toAdd.map(\.id), [plan.slots[1].id])
        XCTAssertTrue(changes.cancelledForTrip.isEmpty)
    }

    func testTheNextLineOfARow() {
        let rule = evening()
        let plan = AutoRuleScheduler.plan(rules: [rule], state: AutoState(), now: F.at(2026, 11, 13, 20, 0), calendar: cal)
        XCTAssertEqual(AutoText.nextLine(rule: rule, plan: plan, state: AutoState(), now: F.at(2026, 11, 13, 20, 0), calendar: cal),
                       "nächste: Mo 19:00")
        let follow = F.rule(.followDelay(minutes: 10))
        XCTAssertEqual(AutoText.nextLine(rule: follow, plan: plan, state: AutoState(), now: now, calendar: cal), "wartet auf „Live verfolgen“")
        let milestone = F.rule(.milestone(percents: [50, 75, 100]))
        XCTAssertEqual(AutoText.nextLine(rule: milestone, plan: plan, state: AutoState(ticket: F.ticket(fraction: 0.61)), now: now, calendar: cal),
                       "nächster Meilenstein: 75 % · jetzt 61 %")
    }
}

private extension AutoRule {
    func withID(_ id: UUID) -> AutoRule {
        var copy = self
        copy.id = id
        return copy
    }
}
