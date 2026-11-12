import Foundation
import XCTest
@testable import KlimaCore

/// The validator accepts the bundled table and rejects everything that could put a wrong price table in the app.
final class RelationPackValidatorTests: XCTestCase {
    private typealias F = TariffFixtures
    private let validator = PackBuilder.validator

    /// A small valid pack (30 points, 435 relations) and its catalogue block.
    private func small(version: Int = 2, validFrom: String = "2026-12-13", options: PackBuilder.Options = .init(),
                       pairs customPairs: [(Int, Int, Int)]? = nil) -> (data: Data, info: RelationsPackInfo) {
        let (ids, pairs) = PackBuilder.smallPairs()
        let data = PackBuilder.make(version: version, validFrom: validFrom, pointIDs: ids, pairs: customPairs ?? pairs, options: options)
        return (data, PackBuilder.info(for: data, version: version, validFrom: validFrom))
    }

    private let reference = RelationPackValidator.Reference(pairCount: 435)

    private func assertRejects(_ data: Data, _ info: RelationsPackInfo, _ expected: RelationPackError,
                               reference: RelationPackValidator.Reference? = nil,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try validator.validate(data, expected: info, reference: reference ?? self.reference), file: file, line: line) {
            XCTAssertEqual($0 as? RelationPackError, expected, file: file, line: line)
        }
    }

    // MARK: Accepts

    func testAcceptsAWellFormedPack() throws {
        let (data, info) = small()
        let pack = try validator.validate(data, expected: info, reference: reference)
        XCTAssertEqual(pack.version, 2)
        XCTAssertEqual(pack.validFrom, "2026-12-13")
        XCTAssertEqual(pack.pairCount, 435)
        XCTAssertEqual(pack.points.count, 30)
        let table = pack.table()
        XCTAssertEqual(table.version, 2)
        XCTAssertEqual(table.price(from: "at:test:0", to: "at:test:1"), 10.0)
        XCTAssertEqual(table.price(from: "at:test:1", to: "at:test:0"), 10.0, "symmetric lookup")
        XCTAssertEqual(table.count, 435)
    }

    /// Acceptance: the bundled table, packed the way the owner publishes it, is accepted against itself.
    func testAcceptsThePackedBundledTable() throws {
        let bundled = try F.bundledTable()
        let data = try PackBuilder.bundled(version: 2, validFrom: "2026-12-13", factor: 1.035)
        let info = PackBuilder.info(for: data, version: 2, validFrom: "2026-12-13")
        let pack = try validator.validate(data, expected: info, reference: .init(table: bundled))
        XCTAssertEqual(pack.pairCount, bundled.count)
        let table = pack.table()
        // 3,5 % on a relation of the bundled table (rounded to 10 cent).
        let (a, b) = (pack.points[0].stationID, pack.points[8].stationID)
        let old = try XCTUnwrap(bundled.price(from: a, to: b))
        XCTAssertEqual(try XCTUnwrap(table.price(from: a, to: b)), (old * 1.035 * 10).rounded() / 10, accuracy: 0.0001)
    }

    func testAcceptsTheSameTableWithoutAnIncrease() throws {
        let bundled = try F.bundledTable()
        let data = try PackBuilder.bundled(version: 2, validFrom: "2026-12-13")
        XCTAssertNoThrow(try validator.validate(data, expected: PackBuilder.info(for: data, version: 2, validFrom: "2026-12-13"),
                                                reference: .init(table: bundled)))
    }

    // MARK: Rejects

    func testRejectsAWrongHash() {
        let (data, info) = small()
        var wrong = info
        wrong.sha256 = String(repeating: "0", count: 64)
        assertRejects(data, wrong, .hashMismatch)
        // One flipped byte in the file, hash of the original.
        var bytes = [UInt8](data)
        bytes[bytes.count - 1] ^= 0xFF
        assertRejects(Data(bytes), info, .hashMismatch)
    }

    func testRejectsAnOversizePack() {
        let (_, info) = small()
        let big = Data(count: RelationPack.maxBytes + 1)
        var oversize = info
        oversize.bytes = big.count
        assertRejects(big, oversize, .tooLarge)
        // The catalogue itself may not promise more than the cap.
        let (data, ok) = small()
        var promised = ok
        promised.bytes = RelationPack.maxBytes + 1
        assertRejects(data, promised, .tooLarge)
        // Exactly the cap is fine as a size (it fails later, on content, not on size).
        XCTAssertEqual(RelationPack.maxBytes, 8 * 1024 * 1024)
    }

    func testRejectsASizeThatDiffersFromTheCatalogue() {
        let (data, info) = small()
        var wrong = info
        wrong.bytes += 1
        assertRejects(data, wrong, .sizeMismatch)
    }

    func testRejectsWrongMagicAndFormat() {
        var options = PackBuilder.Options()
        options.magic = [0x4B, 0x42, 0x50, 0x4C]   // "KBPL" – the places file
        var (data, info) = small(options: options)
        assertRejects(data, info, .badMagic)

        options = PackBuilder.Options()
        options.format = 2
        (data, info) = small(options: options)
        assertRejects(data, info, .unsupportedFormat(2))

        options = PackBuilder.Options()
        options.flags = 1
        (data, info) = small(options: options)
        assertRejects(data, info, .corrupt("flags"))
    }

    func testRejectsAVersionOrDayThatDiffersFromTheCatalogue() {
        let (data, info) = small()
        var otherVersion = info
        otherVersion.version = 3
        assertRejects(data, otherVersion, .versionMismatch)
        var otherDay = info
        otherDay.validFrom = "2026-12-14"
        assertRejects(data, otherDay, .validFromMismatch)
    }

    func testRejectsATruncatedOrExtendedFile() {
        var options = PackBuilder.Options()
        options.dropLast = 10
        var (data, info) = small(options: options)
        assertRejects(data, info, .sizeMismatch)

        options = PackBuilder.Options()
        options.trailing = [0, 0, 0]
        (data, info) = small(options: options)
        assertRejects(data, info, .sizeMismatch)

        let tiny = Data("KBRP".utf8)
        assertRejects(tiny, PackBuilder.info(for: tiny, version: 2, validFrom: "2026-12-13"), .truncated)
    }

    func testRejectsABrokenSection() {
        var options = PackBuilder.Options()
        options.pointsCRCDelta = 1
        let (data, info) = small(options: options)
        assertRejects(data, info, .corrupt("points"))
    }

    /// A damaged header that claims gigabytes of relations is refused before anything is allocated for it.
    func testRejectsAHeaderThatClaimsAbsurdlyManyRelations() {
        let (ids, pairs) = PackBuilder.smallPairs()
        var bytes = [UInt8](PackBuilder.make(version: 2, validFrom: "2026-12-13", pointIDs: ids, pairs: pairs))
        bytes.replaceSubrange(20..<24, with: PackBuilder.le32(300_000_000))   // pairCount
        let data = Data(bytes)
        assertRejects(data, PackBuilder.info(for: data, version: 2, validFrom: "2026-12-13"), .corrupt("counts"))
    }

    func testRejectsAPairCountOutlier() throws {
        let (ids, pairs) = PackBuilder.smallPairs()
        // 300 of 435 relations, but the table in use has 435: −31 % is outside ±25 %.
        let data = PackBuilder.make(version: 2, validFrom: "2026-12-13", pointIDs: ids, pairs: Array(pairs.prefix(300)))
        assertRejects(data, PackBuilder.info(for: data, version: 2, validFrom: "2026-12-13"), .pairCountOutlier(300))
        // 330 of 435 is −24,1 %: accepted.
        let near = PackBuilder.make(version: 2, validFrom: "2026-12-13", pointIDs: ids, pairs: Array(pairs.prefix(330)))
        XCTAssertNoThrow(try validator.validate(near, expected: PackBuilder.info(for: near, version: 2, validFrom: "2026-12-13"),
                                                reference: reference))
        // Far too many is just as wrong.
        assertRejects(data, PackBuilder.info(for: data, version: 2, validFrom: "2026-12-13"), .pairCountOutlier(300),
                      reference: .init(pairCount: 100))
    }

    func testRejectsPricesOutsideTheRange() {
        let (ids, pairs) = PackBuilder.smallPairs()
        func rejected(_ price: Int, _ expected: RelationPackError) {
            var broken = pairs
            broken[7].2 = price
            let data = PackBuilder.make(version: 2, validFrom: "2026-12-13", pointIDs: ids, pairs: broken)
            assertRejects(data, PackBuilder.info(for: data, version: 2, validFrom: "2026-12-13"), expected)
        }
        rejected(0, .priceOutOfRange)
        rejected(65_535, .priceOutOfRange)   // the clamp value of the build script
        rejected(RelationPackValidator.maxPriceUnits + 1, .priceOutOfRange)
    }

    func testRejectsAPackThatIsNotSymmetricOrCanonical() {
        let (ids, pairs) = PackBuilder.smallPairs()
        func rejected(_ broken: [(Int, Int, Int)]) {
            let data = PackBuilder.make(version: 2, validFrom: "2026-12-13", pointIDs: ids, pairs: broken)
            assertRejects(data, PackBuilder.info(for: data, version: 2, validFrom: "2026-12-13"), .pairOrder)
        }
        var reversed = pairs
        reversed[3] = (reversed[3].1, reversed[3].0, reversed[3].2)       // B before A: the other direction
        rejected(reversed)
        var duplicate = pairs
        duplicate[10] = duplicate[9]                                      // the same relation twice
        rejected(duplicate)
        var unordered = pairs
        unordered.swapAt(4, 5)
        rejected(unordered)
        var outOfRange = pairs
        outOfRange[0] = (0, 99, 150)                                      // a point that does not exist
        rejected(outOfRange)
        var same = pairs
        same[2] = (5, 5, 150)
        rejected(same)
    }

    func testRejectsPricesInTheWrongUnit() throws {
        // Every price 10 times too high (cents instead of 10-cent units), against a table that knows the same relations.
        let (ids, pairs) = PackBuilder.smallPairs()
        let table = RelationPriceTable(validFrom: "2025-12-14", source: "test", pointIDs: ids,
                                       triples: Data(pairs.flatMap { PackBuilder.le16($0.0) + PackBuilder.le16($0.1) + PackBuilder.le16($0.2) }))
        let tenfold = PackBuilder.smallPairs(priceScale: 10).pairs
        let data = PackBuilder.make(version: 2, validFrom: "2026-12-13", pointIDs: ids, pairs: tenfold)
        assertRejects(data, PackBuilder.info(for: data, version: 2, validFrom: "2026-12-13"), .priceOutlier, reference: .init(table: table))
        // A 3,5 % increase against the same table is fine.
        let raised = pairs.map { ($0.0, $0.1, Int((Double($0.2) * 1.035).rounded())) }
        let ok = PackBuilder.make(version: 2, validFrom: "2026-12-13", pointIDs: ids, pairs: raised)
        XCTAssertNoThrow(try validator.validate(ok, expected: PackBuilder.info(for: ok, version: 2, validFrom: "2026-12-13"),
                                                reference: .init(table: table)))
    }

    func testRejectsDuplicateOrEmptyStationIDs() {
        let (ids, pairs) = PackBuilder.smallPairs()
        var duplicated = ids
        duplicated[3] = duplicated[2]
        let data = PackBuilder.make(version: 2, validFrom: "2026-12-13", pointIDs: duplicated, pairs: pairs)
        assertRejects(data, PackBuilder.info(for: data, version: 2, validFrom: "2026-12-13"), .corrupt("points"))
    }

    func testHashComparisonIgnoresCase() throws {
        let (data, info) = small()
        var upper = info
        upper.sha256 = info.sha256.uppercased()
        XCTAssertNoThrow(try validator.validate(data, expected: upper, reference: reference))
    }
}
