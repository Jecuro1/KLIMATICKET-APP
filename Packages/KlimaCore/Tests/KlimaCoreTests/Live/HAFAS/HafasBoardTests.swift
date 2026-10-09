import XCTest
@testable import KlimaCore

/// StationBoard goldens (SPEC §D2 WP-A 5). Golden entries are in HAFAS order; `Board.entries` is sorted by effective
/// time, so golden entries are looked up, not compared by position.
final class HafasBoardTests: XCTestCase {
    static let scenarios = ["stationboard_dep_innsbruck_hbf", "stationboard_arr_wien_hbf", "stationboard_dep_wien_hbf_rail_90min"]

    static func squash(_ s: String?) -> String? { s?.replacingOccurrences(of: " ", with: "") }

    func testBoardsMatchGolden() throws {
        for scenario in Self.scenarios {
            let g = try Fixture.golden("hafas/\(scenario)")
            let board = try HafasCodec.board(from: Fixture.data("hafas/\(scenario).response"))
            let ctx = "[\(scenario)]"
            XCTAssertEqual(board.kind.rawValue, g["boardType"] as? String, ctx)
            XCTAssertEqual(board.entries.count, g["entryCount"] as? Int, ctx)

            for ge in try XCTUnwrap(g["entries"] as? [[String: Any]], ctx) {
                let planned = ISO.date(ge["plannedWhen"] as? String)
                let match = board.entries.first {
                    $0.event.planned == planned && Self.squash($0.line?.name) == Self.squash(ge["line"] as? String)
                        && $0.direction == ge["direction"] as? String
                }
                let e = try XCTUnwrap(match, "\(ctx) missing \(ge)")
                XCTAssertEqual(e.event.effective, ISO.date(ge["when"] as? String), "\(ctx) when")
                XCTAssertEqual(e.event.delaySeconds, ge["delaySec"] as? Int, "\(ctx) delay")
                XCTAssertEqual(e.event.platform?.text, ge["platform"] as? String, "\(ctx) platform")
                XCTAssertEqual(e.event.plannedPlatform?.text, ge["plannedPlatform"] as? String, "\(ctx) planned platform")
                XCTAssertEqual(e.event.platformChangeFlag, ge["platformChanged"] as? Bool, "\(ctx) platformChanged")
                XCTAssertEqual(e.event.isCancelled, ge["cancelled"] as? Bool, "\(ctx) cancelled")
                XCTAssertEqual(e.isRedirected, ge["redirected"] as? Bool, "\(ctx) redirected")
            }

            // platformChanges: the HAFAS-flagged entries (first five, HAFAS order).
            let flagged = try HafasCodec.board(from: Fixture.data("hafas/\(scenario).response"))
            let gChanges = try XCTUnwrap(g["platformChanges"] as? [[String: Any]], ctx)
            let ours = flagged.entries.filter(\.event.platformChangeFlag)
            XCTAssertGreaterThanOrEqual(ours.count, gChanges.count, ctx)
            for gc in gChanges {
                let planned = ISO.date(gc["plannedWhen"] as? String)
                let e = try XCTUnwrap(ours.first { $0.event.planned == planned && Self.squash($0.line?.name) == Self.squash(gc["line"] as? String) },
                                      "\(ctx) platform change \(gc)")
                XCTAssertEqual(e.direction, gc["direction"] as? String)
                XCTAssertEqual(e.event.plannedPlatform?.text, gc["plannedPlatform"] as? String)
                XCTAssertEqual(e.event.platform?.text, gc["platform"] as? String)
                XCTAssertTrue(e.event.platformChanged)
            }

            let maxDelay = board.entries.compactMap(\.event.delaySeconds).max() ?? 0
            XCTAssertEqual(maxDelay, g["maxDelaySec"] as? Int, "\(ctx) maxDelaySec")
            assertSorted(board, ctx)
        }
    }

    private func assertSorted(_ board: Board, _ ctx: String) {
        let times = board.entries.compactMap(\.event.effective)
        XCTAssertEqual(times, times.sorted(), "\(ctx) sorted by effective time")
    }

    func testInnsbruckFirstDepartureGolden() throws {
        let board = try HafasCodec.board(from: Fixture.data("hafas/stationboard_dep_innsbruck_hbf.response"))
        let busF = try XCTUnwrap(board.entries.first { $0.line?.name == "Bus F" && $0.direction == "Rum Bahnhst" })
        XCTAssertEqual(busF.event.planned, ISO.date("2026-10-09T11:22:00+02:00"))
        XCTAssertEqual(busF.event.realtime, ISO.date("2026-10-09T11:24:00+02:00"))
        XCTAssertEqual(busF.event.delaySeconds, 120)
        XCTAssertEqual(busF.event.platform, Platform(text: "F", kind: .stand))
        XCTAssertEqual(busF.line?.mode, .bus)
        XCTAssertNotNil(busF.terminusOrOrigin)
        XCTAssertEqual(busF.stop.extId.map { !$0.isEmpty }, true)
        XCTAssertFalse(busF.tripID.isEmpty)
        // The S 4 platform change 4 → 3.
        let s4 = try XCTUnwrap(board.entries.first { $0.line?.name == "S 4" && $0.event.platformChangeFlag })
        XCTAssertEqual(s4.event.plannedPlatform?.text, "4")
        XCTAssertEqual(s4.event.platform?.text, "3")
    }

