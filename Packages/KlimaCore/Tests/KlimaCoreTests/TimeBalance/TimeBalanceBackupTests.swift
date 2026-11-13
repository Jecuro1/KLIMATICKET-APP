import XCTest
@testable import KlimaCore

/// The JSON backup carries the time fields as optional keys beside the trip row's own (the row type stands in for the
/// sync DTO `TripDTO`: snake_case keys, a synthesized `Codable`). Encoder and decoder are set up like `Backup` does it.
final class TimeBalanceBackupTests: XCTestCase {
    /// Same shape as the beginning of a `TripDTO`.
    struct Row: Codable, Equatable {
        var id: UUID
        var date: Date
        var from_name: String
        var distance_km: Double
        var is_round_trip: Bool
        var via: String?
    }

    struct File: Codable, Equatable {
        var version: Int
        var trips: [TripTimeBackupRow<Row>]
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private let row = Row(id: UUID(uuidString: "0B9C3B2E-6C1E-4C0B-9F5B-3E1B2C7D8A90")!, date: Date(timeIntervalSince1970: 1_780_000_000),
                          from_name: "St. Anton am Arlberg", distance_km: 101, is_round_trip: true, via: "")

    /// Export from a trip with all three fields (and the arrival), import, compare.
    func testRoundTripWithAllFields() throws {
        let arrival = Date(timeIntervalSince1970: 1_780_004_320)
        let fields = TripTimeBackupFields(durationMinutes: 75, delayMinutes: 12, delaySource: "live", arrivalAt: arrival)
        let file = File(version: 2, trips: [TripTimeBackupRow(row, times: fields)])
        let data = try encoder.encode(file)
        let json = String(decoding: data, as: UTF8.self)
        for key in ["\"duration_minutes\" : 75", "\"delay_minutes\" : 12", "\"delay_source\" : \"live\"", "\"arrival_at\"",
                    "\"from_name\" : \"St. Anton am Arlberg\"", "\"distance_km\" : 101"] {
            XCTAssertTrue(json.contains(key), "\(key) in \(json)")
        }
        // One flat object per trip: no nested "base" / "times".
        XCTAssertFalse(json.contains("\"base\""))
        XCTAssertFalse(json.contains("\"times\""))
        let back = try decoder.decode(File.self, from: data)
        XCTAssertEqual(back, file)
        XCTAssertEqual(back.trips.first?.times.durationMinutes, 75)
        XCTAssertEqual(back.trips.first?.times.delaySource, "live")
        XCTAssertEqual(back.trips.first?.times.arrivalAt, arrival)
    }

    /// A trip without a duration still writes its zeros, so restoring it over an entity with a duration clears that.
    func testDefaultsAreWrittenButAMissingArrivalIsNot() throws {
        let fields = TripTimeBackupFields(durationMinutes: 0, delayMinutes: 0, delaySource: "", arrivalAt: nil)
        let json = String(decoding: try encoder.encode(TripTimeBackupRow(row, times: fields)), as: UTF8.self)
        XCTAssertTrue(json.contains("\"duration_minutes\" : 0"))
        XCTAssertTrue(json.contains("\"delay_source\" : \"\""))
        XCTAssertFalse(json.contains("arrival_at"))
    }

    /// Every backup before the Zeitbilanz: no keys – the row restores, the fields are nil (the app then keeps the
    /// entity's values or the model defaults).
    func testOldBackupWithoutTheKeysRestores() throws {
        let old = """
        {"version": 2, "trips": [{"id": "0B9C3B2E-6C1E-4C0B-9F5B-3E1B2C7D8A90", "date": "2026-05-28T20:26:40Z",
          "from_name": "St. Anton am Arlberg", "distance_km": 101, "is_round_trip": true}]}
        """
        let file = try decoder.decode(File.self, from: Data(old.utf8))
        XCTAssertEqual(file.trips.count, 1)
        XCTAssertEqual(file.trips[0].base.from_name, "St. Anton am Arlberg")
        XCTAssertNil(file.trips[0].base.via)
        XCTAssertTrue(file.trips[0].times.isEmpty)
    }

    /// A broken value never fails the restore: wrong types are dropped, out-of-range values are cleaned.
    func testBrokenValuesAreDroppedOrCleaned() throws {
        let odd = """
        {"id": "0B9C3B2E-6C1E-4C0B-9F5B-3E1B2C7D8A90", "date": "2026-05-28T20:26:40Z", "from_name": "X", "distance_km": 1,
         "is_round_trip": false, "duration_minutes": "lang", "delay_minutes": -7, "delay_source": "radar", "arrival_at": 12}
        """
        let back = try decoder.decode(TripTimeBackupRow<Row>.self, from: Data(odd.utf8))
        XCTAssertNil(back.times.durationMinutes)
        XCTAssertEqual(back.times.delayMinutes, 0)
        XCTAssertEqual(back.times.delaySource, "")
        XCTAssertNil(back.times.arrivalAt)
        XCTAssertEqual(TripTimeBackupFields(durationMinutes: 5000).durationMinutes, 0, "more than a day is no duration")
        XCTAssertEqual(TripTimeBackupFields(durationMinutes: 1440).durationMinutes, 1440)
        XCTAssertEqual(TripTimeBackupFields(delaySource: "manual").delaySource, "manual")
    }

    /// The base row's own decoding errors still surface (a trip without an id is not silently dropped).
    func testABrokenBaseRowStillFails() {
        let broken = """
        {"date": "2026-05-28T20:26:40Z", "from_name": "X", "distance_km": 1, "is_round_trip": false, "duration_minutes": 30}
        """
        XCTAssertThrowsError(try decoder.decode(TripTimeBackupRow<Row>.self, from: Data(broken.utf8)))
    }
}
