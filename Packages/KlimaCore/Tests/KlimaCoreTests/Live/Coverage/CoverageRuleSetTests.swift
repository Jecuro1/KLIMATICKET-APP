import XCTest
@testable import KlimaCore

/// SPEC §D2 WP-C 1: the rule file decodes completely; documentation keys are ignored; bad input throws or degrades.
final class CoverageRuleSetTests: XCTestCase {
    func testDecodesShippedRuleFile() throws {
        let set = try CoverageRuleSet(jsonData: CoverageFixtures.rulesData)
        XCTAssertEqual(set.schemaVersion, 1)
        XCTAssertEqual(set.rules.count, 27)
        XCTAssertEqual(set.acceptedOperatorsRail.count, 15)
        XCTAssertEqual(set.gemeinschaftsbahnhoefe.count, 9)
        XCTAssertEqual(set.transitSections.count, 6)
        XCTAssertEqual(Set(set.regionalScopes.keys),
                       ["tirol", "vbg", "sbg", "ooe", "vor-metropolregion", "vor-region", "wien", "stmk", "ktn"])
        XCTAssertNil(set.regionalScopes["_howTo"])
        XCTAssertNil(set.lineIdPrefixToVerbund["_verification"])
        XCTAssertEqual(set.lineIdPrefixToVerbund["vvt"], "VVT (Tirol)")
        // Every regex compiles, every operator is known.
        XCTAssertEqual(set.unknownOperatorKeys, [])
        XCTAssertTrue(set.acceptedOperatorsRail.allSatisfy { $0.regex != nil })
        XCTAssertTrue(set.gemeinschaftsbahnhoefe.allSatisfy { $0.nameRegex != nil })
        XCTAssertEqual(set.transitSections.first { $0.id == "de-deutsches-eck" }?.endpoints, ["Salzburg Hbf", "Kufstein"])
        let night = try XCTUnwrap(set.rules.first { $0.id == "ski-hiking-tourist-buses" })
        XCTAssertEqual(night.result, .notCovered)
        XCTAssertEqual(night.resultTirol, .unknown)
        XCTAssertEqual(set.rules.first { $0.id == "westbahn" }?.badge?.de, "Inklusive · WESTbahn")
    }

    /// The reference crashes on `regionalScopes.wien.include.plus`; the port ignores it (and `stmk.include.westbahn`).
    func testDocumentationKeysAreIgnored() throws {
        let set = try CoverageRuleSet(jsonData: CoverageFixtures.rulesData)
        let wien = try XCTUnwrap(set.regionalScopes["wien"]?.include)
        XCTAssertEqual(wien.conditions.count, 1, "only allStopsStateIn; `plus` is documentation")
        guard case .allStopsStateIn(let states) = wien.conditions[0] else { return XCTFail("\(wien.conditions)") }
        XCTAssertEqual(states, ["W"])
        let stmk = try XCTUnwrap(set.regionalScopes["stmk"]?.include)
        XCTAssertEqual(stmk.conditions.count, 1, "only anyOf; `westbahn` is documentation")
        // `verification` inside an anyOf member (ooe, ktn) is ignored too.
        guard case .anyOf(let members) = try XCTUnwrap(set.regionalScopes["ooe"]?.include?.conditions.first) else { return XCTFail() }
        XCTAssertEqual(members[0].conditions.count, 1)

        // A Wien leg is in scope for the Jahreskarte family, a Graz S-Bahn leg for KlimaTicket Steiermark.
        let ev = CoverageFixtures.evaluator
        let wienLeg = CoverageLegInput(legType: "JNY", operator: "Wiener Linien", productName: "U6", category: "U", cls: 256,
                                       lineId: "vor-21-U6", line: "U6",
                                       from: .init(name: "Wien Westbahnhof", lat: 48.19657, lon: 16.33803, country: "AT", state: "W"),
                                       to: .init(name: "Wien Floridsdorf", lat: 48.25638, lon: 16.40020, country: "AT", state: "W"))
        XCTAssertEqual(ev.evaluate(wienLeg, scope: .regional("wien")).result, .covered)
        let grazLeg = CoverageLegInput(legType: "JNY", operator: "Nahreisezug", productName: "S 5 (Zug-Nr. 4512)", category: "S",
                                       categoryLong: "S-Bahn", cls: 32, lineId: "at:obb:stv|S5:", line: "5",
                                       from: .init(name: "Graz Hbf", lat: 47.0722, lon: 15.4172, country: "AT", state: "ST"),
                                       to: .init(name: "Leibnitz Bahnhof", lat: 46.7787, lon: 15.5374, country: "AT", state: "ST"))
        XCTAssertEqual(ev.evaluate(grazLeg, scope: .regional("stmk")).result, .covered)
    }

