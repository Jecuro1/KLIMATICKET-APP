import XCTest
@testable import KlimaCore

/// Automatik: the stored values – rule JSON round trip, an unknown trigger dropped without a crash, garbage, normalisation,
/// ledger and log, the sentence and the templates.
final class AutomationModelTests: XCTestCase {
    private typealias F = AutomationFixtures

    private func allKindsBook() -> AutoRuleBook {
        let route = AutoRouteRef(fromName: "Linz Hbf", toName: "Wien Hbf", fromStationID: "at:44:1", toStationID: "at:49:1")
        return AutoRuleBook(isEnabled: true, quietWeekend: true, rules: [
            F.rule(.ticketDeadline(daysBefore: 30), name: "Vor Ablauf"),
            F.rule(.milestone(percents: [25, 100]), conditions: [.timeWindow(startMinute: 420, endMinute: 1320)], name: "Gipfel"),
            F.rule(.dayWithoutTrip(weekdays: [.monday, .friday], minuteOfDay: 1140), conditions: [.validTicket], name: "Abend",
                   actions: [.notify(title: "Eigener Titel", body: ""), .openAddTrip(fromStationID: "at:44:1", toStationID: nil)]),
            F.rule(.followDelay(minutes: 10), conditions: [.weekdays([.saturday])], cooldown: 30, name: "Verspätung",
                   actions: [.notify(title: "", body: ""), .openShortcut(name: "Heimweg")]),
            F.rule(.tripLogged(AutoTripFilter(modes: [.bus, .tram], minValueEUR: 20, route: route)), name: "Große Fahrt"),
        ])
    }

    func testRuleBookRoundTrip() throws {
        let book = allKindsBook()
        let data = try XCTUnwrap(book.encoded())
        XCTAssertEqual(AutoRuleBook.decode(data), book)
    }

    func testAnUnknownTriggerIsDroppedWithoutACrash() throws {
        let good = F.rule(.followDelay(minutes: 5), name: "Bleibt")
        let goodJSON = String(data: try JSONEncoder().encode(good), encoding: .utf8) ?? ""
        let json = """
        {"version": 2, "isEnabled": true, "rules": [
          {"id": "\(UUID().uuidString)", "name": "Aus der Zukunft", "isEnabled": true,
           "trigger": {"type": "usualTime", "weekday": 1}, "conditions": [], "actions": [], "cooldownMinutes": 0, "createdAt": 0},
          {"id": "kaputt"},
          \(goodJSON)
        ]}
        """
        let book = AutoRuleBook.decode(Data(json.utf8))
        XCTAssertEqual(book.rules.map(\.name), ["Bleibt"])
        XCTAssertTrue(book.isEnabled)
    }

    func testGarbageGivesNoRules() {
        XCTAssertEqual(AutoRuleBook.decode(Data("nicht json".utf8)).rules, [])
        XCTAssertEqual(AutoRuleBook.decode(nil), AutoRuleBook())
        XCTAssertEqual(AutoRuleBook.decode(Data("{\"rules\": 5}".utf8)).rules, [])
        XCTAssertEqual(AutoLedger.decode(Data("[]".utf8)), AutoLedger())
        XCTAssertEqual(AutoLog.decode(Data("{".utf8)).entries, [])
    }

