import XCTest
@testable import KlimaCore

/// Availability states, German formatting and the number guard of the on-device assistant (docs/LOCAL_AI.md).
final class AssistantCoreTests: XCTestCase {
    func testAvailabilityPriority() {
        XCTAssertEqual(AssistantAvailabilityResolver.resolve(system: .available, supportsGerman: true, switchedOn: true), .available)
        XCTAssertEqual(AssistantAvailabilityResolver.resolve(system: .available, supportsGerman: false, switchedOn: true), .languageUnsupported)
        XCTAssertEqual(AssistantAvailabilityResolver.resolve(system: .appleIntelligenceNotEnabled, supportsGerman: true, switchedOn: true), .notEnabled)
        XCTAssertEqual(AssistantAvailabilityResolver.resolve(system: .deviceNotEligible, supportsGerman: true, switchedOn: true), .unsupportedDevice)
        XCTAssertEqual(AssistantAvailabilityResolver.resolve(system: .modelNotReady, supportsGerman: true, switchedOn: true), .modelNotReady)
        // The app switch wins over every system state, so a switched-off assistant never reads as "available".
        XCTAssertEqual(AssistantAvailabilityResolver.resolve(system: .available, supportsGerman: true, switchedOn: false), .switchedOff)
        XCTAssertEqual(AssistantAvailabilityResolver.resolve(system: .deviceNotEligible, supportsGerman: false, switchedOn: false), .switchedOff)
    }

    func testGermanFormatting() {
        XCTAssertEqual(AssistantFormat.euro(1400), "€ 1.400")
        XCTAssertEqual(AssistantFormat.euro(23.5), "€ 23,50")
        XCTAssertEqual(AssistantFormat.euro(-120), "€ -120")
        XCTAssertEqual(AssistantFormat.euro(1085.4), "€ 1.085")
        XCTAssertEqual(AssistantFormat.integer(1234567), "1.234.567")
        XCTAssertEqual(AssistantFormat.kilometres(1240.4), "1.240 km")
        var c = Calendar.vienna
        c.timeZone = TimeZone(identifier: "Europe/Vienna")!
        let date = c.date(from: DateComponents(year: 2026, month: 10, day: 4))!
        XCTAssertEqual(AssistantFormat.dayMonth(date, calendar: c), "04.10.")
    }

    func testNumberGuardNormalForms() {
        XCTAssertEqual(AssistantNumberGuard.tokens(in: "€ 1.400"), ["1400"])
        XCTAssertEqual(AssistantNumberGuard.tokens(in: "€ 1.400,50"), ["1400.5"])
        XCTAssertEqual(AssistantNumberGuard.tokens(in: "23,50 € und 23.50"), ["23.5", "23.5"])
        XCTAssertEqual(AssistantNumberGuard.tokens(in: "am 18.10. um 7:30 Uhr"), ["18.1", "7", "30"])
        XCTAssertEqual(AssistantNumberGuard.tokens(in: "CO₂ gespart: 180 kg"), ["180"])
        XCTAssertEqual(AssistantNumberGuard.tokens(in: "14.11.2026"), ["14.11", "2026"])
        XCTAssertEqual(AssistantNumberGuard.tokens(in: "Du hast 3. Oktober"), ["3"])
    }

    func testNumberGuardAcceptsOnlyFactNumbers() {
        let facts = ["Ticketpreis: € 1.400", "Wert bisher: € 1.085", "Fahrten: 12", "Break-even-Prognose: 14.11.", "Ticket: KlimaTicket 2026"]
        XCTAssertTrue(AssistantNumberGuard.accepts("Du hast 12 Fahrten im Wert von € 1.085 erfasst.", facts: facts))
        XCTAssertTrue(AssistantNumberGuard.accepts("Am 14.11. ist es so weit, das KlimaTicket 2026 rentiert sich.", facts: facts))
        // An invented figure, a rounded figure and an invented price all fail.
        XCTAssertEqual(AssistantNumberGuard.unknown(in: "Du hast 13 Fahrten gemacht.", facts: facts), ["13"])
        XCTAssertEqual(AssistantNumberGuard.unknown(in: "Rund 1.100 € fehlen.", facts: facts), ["1100"])
        XCTAssertFalse(AssistantNumberGuard.accepts("Der Preis liegt bei € 23,50.", facts: facts))
        XCTAssertTrue(AssistantNumberGuard.accepts("Ganz ohne Zahlen.", facts: facts))
    }

    func testDraftMergeKeepsSelfAndMarksModelContribution() {
        let rules = TripQueryDraft(destination: "Innsbruck", source: .rules)
        let model = TripQueryDraft(origin: "Wien", destination: "Graz", source: .model)
        let merged = rules.filled(from: model)
        XCTAssertEqual(merged.destination, "Innsbruck")
        XCTAssertEqual(merged.origin, "Wien")
        XCTAssertEqual(merged.source, .model)
        let nothing = rules.filled(from: TripQueryDraft(source: .model))
        XCTAssertEqual(nothing.source, .rules)
    }
}
