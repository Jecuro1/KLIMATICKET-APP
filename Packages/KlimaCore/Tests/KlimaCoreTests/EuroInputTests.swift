import XCTest
@testable import KlimaCore

/// The trip editor's price field: comma and dot, live normalising, plausibility hints.
final class EuroInputTests: XCTestCase {
    func testParseAcceptsCommaAndDot() {
        XCTAssertEqual(EuroInput.parse("24,90"), 24.9)
        XCTAssertEqual(EuroInput.parse("24.90"), 24.9)
        XCTAssertEqual(EuroInput.parse("24.9"), 24.9)
        XCTAssertEqual(EuroInput.parse("24,9"), 24.9)
        XCTAssertEqual(EuroInput.parse("24"), 24)
        XCTAssertEqual(EuroInput.parse("24,"), 24)
        XCTAssertEqual(EuroInput.parse(",5"), 0.5)
        XCTAssertEqual(EuroInput.parse("€ 12,30"), 12.3)
        XCTAssertEqual(EuroInput.parse("12,30 €"), 12.3)
        XCTAssertEqual(EuroInput.parse("1,506"), 1.51, "rounded to cents")
    }

    func testParseGrouping() {
        XCTAssertEqual(EuroInput.parse("1.024,50"), 1024.5)
        XCTAssertEqual(EuroInput.parse("1,024.50"), 1024.5)
        XCTAssertEqual(EuroInput.parse("1 024,50"), 1024.5)
        XCTAssertEqual(EuroInput.parse("1\u{00A0}024,50"), 1024.5)
        XCTAssertEqual(EuroInput.parse("1.500"), 1500, "a dot before three digits groups thousands in de-AT")
        XCTAssertEqual(EuroInput.parse("0.500"), 0.5, "… but not after a leading zero")
        XCTAssertEqual(EuroInput.parse("1.234.5"), 1234.5)
    }

    func testParseRejects() {
        XCTAssertNil(EuroInput.parse(""))
        XCTAssertNil(EuroInput.parse("€"))
        XCTAssertNil(EuroInput.parse(","))
        XCTAssertNil(EuroInput.parse("0"))
        XCTAssertNil(EuroInput.parse("0,00"))
        XCTAssertNil(EuroInput.parse("12.345,00"), "above the field's range")
        XCTAssertNil(EuroInput.parse("abc"))
    }

    func testLiveNormalisesWhileTyping() {
        XCTAssertEqual(EuroInput.live("23."), "23,")
        XCTAssertEqual(EuroInput.live("23.5"), "23,5")
        XCTAssertEqual(EuroInput.live("23,50"), "23,50")
        XCTAssertEqual(EuroInput.live("23,505", previous: "23,50"), "23,50", "a third decimal does not go in")
        XCTAssertEqual(EuroInput.live("007"), "7")
        XCTAssertEqual(EuroInput.live("0"), "0")
        XCTAssertEqual(EuroInput.live(","), "0,")
        XCTAssertEqual(EuroInput.live(".5"), "0,5")
        XCTAssertEqual(EuroInput.live("€ 12"), "12")
        XCTAssertEqual(EuroInput.live(""), "")
        XCTAssertEqual(EuroInput.live("12,,"), "12,")
        XCTAssertEqual(EuroInput.live("9999"), "9999")
        XCTAssertEqual(EuroInput.live("99999", previous: "9999"), "9999", "a fifth integer digit does not go in")
        XCTAssertEqual(EuroInput.live("1.024,50"), "1024,50", "a pasted grouped price")
    }

    func testEditableText() {
        XCTAssertEqual(EuroInput.editableText(23.5), "23,50")
        XCTAssertEqual(EuroInput.editableText(5), "5,00")
        XCTAssertEqual(EuroInput.editableText(0), "")
        XCTAssertEqual(EuroInput.parse(EuroInput.editableText(1234.56)), 1234.56)
    }

    func testPlausibility() {
        // Wien Hbf → Mödling: about € 4,90.
        XCTAssertEqual(FarePlausibility.check(entered: 150, estimate: 4.9), .high(reference: 4.9))
        XCTAssertNil(FarePlausibility.check(entered: 5.2, estimate: 4.9))
        XCTAssertNil(FarePlausibility.check(entered: 12, estimate: 4.9), "a Verbund ticket with a zone more is plausible")
        // Innsbruck → Wien: € 81,10.
        XCTAssertEqual(FarePlausibility.check(entered: 1, estimate: 81.1), .low(reference: 81.1))
        XCTAssertEqual(FarePlausibility.check(entered: 162.2, estimate: 81.1), .looksLikeReturn(oneWay: 81.1))
        XCTAssertEqual(FarePlausibility.check(entered: 160, estimate: 81.1), .looksLikeReturn(oneWay: 80))
        XCTAssertNil(FarePlausibility.check(entered: 120, estimate: 81.1), "1st class or a train surcharge")
        // A city ticket: small absolute differences never warn.
        XCTAssertNil(FarePlausibility.check(entered: 1, estimate: 2.4))
        XCTAssertNil(FarePlausibility.check(entered: 4.8, estimate: 2.4), "below € 3 a double is no return-ticket hint")
        // Without an estimate (custom place) only absurd values.
        XCTAssertNil(FarePlausibility.check(entered: 80, estimate: nil))
        XCTAssertEqual(FarePlausibility.check(entered: 500, estimate: nil), .high(reference: nil))
        XCTAssertNil(FarePlausibility.check(entered: 0, estimate: 10))
    }
}
