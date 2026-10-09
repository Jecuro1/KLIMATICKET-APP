import XCTest
@testable import KlimaCore

/// SPEC §D2 WP-C 3: every `golden["coverage/journeys"]` entry (families oe and tirol): HAFAS fixture → `HafasCodec` →
/// `CoverageInputMapper` → evaluator; overall and per-ride-leg result and rule equal the reference engine.
final class CoverageJourneyGoldenTests: XCTestCase {
    func testAllCoverageGoldensMatch() throws {
        let golden = try Fixture.golden("coverage/journeys")
        XCTAssertEqual(golden.count, 8)
        let ev = CoverageFixtures.evaluator
        var checked = 0
        for scenario in golden.keys.sorted() {
            let page = try CoverageFixtures.page(scenario)
            let entries = try XCTUnwrap(golden[scenario] as? [[String: Any]], scenario)
            for e in entries {
                let family = try XCTUnwrap(e["family"] as? String)
                let index = try XCTUnwrap(e["connection"] as? Int)
                let ctx = "\(scenario) [\(family)] #\(index)"
                let journey = page.journeys[index]
                let cov = ev.evaluate(journey, scope: family == "oe" ? .oe : .regional(family))
                XCTAssertEqual(cov.overall.rawValue, e["overall"] as? String, ctx)
                XCTAssertEqual(cov.legs.count, journey.legs.count, ctx)
                let rides = zip(journey.legs, cov.legs).filter { $0.0.kind == .ride }
                let goldenLegs = try XCTUnwrap(e["legs"] as? [[String: Any]], ctx)
                XCTAssertEqual(rides.count, goldenLegs.count, ctx)
                for ((leg, got), g) in zip(rides, goldenLegs) {
                    XCTAssertEqual(leg.line?.fullName, g["product"] as? String, ctx)
                    XCTAssertEqual(got.result.rawValue, g["result"] as? String, "\(ctx) \(g["product"] ?? "")")
                    XCTAssertEqual(got.ruleID, g["rule"] as? String, "\(ctx) \(g["product"] ?? "")")
                }
                for (leg, got) in zip(journey.legs, cov.legs) where leg.kind != .ride {
                    XCTAssertEqual(got.result, .notApplicable, ctx)
                }
                checked += 1
            }
        }
        XCTAssertEqual(checked, 74)
    }

    /// The covered prefix: fully covered journeys have no "last covered stop"; Innsbruck → Lech with KlimaTicket Tirol
    /// stops before the first leg (RJX to Vorarlberg is out of scope).
    func testCoveredPrefix() throws {
        let ev = CoverageFixtures.evaluator
        let lech = try CoverageFixtures.page("tripsearch_innsbruck_lech_bus").journeys[0]
        let oe = ev.evaluate(lech, scope: .oe)
        XCTAssertEqual(oe.overall, .covered)
        XCTAssertEqual(oe.lastCoveredLegIndex, 2)
        XCTAssertNil(oe.lastCoveredStopName)
        let tirol = ev.evaluate(lech, scope: .regional("tirol"))
        XCTAssertEqual(tirol.overall, .partial)
        XCTAssertNil(tirol.lastCoveredLegIndex)
        XCTAssertNil(tirol.lastCoveredStopName)
    }
}
