import Foundation
import XCTest
@testable import KlimaCore

/// Facilities of a stop (ENRICH_SPEC §1.11): decoding of the EQUI section, missing and corrupt sections, the
/// reference stops of the shipped stops_osm.bin, and the honest German presentation.
final class PlaceEquipmentTests: XCTestCase {
    private static let features = ["elevator", "toilets", "bicycle_parking", "ticket_machine", "shelter", "bench",
                                   "tactile_paving", "departures_board", "wheelchair"]
    private static let bits: [String: [Int]] = [
        "nearby": [44, 9], "elevator_n": [18, 4], "toilets_n": [22, 4], "toilets_wheelchair": [26, 2],
        "toilets_fee": [28, 2], "bicycle_stands": [30, 8], "bicycle_covered": [38, 2], "ticket_n": [40, 4],
    ]

    private static func meta(features: [String] = features, bits: [String: [Int]] = bits, version: Int = 1) -> [String: Any] {
        ["equipment": ["v": version, "record": "u64le", "features": features, "bits": bits] as [String: Any]]
    }

    /// Packs one stop word the way build_tags.py does.
    private static func word(states: [Int: Int] = [:], nearby: Set<Int> = [], elevatorN: Int = 0, toiletsN: Int = 0,
                             toiletWheelchair: Int = 0, toiletFee: Int = 0, stands: Int = 0, covered: Int = 0,
                             ticketN: Int = 0) -> UInt64 {
        var w: UInt64 = 0
        for (slot, st) in states { w |= UInt64(st) << UInt64(2 * slot) }
        for slot in nearby { w |= UInt64(1) << UInt64(44 + slot) }
        w |= UInt64(elevatorN) << 18 | UInt64(toiletsN) << 22 | UInt64(toiletWheelchair) << 26
        w |= UInt64(toiletFee) << 28 | UInt64(stands) << 30 | UInt64(covered) << 38 | UInt64(ticketN) << 40
        return w
    }

    private static func section(_ words: [UInt64]) -> [UInt8] {
        words.flatMap { w in (0..<8).map { UInt8((w >> UInt64(8 * $0)) & 0xFF) } }
    }

    private static func facility(_ list: [StopFacility], _ kind: FacilityKind) -> StopFacility {
        list.first { $0.kind == kind }!
    }

    // MARK: Decoding

    func testDecodesStopWordWithCountsStatesAndSources() throws {
        let w = Self.word(states: [0: 2, 1: 2, 2: 2, 3: 2, 4: 2, 5: 1, 7: 3, 8: 3], nearby: [0, 1, 2, 3],
                          elevatorN: 3, toiletsN: 2, toiletWheelchair: 3, toiletFee: 1, stands: 42, covered: 2, ticketN: 5)
        let eq = try XCTUnwrap(PlaceEquipment(section: Self.section([w]), meta: Self.meta(), stopCount: 1))
        let list = eq.facilities(stop: 0)
        XCTAssertEqual(list.map(\.kind), FacilityKind.allCases)

        let lift = Self.facility(list, .elevator)
        XCTAssertEqual(lift.status, .present)
        XCTAssertEqual(lift.count, 3)
        XCTAssertEqual(lift.source, .nearbyObject)

        let wc = Self.facility(list, .toilets)
        XCTAssertEqual(wc.count, 2)
        XCTAssertEqual(wc.toiletWheelchair, .limited)
        XCTAssertEqual(wc.toiletFee, false)

        let bike = Self.facility(list, .bicycleParking)
        XCTAssertEqual(bike.count, 42)
        XCTAssertEqual(bike.covered, true)
        XCTAssertFalse(bike.countIsAtLeast)

        XCTAssertEqual(Self.facility(list, .ticketMachine).count, 5)
        XCTAssertEqual(Self.facility(list, .bench).status, .absent)
        XCTAssertEqual(Self.facility(list, .bench).source, .stopTag)
        XCTAssertEqual(Self.facility(list, .tactilePaving).status, .notRecorded)
        XCTAssertNil(Self.facility(list, .tactilePaving).source, "not recorded has no source")
        XCTAssertEqual(Self.facility(list, .departuresBoard).status, .realtime)
        XCTAssertEqual(Self.facility(list, .wheelchair).status, .limited)
        XCTAssertEqual(Self.facility(list, .wheelchair).source, .stopTag)
    }

