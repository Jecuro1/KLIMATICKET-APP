import XCTest
@testable import KlimaCloud

/// DTO coding against the shared wire fixture `backend/test/fixtures/contract-rows.json` (contract §3.5 / §6.6).
final class FixtureTests: XCTestCase {
    private static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // KlimaCloudTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // KlimaCloud
        .deletingLastPathComponent()   // Packages
        .deletingLastPathComponent()   // repository root
        .appendingPathComponent("backend/test/fixtures/contract-rows.json")

    private func table(_ name: String) throws -> (push: [String: Any], pull: [String: Any]) {
        let data = try Data(contentsOf: Self.fixtureURL)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tables = try XCTUnwrap(root["tables"] as? [String: Any])
        let entry = try XCTUnwrap(tables[name] as? [String: Any], "fixture has no table \(name)")
        return (try XCTUnwrap(entry["push"] as? [String: Any]), try XCTUnwrap(entry["pull"] as? [String: Any]))
    }

    private func check<Row: SyncRow>(_ type: Row.Type, file: StaticString = #filePath, line: UInt = #line) throws {
        let (push, pull) = try table(Row.table)

        // 1) Every pull object decodes (server_rev as an integer).
        var pullObject = pull
        pullObject["server_rev"] = 4711
        let decodedPull = try CloudCoding.decoder.decode(Row.self, from: try JSONSerialization.data(withJSONObject: pullObject))
        XCTAssertEqual(decodedPull.server_rev, 4711, file: file, line: line)
        XCTAssertEqual(decodedPull.id.uuidString.lowercased(), pull["id"] as? String, file: file, line: line)

        // 2) Encoding a DTO yields exactly the push key set (user_id included, server_rev absent, nil optionals absent).
        let decodedPush = try CloudCoding.decoder.decode(Row.self, from: try JSONSerialization.data(withJSONObject: push))
        let encodedPush = try XCTUnwrap(try JSONSerialization.jsonObject(with: try CloudCoding.encoder.encode(decodedPush)) as? [String: Any])
        let pushKeys = Set(push.filter { !($0.value is NSNull) }.keys)
        XCTAssertEqual(Set(encodedPush.keys), pushKeys, file: file, line: line)
        XCTAssertNil(encodedPush["server_rev"], file: file, line: line)

        // 3) The pulled row re-encodes to the canonical pull values (ids compared case-insensitively).
        var stripped = decodedPull
        stripped.server_rev = nil
        let reencoded = try XCTUnwrap(try JSONSerialization.jsonObject(with: try CloudCoding.encoder.encode(stripped)) as? [String: Any])
        for (key, expected) in pull where key != "server_rev" {
            let actual = reencoded[key]
            if expected is NSNull {
                XCTAssertNil(actual, "\(Row.table).\(key) should be absent", file: file, line: line)
            } else if key == "id" {
                XCTAssertEqual((actual as? String)?.lowercased(), expected as? String, file: file, line: line)
            } else if let expected = expected as? String {
                XCTAssertEqual(actual as? String, expected, "\(Row.table).\(key)", file: file, line: line)
            } else if let expected = expected as? NSNumber {
                let number = try XCTUnwrap(actual as? NSNumber, "\(Row.table).\(key)", file: file, line: line)
                XCTAssertEqual(number.doubleValue, expected.doubleValue, "\(Row.table).\(key)", file: file, line: line)
            }
        }
        XCTAssertEqual(Set(reencoded.keys), Set(pull.filter { !($0.value is NSNull) && $0.key != "server_rev" }.keys),
                       file: file, line: line)

        // 4) Push and pull describe the same row once normalized.
        var normalizedPush = decodedPush
        normalizedPush.user_id = decodedPull.user_id
        XCTAssertEqual(normalizedPush, stripped, "\(Row.table): push ≠ pull after normalization", file: file, line: line)
    }

    func testTickets() throws { try check(TicketDTO.self) }
    func testTrips() throws { try check(TripDTO.self) }
    func testFavoriteRoutes() throws { try check(FavoriteDTO.self) }
    func testBenefits() throws { try check(BenefitDTO.self) }

    func testOffsetIsNormalizedToUTC() throws {
        let (push, _) = try table("trips")
        let trip = try CloudCoding.decoder.decode(TripDTO.self, from: try JSONSerialization.data(withJSONObject: push))
        XCTAssertEqual(APITimestamp.string(from: trip.updated_at), "2026-10-08T03:50:12.500000Z")
        XCTAssertEqual(trip.note, "Railjet – „ruhig“ ✓")
    }

    func testFixtureCoversEverySyncTable() throws {
        for name in SyncTables.all { _ = try table(name) }
        XCTAssertEqual(SyncTables.all, ["tickets", "trips", "favorite_routes", "benefits"])
    }
}