    func testArrivalBoardOriginAndLargeDelay() throws {
        let board = try HafasCodec.board(from: Fixture.data("hafas/stationboard_arr_wien_hbf.response"))
        XCTAssertEqual(board.kind, .arrivals)
        XCTAssertEqual(board.entries.compactMap(\.event.delaySeconds).max(), 21_240, "+354 min exists")
        // Arrivals carry the run's origin (prodL[0].fLocX) and dirTxt is still the final destination.
        XCTAssertTrue(board.entries.allSatisfy { $0.terminusOrOrigin != nil })
        let late = try XCTUnwrap(board.entries.first { $0.event.delaySeconds == 21_240 })
        XCTAssertEqual(late.direction, "Lockenhaus Hauptplatz")
        XCTAssertNotEqual(board.entries.first?.id, late.id, "sorted by effective time, the +354 min arrival is not first")
    }
}

final class HafasJourneyDetailsTests: XCTestCase {
    func testTripGolden() throws {
        let trip = try HafasCodec.trip(from: Fixture.data("hafas/journeydetails_rjx133_koralm_polyline.response"))
        let g = try XCTUnwrap(try Fixture.golden("hafas/journeydetails_rjx133_koralm_polyline")["trip"] as? [String: Any])
        XCTAssertEqual(trip.line?.name, g["line"] as? String)
        XCTAssertEqual(trip.line?.name, "RJX 133")
        XCTAssertEqual(trip.direction, g["direction"] as? String)
        XCTAssertEqual(trip.stopovers.count, g["stopoverCount"] as? Int)
        XCTAssertEqual(trip.stopovers.count, 12)
        XCTAssertEqual(trip.stopovers.first?.location.name, g["firstStop"] as? String)
        XCTAssertEqual(trip.stopovers.last?.location.name, g["lastStop"] as? String)
        XCTAssertEqual(trip.polyline?.count, g["polylinePointCount"] as? Int)
        XCTAssertFalse(trip.tripID.isEmpty)
        XCTAssertNotNil(trip.currentPosition)
        XCTAssertNotNil(trip.realtimeUpdatedAt)
    }

    func testBorderAndIndices() throws {
        let trip = try HafasCodec.trip(from: Fixture.data("hafas/journeydetails_rjx133_koralm_polyline.response"))
        let tarvisio = try XCTUnwrap(trip.stopovers.first { $0.location.name.hasPrefix("Tarvisio") })
        XCTAssertTrue(tarvisio.isBorder)
        XCTAssertEqual(trip.stopovers.filter(\.isBorder).count, 1)
        let idx = trip.stopovers.compactMap(\.index)
        XCTAssertEqual(idx.count, trip.stopovers.count)
        XCTAssertEqual(idx, idx.sorted())
        XCTAssertEqual(Set(idx).count, idx.count)
        // First stop: departure only; last stop: arrival only.
        XCTAssertNil(trip.stopovers.first?.arrival)
        XCTAssertNotNil(trip.stopovers.first?.departure)
        XCTAssertNil(trip.stopovers.last?.departure)
        // Bruck/Mur: platform change 4 → 5 flagged; CALCULATED prognosis in Italy maps to .other.
        let bruck = try XCTUnwrap(trip.stopovers.first { $0.location.name.hasPrefix("Bruck/Mur") })
        XCTAssertTrue(bruck.arrival?.platformChanged == true)
        XCTAssertEqual(bruck.arrival?.plannedPlatform?.text, "4")
        XCTAssertEqual(bruck.arrival?.platform?.text, "5")
        XCTAssertEqual(trip.stopovers.last?.arrival?.prognosis, .other)
        XCTAssertNil(trip.stopovers.last?.arrival?.realtime)
    }

    /// Cutting the run to a leg by `Stopover.index` (SPEC §A3.3 JourneyDetails).
    func testCutToLegByIndex() throws {
        let trip = try HafasCodec.trip(from: Fixture.data("hafas/journeydetails_rjx133_koralm_polyline.response"))
        let leg = trip.stopovers.filter { ($0.index ?? -1) >= 4 && ($0.index ?? 99) <= 6 }
        XCTAssertEqual(leg.map(\.location.name), ["Graz Hbf", "Klagenfurt Hbf", "Villach Hbf"])
    }
}