    /// The app ships the same file (App/Resources/coverage_rules.json, loaded like stations.json).
    func testAppResourceIsTheFixture() throws {
        let app = try Data(contentsOf: PlaceFixtures.resources.appendingPathComponent("coverage_rules.json"))
        XCTAssertEqual(app, try CoverageFixtures.rulesData)
        XCTAssertNoThrow(try CoverageEvaluator(rulesJSON: app, stations: StationIndex(stations: [])))
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try CoverageRuleSet(jsonData: Data("{\"schemaVersion\":1,\"rules\":[".utf8)))
        XCTAssertThrowsError(try CoverageRuleSet(jsonData: Data("[]".utf8)))
        XCTAssertThrowsError(try CoverageRuleSet(jsonData: Data("{\"rules\":[]}".utf8)), "schemaVersion is required")
        XCTAssertThrowsError(try CoverageEvaluator(rulesJSON: Data("nope".utf8), stations: StationIndex(stations: [])))
    }

    func testNewerSchemaThrowsInsteadOfGuessing() {
        let json = Data(#"{"schemaVersion":2,"rules":[]}"#.utf8)
        XCTAssertThrowsError(try CoverageRuleSet(jsonData: json)) { error in
            XCTAssertEqual(error as? CoverageRuleSet.LoadError, .unsupportedSchema(2))
        }
    }

    /// Unknown operators make their node false (logged once via `unknownOperatorKeys`), never crash; a bad regex too.
    func testUnknownOperatorsEvaluateToFalse() throws {
        let json = #"""
        {"schemaVersion":1,"rules":[
          {"id":"future","priority":5,"appliesTo":["*"],"match":{"vehicleColour":"red","legTypeIn":["JNY"]},"result":"notCovered"},
          {"id":"nested","priority":6,"appliesTo":["*"],"match":{"anyOf":[{"teleport":true},{"categoryIn":["XYZ"]}]},"result":"discount"},
          {"id":"badregex","priority":7,"appliesTo":["*"],"match":{"operatorRegex":"(unclosed"},"result":"notCovered"},
          {"id":"wrongtype","priority":8,"appliesTo":["*"],"match":{"categoryIn":"RJX"},"result":"notCovered"},
          {"id":"oddresult","priority":9,"appliesTo":["*"],"match":{"categoryIn":["ODD"]},"result":"freeBeer"},
          {"id":"rail","priority":60,"appliesTo":["oe"],"match":{"categoryIn":["RJX"],"note":"doc","_x":1},"result":"covered"},
          {"id":"loop","priority":61,"appliesTo":["oe"],"match":{"ruleRef":"loop"},"result":"covered"},
          {"id":"fallback","priority":1000,"appliesTo":["*"],"match":{"always":true},"result":"unknown"}
        ]}
        """#
        let ev = try CoverageEvaluator(rulesJSON: Data(json.utf8), stations: StationIndex(stations: []))
        XCTAssertEqual(ev.unknownOperatorKeys, ["categoryIn", "operatorRegex (ungültiger Ausdruck)", "teleport", "vehicleColour"])
        let at = CoverageLegInput.Stop(name: "A", country: "AT", state: "T")
        let rj = CoverageLegInput(legType: "JNY", operator: "(unclosed", category: "RJX", from: at, to: at)
        XCTAssertEqual(ev.evaluate(rj, scope: .oe), LegCoverage(result: .covered, ruleID: "rail"))
        let xyz = CoverageLegInput(legType: "JNY", category: "XYZ", from: at, to: at)
        XCTAssertEqual(ev.evaluate(xyz, scope: .oe).ruleID, "nested")
        let odd = CoverageLegInput(legType: "JNY", category: "ODD", from: at, to: at)
        XCTAssertEqual(ev.evaluate(odd, scope: .oe).result, .unknown, "unknown result strings degrade to unknown")
        let other = CoverageLegInput(legType: "JNY", category: "ZZZ", from: at, to: at)
        XCTAssertEqual(ev.evaluate(other, scope: .oe).ruleID, "fallback", "a self-referencing ruleRef terminates")
    }
}
