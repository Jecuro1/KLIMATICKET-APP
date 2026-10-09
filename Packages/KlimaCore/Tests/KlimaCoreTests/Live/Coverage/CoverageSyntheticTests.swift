import XCTest
@testable import KlimaCore

/// SPEC §D2 WP-C 2: the 14 official synthetic cases (`FX/coverage/synthetic_cases.json`) → `expected`, with the
/// reference engine's winning rule.
final class CoverageSyntheticTests: XCTestCase {
    struct Case: Decodable {
        let label: String
        let family: String
        let expected: CoverageResult
        let engineResult: CoverageResult
        let rule: String?
        let leg: CoverageLegInput
    }

    static func cases() throws -> [Case] {
        struct File: Decodable { let cases: [Case] }
        return try JSONDecoder().decode(File.self, from: Fixture.data("coverage/synthetic_cases")).cases
    }

    func testAllFourteenCasesMatch() throws {
        let ev = CoverageFixtures.evaluator
        let cases = try Self.cases()
        XCTAssertEqual(cases.count, 14)
        for c in cases {
            let scope: TicketScope = c.family == "oe" ? .oe : .regional(c.family)
            let got = ev.evaluate(c.leg, scope: scope)
            XCTAssertEqual(got.result, c.expected, c.label)
            XCTAssertEqual(got.result, c.engineResult, c.label)
            XCTAssertEqual(got.ruleID, c.rule, c.label)
        }
    }

    func testBadgesAndPartialDetails() throws {
        let ev = CoverageFixtures.evaluator
        let cases = Dictionary(uniqueKeysWithValues: try Self.cases().map { ($0.label, $0) })
        let munich = try XCTUnwrap(cases["RJ Wien–München"])
        let partial = ev.evaluate(munich.leg, scope: .oe)
        XCTAssertEqual(partial.lastCoveredStopName, "Salzburg Hbf")
        XCTAssertEqual(partial.badge, "KlimaTicket gilt bis Salzburg Hbf · danach Ticket nötig")
        XCTAssertEqual(partial.confidence, "high")

        let toll = try XCTUnwrap(cases["Paznaun bus with toll remark"])
        XCTAssertEqual(ev.evaluate(toll.leg, scope: .oe).badge, "Inklusive · zzgl. Mautgebühr")
        // The same remark on a leg that never reaches Galtür/Bielerhöhe → covered (LIVE quirk, Landeck–Ischgl).
        var ischgl = toll.leg
        ischgl.from = .init(name: "Landeck-Zams Bahnhof", lat: 47.1407, lon: 10.5672, country: "AT", state: "T")
        ischgl.to = .init(name: "Ischgl Seilbahnen", lat: 47.0127, lon: 10.2915, country: "AT", state: "T")
        XCTAssertEqual(ev.evaluate(ischgl, scope: .oe), LegCoverage(result: .covered, ruleID: "toll-surcharge", badge: "Inklusive",
                                                                     confidence: "high"))

        // A leg that starts abroad has no covered stop → notCovered (Auslandsabschnitt).
        var abroad = munich.leg
        abroad.from = abroad.to
        abroad.passList = []
        let r = ev.evaluate(abroad, scope: .oe)
        XCTAssertEqual(r.result, .notCovered)
        XCTAssertEqual(r.badge, "Nicht im KlimaTicket (Auslandsabschnitt)")
    }

    /// Unknown states are not evidence of leaving a regional area; out-of-scope legs with known states are notCovered.
    func testRegionalScopeOutcomes() throws {
        let ev = CoverageFixtures.evaluator
        let ibk = CoverageLegInput.Stop(name: "Innsbruck Hbf", lat: 47.2633, lon: 11.40085, country: "AT", state: "T")
        let wien = CoverageLegInput.Stop(name: "Wien Hbf", lat: 48.18519, lon: 16.37641, country: "AT", state: "W")
        let nowhere = CoverageLegInput.Stop(name: "Irgendwo", lat: 10, lon: 10)
        let rjx = CoverageLegInput(legType: "JNY", operator: "Nahreisezug", productName: "RJX 662", category: "RJX", cls: 1,
                                   from: ibk, to: wien)
        XCTAssertEqual(ev.evaluate(rjx, scope: .regional("tirol")),
                       LegCoverage(result: .notCovered, ruleID: "scope:tirol", badge: "Außerhalb des Geltungsbereichs", confidence: "medium"))
        var unknownEnd = rjx
        unknownEnd.to = nowhere
        XCTAssertEqual(ev.evaluate(unknownEnd, scope: .regional("tirol")).result, .unknown)
        var inside = rjx
        inside.to = .init(name: "Landeck-Zams Bahnhof", lat: 47.1407, lon: 10.5672, country: "AT", state: "T")
        XCTAssertEqual(ev.evaluate(inside, scope: .regional("tirol")).result, .covered)
        // Unsupported tickets never claim coverage; walks are not applicable everywhere.
        XCTAssertEqual(ev.evaluate(inside, scope: .unsupported).result, .unknown)
        let walk = CoverageLegInput(legType: "WALK", from: ibk, to: ibk)
        for scope in [TicketScope.oe, .regional("tirol"), .unsupported] {
            XCTAssertEqual(ev.evaluate(walk, scope: scope).result, .notApplicable, "\(scope)")
        }
        XCTAssertEqual(ev.evaluate(inside, scope: .regional("atlantis")).result, .unknown, "family missing in the rule file")
    }

    /// States are resolved from the station index when the input has none (reference `enrich_stop`).
    func testMissingStateComesFromStationIndex() {
        let ev = CoverageFixtures.evaluator
        // Kufstein and Wörgl stations, no state and no country given → T / AT via stations.json.
        let leg = CoverageLegInput(legType: "JNY", operator: "Nahreisezug", productName: "REX 1", category: "REX", cls: 16,
                                   from: .init(name: "Kufstein Bahnhof", lat: 47.58299, lon: 12.16596),
                                   to: .init(name: "Wörgl Hbf", lat: 47.4894, lon: 12.0613))
        XCTAssertEqual(ev.evaluate(leg, scope: .regional("tirol")).result, .covered)
        XCTAssertEqual(ev.evaluate(leg, scope: .oe).ruleID, "regional-rail")
    }

    func testAggregation() {
        typealias E = CoverageEvaluator
        XCTAssertEqual(E.aggregate([]), .notApplicable)
        XCTAssertEqual(E.aggregate([.notApplicable]), .notApplicable)
        XCTAssertEqual(E.aggregate([.covered, .notApplicable, .surcharge]), .covered)
        XCTAssertEqual(E.aggregate([.notCovered, .notApplicable, .notCovered]), .notCovered)
        XCTAssertEqual(E.aggregate([.covered, .unknown]), .unknown)
        XCTAssertEqual(E.aggregate([.unknown, .notCovered]), .partial)
        XCTAssertEqual(E.aggregate([.covered, .notCovered]), .partial)
        XCTAssertEqual(E.aggregate([.discount]), .partial)
        XCTAssertEqual(E.aggregate([.partial]), .partial)
    }
}