    func testCappedCountsAreMarkedAsAtLeast() throws {
        let w = Self.word(states: [0: 2, 2: 2], nearby: [0, 2], elevatorN: 15, stands: 255)
        let eq = try XCTUnwrap(PlaceEquipment(section: Self.section([w]), meta: Self.meta(), stopCount: 1))
        XCTAssertTrue(Self.facility(eq.facilities(stop: 0), .elevator).countIsAtLeast)
        XCTAssertTrue(Self.facility(eq.facilities(stop: 0), .bicycleParking).countIsAtLeast)
    }

    func testSlotsResolveByNameNotPosition() throws {
        // Same bits, feature list in another order: the wheelchair state sits in the slot named "wheelchair".
        let reordered = ["wheelchair", "elevator", "toilets", "bicycle_parking", "ticket_machine", "shelter", "bench",
                         "tactile_paving", "departures_board"]
        let w = Self.word(states: [0: 1])                       // slot 0 = wheelchair in the reordered META
        let eq = try XCTUnwrap(PlaceEquipment(section: Self.section([w]), meta: Self.meta(features: reordered), stopCount: 1))
        XCTAssertEqual(Self.facility(eq.facilities(stop: 0), .wheelchair).status, .absent)
        XCTAssertEqual(Self.facility(eq.facilities(stop: 0), .elevator).status, .notRecorded)
    }

    func testStopsOutsideTheSectionAreEmpty() throws {
        let eq = try XCTUnwrap(PlaceEquipment(section: Self.section([0, 0]), meta: Self.meta(), stopCount: 2))
        XCTAssertEqual(eq.facilities(stop: 2), [])
        XCTAssertEqual(eq.facilities(stop: -1), [])
        XCTAssertTrue(eq.facilities(stop: 1).allSatisfy { $0.status == .notRecorded && $0.source == nil })
    }

    // MARK: Missing and corrupt sections

    func testMissingSectionMeansNoFacilityData() {
        XCTAssertNil(PlaceEquipment(section: nil, meta: Self.meta(), stopCount: 2))
    }

    func testMissingOrForeignMetaMeansNoFacilityData() {
        let bytes = Self.section([0, 0])
        XCTAssertNil(PlaceEquipment(section: bytes, meta: nil, stopCount: 2))
        XCTAssertNil(PlaceEquipment(section: bytes, meta: ["build": [:]], stopCount: 2))
        XCTAssertNil(PlaceEquipment(section: bytes, meta: Self.meta(version: 2), stopCount: 2))
    }

    func testWrongLengthIsRejected() {
        XCTAssertNil(PlaceEquipment(section: Self.section([0]), meta: Self.meta(), stopCount: 2))
        XCTAssertNil(PlaceEquipment(section: Self.section([0, 0, 0]), meta: Self.meta(), stopCount: 2))
        XCTAssertNil(PlaceEquipment(section: [], meta: Self.meta(), stopCount: 0))
    }

    func testInconsistentLayoutIsRejected() {
        var badBits = Self.bits
        badBits["nearby"] = [60, 9]                             // runs past bit 63
        XCTAssertNil(PlaceEquipment(section: Self.section([0]), meta: Self.meta(bits: badBits), stopCount: 1))
        var missingField = Self.bits
        missingField["toilets_fee"] = nil
        XCTAssertNil(PlaceEquipment(section: Self.section([0]), meta: Self.meta(bits: missingField), stopCount: 1))
        var overlapping = Self.bits
        overlapping["ticket_n"] = [44, 4]                       // inside the nearby bits
        XCTAssertNil(PlaceEquipment(section: Self.section([0]), meta: Self.meta(bits: overlapping), stopCount: 1))
    }