    func testAnUnknownConditionSwitchesTheRuleOff() throws {
        let rule = F.rule(.followDelay(minutes: 5), conditions: [.weekdays(AutoClock.workdays)])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(rule)) as? [String: Any])
        object["conditions"] = [["type": "nurBeiSonne"], ["type": "weekdays", "weekdays": [0, 1, 2, 3, 4]]]
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(AutoRule.self, from: data)
        XCTAssertFalse(decoded.isEnabled, "a rule that lost a condition would fire more often than chosen")
        XCTAssertEqual(decoded.conditions, [.weekdays(AutoClock.workdays)])
    }

    func testNormalisationKeepsValuesInRange() {
        var rule = F.rule(.milestone(percents: [33, 50]), conditions: [.noTripToday, .weekdays([.monday]), .weekdays([.friday])],
                          cooldown: 90, name: "   ", actions: [.openAddTrip(fromStationID: nil, toStationID: nil)])
        rule = rule.normalized
        XCTAssertEqual(rule.trigger, .milestone(percents: [50]))
        XCTAssertEqual(rule.conditions, [.weekdays([.monday])], "noTripToday means nothing after a save; one condition per kind")
        XCTAssertEqual(rule.actions.first, .notify(title: "", body: ""))
        XCTAssertEqual(rule.cooldownMinutes, 0, "a milestone has no cooldown")
        XCTAssertEqual(rule.name, "Meilensteine feiern")
        XCTAssertEqual(AutoTrigger.dayWithoutTrip(weekdays: [], minuteOfDay: 5000).normalized, .dayWithoutTrip(weekdays: [], minuteOfDay: 1439))
    }

    func testLedgerRoundTripAndPrune() throws {
        let keep = UUID(), gone = UUID()
        var ledger = AutoLedger(tripWatermark: F.at(2026, 11, 12, 8))
        ledger.apply([.milestones(ruleID: keep, ticketID: "T", percents: [25, 50]), .milestones(ruleID: gone, ticketID: "T", percents: [25]),
                      .followReported(ruleID: gone, tripID: "x"), .fired(ruleID: keep, at: F.at(2026, 11, 12, 9))])
        let decoded = AutoLedger.decode(try JSONEncoder().encode(ledger))
        XCTAssertEqual(decoded, ledger)
        ledger.prune(keeping: [keep])
        XCTAssertEqual(ledger.celebrated(ruleID: keep, ticketID: "T"), [25, 50])
        XCTAssertEqual(ledger.celebrated(ruleID: gone, ticketID: "T"), [])
        XCTAssertTrue(ledger.followReported.isEmpty)
    }

    func testLogKeepsTheNewestThirtyOnce() {
        var log = AutoLog()
        let rule = UUID()
        for i in 0..<35 {
            log.record(AutoLogEntry(id: "e\(i)", ruleID: rule, ruleName: "R", at: F.at(2026, 11, 1).addingTimeInterval(Double(i) * 60),
                                    title: "T", detail: "D", channel: .inApp))
        }
        XCTAssertFalse(log.record(AutoLogEntry(id: "e34", ruleID: rule, ruleName: "R", at: F.at(2027, 1, 1), title: "", detail: "", channel: .delivered)))
        XCTAssertEqual(log.entries.count, AutoLog.limit)
        XCTAssertEqual(log.entries.first?.id, "e34")
        XCTAssertEqual(log.entries.last?.id, "e5")
        XCTAssertEqual(AutoLog.decode(try? JSONEncoder().encode(log)), log)
    }

    func testRuleSentences() {
        let book = allKindsBook()
        XCTAssertEqual(book.rules.map(AutoText.sentence), [
            "Wenn mein Ticket in 30 Tagen abläuft, dann sag es mir.",
            "Wenn mein Ticket 25 oder 100 % amortisiert ist und es zwischen 07:00 und 22:00 ist, dann sag es mir.",
            "Wenn Mo, Fr um 19:00 noch keine Fahrt erfasst ist und ein Ticket gilt, dann erinnere mich und öffne „Fahrt erfassen“.",
            "Wenn meine verfolgte Fahrt 10 Min Verspätung hat und es Sa ist, dann sag es mir und biete den Kurzbefehl „Heimweg“ an.",
            "Wenn ich eine Fahrt ab € 20 mit Bim oder Bus auf Linz Hbf ⇄ Wien Hbf erfasse, dann sag es mir.",
        ])
        XCTAssertEqual(AutoText.sentence(F.rule(.dayWithoutTrip(weekdays: AutoClock.workdays, minuteOfDay: 1140))),
                       "Wenn Mo–Fr um 19:00 noch keine Fahrt erfasst ist, dann sag es mir.")
    }

    func testEuroAndDates() {
        XCTAssertEqual(AutoText.euro(20), "€ 20")
        XCTAssertEqual(AutoText.euro(1400), "€ 1.400")
        XCTAssertEqual(AutoText.euro(23.5), "€ 23,50")
        XCTAssertEqual(AutoText.euro(1234567.05), "€ 1.234.567,05")
        XCTAssertEqual(AutoText.dateText(F.at(2027, 1, 29), calendar: .vienna), "29. Jän.")
        XCTAssertEqual(AutoText.dateText(F.at(2027, 3, 1), calendar: .vienna), "1. März")
        let now = F.at(2026, 11, 12, 17, 42)
        XCTAssertEqual(AutoText.whenShort(F.at(2026, 11, 12, 19), now: now, calendar: .vienna), "heute 19:00")
        XCTAssertEqual(AutoText.whenShort(F.at(2026, 11, 13, 19), now: now, calendar: .vienna), "morgen 19:00")
        XCTAssertEqual(AutoText.whenShort(F.at(2026, 11, 16, 19), now: now, calendar: .vienna), "Mo 19:00")
        XCTAssertEqual(AutoText.whenShort(F.at(2026, 11, 19, 19), now: now, calendar: .vienna), "19. Nov. 19:00")
    }

    func testTemplates() {
        let now = F.at(2026, 11, 12)
        XCTAssertEqual(AutoTemplates.all.count, 6)
        XCTAssertEqual(Set(AutoTemplates.all.map(\.id)).count, 6)
        let rules = AutoTemplates.all.compactMap { $0.makeRule(now: now) }
        XCTAssertEqual(rules.count, 5, "„Wochenende ruhig“ is a switch, not a rule")
        XCTAssertEqual(Set(rules.map(\.trigger.kind)), Set(AutoTriggerKind.allCases))
        XCTAssertTrue(rules.allSatisfy { $0.normalized == $0 }, "templates are already normalised")
        XCTAssertTrue(rules.allSatisfy { $0.templateID != nil })
    }
}
