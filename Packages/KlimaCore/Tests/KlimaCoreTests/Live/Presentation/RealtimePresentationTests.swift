import XCTest
@testable import KlimaCore

/// SPEC §C3.1 / §D2 WP-C 5: realtime labels.
final class RealtimePresentationTests: XCTestCase {
    let planned = Vienna.date("2026-10-09 11:16")

    private func label(delay minutes: Double?, cancelled: Bool = false) -> RealtimeLabel {
        RealtimePresentation.label(StopEvent(planned: planned, realtime: minutes.map { planned.addingTimeInterval($0 * 60) },
                                             isCancelled: cancelled))
    }

    func testStatesAndTexts() {
        XCTAssertEqual(label(delay: nil), RealtimeLabel(state: .scheduled))
        XCTAssertEqual(label(delay: 0), RealtimeLabel(state: .onTime, delayMinutes: 0, text: "pünktlich"))
        XCTAssertEqual(label(delay: -2), RealtimeLabel(state: .onTime, delayMinutes: -2, text: "11:14 (-2)"))
        XCTAssertEqual(label(delay: 1), RealtimeLabel(state: .late, delayMinutes: 1, text: "11:17 +1"))
        XCTAssertEqual(label(delay: 4), RealtimeLabel(state: .late, delayMinutes: 4, text: "11:20 +4"))
        XCTAssertEqual(label(delay: 5), RealtimeLabel(state: .veryLate, delayMinutes: 5, text: "11:21 +5"))
        XCTAssertEqual(label(delay: 354), RealtimeLabel(state: .veryLate, delayMinutes: 354, text: "17:10 +354"))
        XCTAssertEqual(label(delay: 3, cancelled: true), RealtimeLabel(state: .cancelled, text: "Fällt aus"))
        XCTAssertEqual(label(delay: nil, cancelled: true).state, .cancelled)
        // Seconds round like the reference (half to even): 30 s → 0, 90 s → 2.
        XCTAssertEqual(label(delay: 0.5).delayMinutes, 0)
        XCTAssertEqual(label(delay: 1.5).delayMinutes, 2)
        XCTAssertEqual(label(delay: 0.4).text, "pünktlich")
    }

    func testViennaTimeAcrossDST() {
        XCTAssertEqual(RealtimePresentation.time(Vienna.date("2026-10-24 22:44")), "22:44")
        XCTAssertEqual(RealtimePresentation.time(ISO.date("2026-10-25T05:05:00+01:00")!), "05:05")
        XCTAssertEqual(RealtimePresentation.time(ISO.date("2026-07-01T00:05:00Z")!), "02:05")
    }

    func testSpokenLabels() {
        let late = label(delay: 4)
        XCTAssertEqual(RealtimePresentation.spoken(late, realtime: planned.addingTimeInterval(240)), "4 Minuten später, 11:20")
        XCTAssertEqual(RealtimePresentation.spoken(label(delay: -1), realtime: nil), "1 Minute früher")
        XCTAssertEqual(RealtimePresentation.spoken(label(delay: 0), realtime: planned), "pünktlich")
        XCTAssertEqual(RealtimePresentation.spoken(label(delay: 2, cancelled: true), realtime: nil), "fällt aus")
        XCTAssertNil(RealtimePresentation.spoken(label(delay: nil), realtime: nil))
    }