    func testRandomWordsNeverTrapAndKeepTheInvariants() throws {
        var rng = SystemRandomNumberGenerator()
        let words = (0..<400).map { _ in UInt64.random(in: 0...UInt64.max, using: &rng) }
        let eq = try XCTUnwrap(PlaceEquipment(section: Self.section(words), meta: Self.meta(), stopCount: words.count))
        for i in words.indices {
            let list = eq.facilities(stop: i)
            XCTAssertEqual(list.count, FacilityKind.allCases.count)
            for f in list {
                XCTAssertEqual(f.source == nil, f.status == .notRecorded, "source is set exactly when recorded")
                if f.count > 0 { XCTAssertTrue(f.isPresent, "counts only for present facilities") }
            }
        }
    }

    func testCorruptSectionInTheContainerSwitchesOnlyFacilitiesOff() throws {
        var data = try Data(contentsOf: PlaceFixtures.osmURL)
        let container = try KBPLContainer(data: data)
        let entry = try XCTUnwrap(container.entry("EQUI"))
        // Flip a byte inside the stored DEFLATE stream: inflate or the CRC must reject it.
        let at = entry.offset + entry.storedLength / 2
        data[at] ^= 0xFF
        let base = try XCTUnwrap(PlaceFixtures.dataset.officialLayer?.section("BASE"))
        let result = PlaceDataset.loadOSMLayer(data, official: PlaceFixtures.dataset.officialLayer)
        guard case .success(let layer) = result else {
            return XCTFail("the rest of the OSM layer must stay usable, got \(result)")
        }
        XCTAssertNil(layer.section("EQUI"))
        XCTAssertNil(PlaceEquipment(section: layer.section("EQUI"), meta: layer.metaJSON, stopCount: layer.nStopRecords))
        XCTAssertEqual(base.count, 32)
        XCTAssertNotNil(layer.section("TAGS"), "other sections are unaffected")
    }

    // MARK: Reference stops of the shipped stops_osm.bin

    func testReferenceStopsHaveTheirOSMFacilities() {
        let index = PlaceFixtures.index
        XCTAssertTrue(index.hasFacilityData)

        let innsbruck = index.facilities(for: "at:47:1187")           // Innsbruck Hauptbahnhof
        XCTAssertEqual(innsbruck.count, FacilityKind.allCases.count)
        XCTAssertEqual(Self.facility(innsbruck, .wheelchair).status, .present)
        XCTAssertEqual(Self.facility(innsbruck, .wheelchair).source, .stopTag)
        XCTAssertEqual(Self.facility(innsbruck, .shelter).status, .present)
        XCTAssertEqual(Self.facility(innsbruck, .elevator).status, .present)
        XCTAssertEqual(Self.facility(innsbruck, .elevator).source, .nearbyObject)
        XCTAssertEqual(Self.facility(innsbruck, .toilets).toiletWheelchair, .present)
        XCTAssertEqual(Self.facility(innsbruck, .toilets).toiletFee, true)
        XCTAssertEqual(Self.facility(innsbruck, .bicycleParking).covered, true)
        XCTAssertEqual(Self.facility(innsbruck, .departuresBoard).status, .notRecorded,
                       "no departure board tag in OSM is not a missing board")

        let warth = PlaceFixtures.index.facilities(for: "at:48:344")  // Warth (Vorarlberg) Dorfplatz
        XCTAssertEqual(Self.facility(warth, .shelter).status, .absent)     // shelter=no on the stop
        XCTAssertEqual(Self.facility(warth, .shelter).source, .stopTag)
        XCTAssertEqual(Self.facility(warth, .bench).status, .present)
        XCTAssertEqual(Self.facility(warth, .tactilePaving).status, .absent)
        XCTAssertEqual(Self.facility(warth, .wheelchair).status, .notRecorded)
        XCTAssertEqual(Self.facility(warth, .toilets).status, .notRecorded)

        let wien = index.facilities(for: "at:49:1349")                // Wien Hauptbahnhof
        XCTAssertEqual(Self.facility(wien, .elevator).status, .present)
        XCTAssertEqual(Self.facility(wien, .ticketMachine).status, .present)
        XCTAssertEqual(Self.facility(wien, .toilets).status, .notRecorded)

        let lech = index.facilities(for: "at:48:1264")                // Lech am Arlberg Dorfhus (stand-in)
        XCTAssertEqual(Self.facility(lech, .wheelchair).status, .absent)
        XCTAssertEqual(Self.facility(lech, .toilets).toiletFee, false)

        XCTAssertEqual(index.facilities(for: "at:48:99999"), [], "unknown place: no facilities, no error")
    }

