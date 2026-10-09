import XCTest
@testable import KlimaCore

/// Review 2026-10-09: an arrival board names where each run comes from, not its final destination (`dirTxt` is the
/// final destination on arrival boards too, SPEC §A3.4).
final class BoardArrivalRowsTests: XCTestCase {
    func testArrivalRowsShowTheOriginOfTheRun() throws {
        let board = try HafasCodec.board(from: Fixture.data("hafas/stationboard_arr_wien_hbf.response"))
        XCTAssertEqual(board.kind, .arrivals)
        let rows = BoardPresentation.rows(board)
        XCTAssertEqual(rows.count, board.entries.count)
        for (row, entry) in zip(rows, board.entries) {
            let origin = try XCTUnwrap(entry.terminusOrOrigin?.name, entry.id)
            XCTAssertEqual(row.destination, DisplayNames.make(origin), entry.id)
        }
        // B23 runs to Lockenhaus but arrives from Edlitz: the row must say Edlitz.
        let b23 = try XCTUnwrap(rows.first { $0.lineTitle == "Bus B23" })
        XCTAssertTrue(b23.destination.name.hasPrefix("Edlitz"), b23.destination.name)
        // A single entry defaults to the departure reading (direction first).
        let entry = try XCTUnwrap(board.entries.first)
        XCTAssertEqual(BoardPresentation.row(entry).destination, DisplayNames.make(try XCTUnwrap(entry.direction)))
        XCTAssertEqual(BoardPresentation.row(entry, kind: .arrivals).destination, DisplayNames.make(try XCTUnwrap(entry.terminusOrOrigin?.name)))
    }
}
