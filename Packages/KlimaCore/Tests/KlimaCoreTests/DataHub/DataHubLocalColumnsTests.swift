import XCTest
@testable import KlimaCore

// MARK: review-daten – the block `local` of a backup (docs/DATA_HUB.md §3.1): the columns a trip or a saved route has only on this
// iPhone. Sparse, tolerant, ignored by older readers, and with a clear rule for rows without an entry.

private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    var c = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    c.timeZone = Calendar.vienna.timeZone
    return Calendar.vienna.date(from: c)!
}

final class DataHubLocalColumnsTests: XCTestCase {
    private func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private let tripA = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
    private let tripB = UUID(uuidString: "0B8E4C2A-1D3F-4A5B-9C6D-7E8F9A0B1C2D")!
    private let route = UUID(uuidString: "A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D")!

    private var sample: BackupLocalBlock {
        .make(trips: [(tripA, TripLocalColumns(priceSource: "liveOebb", priceProvider: "ÖBB", priceProduct: "Sparschiene",
                                               priceFetchedAt: at(2026, 11, 19, 7, 12), journeyRef: "¶HKI¶T$A=1@O=Wien Hbf",
                                               lineSummary: "Railjet Xpress 162")),
                      (tripB, .empty)],
              favorites: [(route, FavoriteLocalColumns(schedule: "1,2,3,4,5@07:15"))])
    }

    func testOnlyRowsWithSomethingAreWritten() throws {
        let block = sample
        XCTAssertEqual(Set(block.trips.keys), [tripA.uuidString.lowercased()])
        XCTAssertEqual(block.favorites.count, 1)
        let json = String(decoding: try encoder().encode(block), as: UTF8.self)
        XCTAssertTrue(json.contains("\"line_summary\" : \"Railjet Xpress 162\""))
        XCTAssertTrue(json.contains("\"price_fetched_at\" : \"2026-11-19T06:12:00Z\""))   // Vienna 07:12 in winter = 06:12 UTC
        XCTAssertFalse(json.contains(tripB.uuidString.lowercased()))
        // A trip with only a line writes only that key.
        let lineOnly = String(decoding: try encoder().encode(TripLocalColumns(lineSummary: "S 1")), as: UTF8.self)
        XCTAssertEqual(lineOnly.filter { $0 == ":" }.count, 1)
    }

    func testRoundTrip() throws {
        let data = try encoder().encode(sample)
        let back = try BackupEnvelope.decoder().decode(BackupLocalBlock.self, from: data)
        XCTAssertEqual(back, sample)
        XCTAssertEqual(back.trip(tripA).lineSummary, "Railjet Xpress 162")
        XCTAssertEqual(back.trip(tripA).priceFetchedAt, at(2026, 11, 19, 7, 12))
        XCTAssertEqual(back.favorite(route).schedule, "1,2,3,4,5@07:15")
    }

    /// A row the file has but the block does not name gets no local columns – the file knows these columns, and that row had none.
    func testARowWithoutEntryGetsNone() {
        XCTAssertEqual(sample.trip(tripB), .empty)
        XCTAssertTrue(sample.trip(UUID()).isEmpty)
        XCTAssertEqual(sample.favorite(UUID()), .empty)
        // Upper- or lower-case ids in the file: the key is lower case, like `journey_id`.
        XCTAssertEqual(sample.trip(UUID(uuidString: tripA.uuidString.lowercased())!).lineSummary, "Railjet Xpress 162")
    }

    /// One odd value never blocks the rest: a number where text belongs, a date that is no date.
    func testTolerantDecoding() throws {
        let json = """
        {"trips":{"\(tripA.uuidString.lowercased())":{"line_summary":42,"price_source":"table","price_fetched_at":"gestern"}},
         "favorites":{"\(route.uuidString.lowercased())":{"schedule":["x"]}},"future":{"key":1}}
        """
        let block = try BackupEnvelope.decoder().decode(BackupLocalBlock.self, from: Data(json.utf8))
        XCTAssertEqual(block.trip(tripA).priceSource, "table")
        XCTAssertEqual(block.trip(tripA).lineSummary, "")
        XCTAssertNil(block.trip(tripA).priceFetchedAt)
        XCTAssertEqual(block.favorite(route), .empty)
        // A whole table that is not a dictionary is dropped, the other one stays.
        let half = #"{"trips":[1,2],"favorites":{"\#(route.uuidString.lowercased())":{"schedule":"6,7@09:00"}}}"#
        let partly = try BackupEnvelope.decoder().decode(BackupLocalBlock.self, from: Data(half.utf8))
        XCTAssertTrue(partly.trips.isEmpty)
        XCTAssertEqual(partly.favorite(route).schedule, "6,7@09:00")
    }

    /// The block is a new top-level key: an older reader (version 1.2, or 1.3 before the block) ignores it, the frame and the
    /// checksum stay as they were.
    func testOlderReadersIgnoreTheBlock() throws {
        struct OldReader: Decodable {
            struct Row: Decodable { var id: UUID }
            var version: Int
            var tickets: [Row]
            var trips: [Row]
            var favorites: [Row]
        }
        struct File: Encodable {
            struct Row: Encodable { var id: UUID }
            var format = BackupFormat.name
            var version = BackupFormat.currentVersion
            var tickets: [Row] = []
            var trips: [Row]
            var favorites: [Row]
            var local: BackupLocalBlock
            var checksum = BackupChecksum.placeholder
        }
        let file = File(trips: [.init(id: tripA), .init(id: tripB)], favorites: [.init(id: route)], local: sample)
        let sealed = try XCTUnwrap(BackupChecksum.seal(try encoder().encode(file)))
        let old = try JSONDecoder().decode(OldReader.self, from: sealed)
        XCTAssertEqual(old.trips.map(\.id), [tripA, tripB])
        let inspection = BackupInspection.inspect(sealed)
        XCTAssertTrue(inspection.canRestore)
        if case .intact = inspection.verdict {} else { XCTFail("sealed file must be intact") }
        // Changing a line name after sealing is caught like any other byte.
        var tampered = sealed
        let range = try XCTUnwrap(tampered.range(of: Data("Railjet Xpress 162".utf8)))
        tampered.replaceSubrange(range, with: Data("Railjet Xpress 163".utf8))
        XCTAssertEqual(BackupInspection.inspect(tampered).problem, .damaged)
    }
}