    // MARK: Presentation

    func testRowsAreHonestAndAccessible() {
        let list = [StopFacility(kind: .elevator, status: .present, count: 2, source: .nearbyObject),
                    StopFacility(kind: .shelter, status: .absent, source: .stopTag)]
        let rows = FacilityPresentation.rows(list)
        XCTAssertEqual(rows.map(\.kind), FacilityPresentation.order)
        let lift = rows.first { $0.kind == .elevator }!
        XCTAssertEqual(lift.title, "Aufzug")
        XCTAssertEqual(lift.symbol, "arrow.up.arrow.down.square")
        XCTAssertEqual(lift.statusText, "laut OpenStreetMap vorhanden")
        XCTAssertEqual(lift.detail, "2 Aufzüge")
        XCTAssertEqual(lift.accessibilityLabel, "Aufzug: laut OpenStreetMap vorhanden, 2 Aufzüge, Objekt in bis zu 40 m")
        let wheel = rows.first { $0.kind == .wheelchair }!
        XCTAssertEqual(wheel.tone, .neutral)
        XCTAssertEqual(wheel.statusText, "nicht erfasst")
        XCTAssertEqual(wheel.accessibilityLabel, "Barrierefrei: nicht erfasst")
        XCTAssertEqual(rows.first { $0.kind == .shelter }?.statusText, "laut OpenStreetMap nicht vorhanden")
    }

    func testNothingIsClaimedMissingFromAMissingEntry() {
        let rows = FacilityPresentation.rows([])
        XCTAssertTrue(rows.allSatisfy { $0.statusText == "nicht erfasst" && $0.tone == .neutral })
        for row in rows {
            XCTAssertFalse(row.accessibilityLabel.localizedCaseInsensitiveContains("fehlt"))
            XCTAssertFalse(row.statusText.localizedCaseInsensitiveContains("fehlt"))
        }
    }

    func testRouteChipsAreAtMostThreePositiveFacilities() {
        let all = FacilityKind.allCases.map { StopFacility(kind: $0, status: .present, source: .stopTag) }
        let chips = FacilityPresentation.routeChips(all)
        XCTAssertEqual(chips.count, 3)
        XCTAssertEqual(chips.map(\.kind), [.wheelchair, .elevator, .toilets])
        XCTAssertTrue(FacilityPresentation.routeChips([]).isEmpty)
        let absentOnly = [StopFacility(kind: .elevator, status: .absent, source: .stopTag)]
        XCTAssertTrue(FacilityPresentation.routeChips(absentOnly).isEmpty)
    }

    func testToiletDetailAndSourceLine() {
        let wc = StopFacility(kind: .toilets, status: .present, count: 1, source: .nearbyObject,
                              toiletWheelchair: .present, toiletFee: true)
        XCTAssertEqual(FacilityPresentation.row(wc).detail, "1 WC · rollstuhlgerecht · kostenpflichtig")
        let date = Date(timeIntervalSince1970: 1_791_590_400)   // 2026-10-08T00:00:00Z: 8. or 9. Oktober in Wien
        let line = FacilityPresentation.sourceLine(buildDate: date)
        XCTAssertTrue(line.hasPrefix("© OpenStreetMap-Mitwirkende, ODbL 1.0 · Stand "), line)
        XCTAssertEqual(FacilityPresentation.sourceLine(buildDate: nil), "© OpenStreetMap-Mitwirkende, ODbL 1.0")
    }
}