    /// Goldens: Landeck → Ischgl +3 / +4 (`vm_trips_landeck_ischgl_delays.json`), Innsbruck → Lech dep onTime,
    /// arr scheduled (`vm_trips_innsbruck_lech.json`).
    func testGoldenStates() throws {
        for (vm, scenario) in VM.trips {
            let golden = try VM.connections(vm)
            let page = try CoverageFixtures.page(scenario)
            XCTAssertEqual(page.journeys.count, golden.count, vm)
            for (j, g) in zip(page.journeys, golden) {
                let dep = try XCTUnwrap(g["dep"] as? [String: Any]), arr = try XCTUnwrap(g["arr"] as? [String: Any])
                VM.assert(RealtimePresentation.label(try XCTUnwrap(j.departure)), dep, "\(vm) dep")
                VM.assert(RealtimePresentation.label(try XCTUnwrap(j.arrival)), arr, "\(vm) arr")
                for (leg, gl) in zip(j.legs, try XCTUnwrap(g["legs"] as? [[String: Any]])) where leg.kind == .ride {
                    VM.assert(RealtimePresentation.label(leg.departure), try XCTUnwrap(gl["dep"] as? [String: Any]), "\(vm) leg dep")
                    VM.assert(RealtimePresentation.label(leg.arrival), try XCTUnwrap(gl["arr"] as? [String: Any]), "\(vm) leg arr")
                }
            }
        }
        let landeck = try VM.connections("vm_trips_landeck_ischgl_delays")[0]
        XCTAssertEqual((landeck["dep"] as? [String: Any])?["text"] as? String, "11:13 +3")
        let first = try CoverageFixtures.page("tripsearch_tyrol_bus_landeck_ischgl").journeys[0]
        XCTAssertEqual(RealtimePresentation.label(first.departure!), RealtimeLabel(state: .late, delayMinutes: 3, text: "11:13 +3"))
        XCTAssertEqual(RealtimePresentation.label(first.arrival!), RealtimeLabel(state: .late, delayMinutes: 4, text: "12:05 +4"))
        let lech = try CoverageFixtures.page("tripsearch_innsbruck_lech_bus").journeys[0]
        XCTAssertEqual(RealtimePresentation.label(lech.departure!).state, .onTime)
        XCTAssertEqual(RealtimePresentation.label(lech.arrival!).state, .scheduled)
    }
}

/// Access to the FX/ux view-model goldens of the reference `ux/client.py`.
enum VM {
    /// vm file ↔ HAFAS fixture it was generated from.
    static let trips = [
        ("vm_trips_innsbruck_lech", "tripsearch_innsbruck_lech_bus"),
        ("vm_trips_st_anton_innsbruck", "tripsearch_st_anton_innsbruck"),
        ("vm_trips_landeck_ischgl_delays", "tripsearch_tyrol_bus_landeck_ischgl"),
    ]

    static func connections(_ vm: String) throws -> [[String: Any]] {
        let obj = try XCTUnwrap(try Fixture.json("ux/\(vm)") as? [String: Any])
        return try XCTUnwrap(obj["connections"] as? [[String: Any]])
    }

    static func value<T>(_ any: Any?) -> T? { any is NSNull ? nil : any as? T }

    static func assert(_ label: RealtimeLabel, _ g: [String: Any], _ ctx: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(label.state.rawValue, g["state"] as? String, ctx, file: file, line: line)
        XCTAssertEqual(label.delayMinutes, value(g["delayMin"]), ctx, file: file, line: line)
        XCTAssertEqual(label.text, value(g["text"]), ctx, file: file, line: line)
    }

    static func assert(_ p: PlatformLabel?, _ g: [String: Any]?, _ ctx: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let g, let display: String = value(g["display"]) else {
            XCTAssertNil(p, ctx, file: file, line: line)
            return
        }
        guard let p else { return XCTFail("\(ctx): platform missing", file: file, line: line) }
        XCTAssertEqual(p.label, g["label"] as? String, ctx, file: file, line: line)
        XCTAssertEqual(p.display, display, ctx, file: file, line: line)
        XCTAssertEqual(p.planned, value(g["planned"]), ctx, file: file, line: line)
        XCTAssertEqual(p.realtime, value(g["realtime"]), ctx, file: file, line: line)
        XCTAssertEqual(p.changed, g["changed"] as? Bool, ctx, file: file, line: line)
    }

    /// The reference plates („T 5“, „S 4“, „CJX 1“) in the BADGE_SPEC form that supersedes them (ENRICH D7):
    /// no spaces, trams without „T“.
    static func badgePlate(_ golden: String, mode: String?) -> String {
        var p = golden
        if mode == "tram", p.hasPrefix("T ") { p.removeFirst(2) }
        return p.replacingOccurrences(of: " ", with: "")
    }
}
