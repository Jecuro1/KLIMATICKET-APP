import Foundation
import XCTest
@testable import KlimaCore

/// The shape of the bundled App/Resources/tariffs.json (read through the repo-relative path), the optional `relationsPack`
/// block and the factor that keeps a newer relation table from counting a price increase twice.
final class TariffCatalogStructureTests: XCTestCase {
    private typealias F = TariffFixtures

    /// Everything the owner's data must satisfy; the test below runs it on the real file, the next one on a broken copy.
    static func problems(in catalog: TariffCatalog) -> [String] {
        var problems: [String] = []
        var seen = Set<String>()
        for product in catalog.products {
            if !seen.insert(product.id).inserted { problems.append("duplicate id \(product.id)") }
            if !(product.priceEUR.isFinite && product.priceEUR > 0) { problems.append("\(product.id): price \(product.priceEUR)") }
            if !TariffFreshness.isISODay(product.validFrom) { problems.append("\(product.id): validFrom \(product.validFrom)") }
            let history = product.priceHistory ?? []
            for point in history where !(point.priceEUR.isFinite && point.priceEUR > 0) {
                problems.append("\(product.id): history price \(point.priceEUR) at \(point.validFrom)")
            }
            let days = history.map(\.validFrom) + [product.validFrom]
            for (a, b) in zip(days, days.dropFirst()) where !(a < b) {
                problems.append("\(product.id): validFrom not strictly ascending (\(a) before \(b))")
            }
        }
        let index = (catalog.fareIndex ?? []).map(\.validFrom)
        for (a, b) in zip(index, index.dropFirst()) where !(a < b) { problems.append("fareIndex not strictly ascending (\(a), \(b))") }
        for point in catalog.fareIndex ?? [] where !(point.factor.isFinite && point.factor > 0.5 && point.factor < 2) {
            problems.append("fareIndex factor \(point.factor)")
        }
        return problems
    }

    func testBundledCatalogueIsStructurallySound() throws {
        let catalog = try F.bundledCatalog()
        XCTAssertEqual(catalog.products.count, 80, "the 80 products")
        XCTAssertEqual(Self.problems(in: catalog), [])
        XCTAssertTrue(catalog.isUsable)
        XCTAssertTrue(catalog.products.contains { $0.family == .oe }, "KlimaTicket Ö is there – the new-year notice needs it")
    }

    /// "Try it once": a validFrom out of order must fail the structure check.
    func testTheStructureCheckFailsWhenAValidFromIsOutOfOrder() throws {
        var catalog = try F.bundledCatalog()
        let index = try XCTUnwrap(catalog.products.firstIndex { ($0.priceHistory?.count ?? 0) >= 2 })
        catalog.products[index].priceHistory?.swapAt(0, 1)
        let found = Self.problems(in: catalog)
        XCTAssertFalse(found.isEmpty)
        XCTAssertTrue(found.contains { $0.contains("not strictly ascending") }, "\(found)")

        var duplicated = try F.bundledCatalog()
        duplicated.products.append(duplicated.products[0])
        XCTAssertTrue(Self.problems(in: duplicated).contains { $0.hasPrefix("duplicate id") })

        var free = try F.bundledCatalog()
        free.products[3].priceEUR = 0
        XCTAssertFalse(Self.problems(in: free).isEmpty)
    }

    func testBundledCatalogueCarriesTheRelationPackBlockAndThePackFileMatchesIt() throws {
        let catalog = try F.bundledCatalog()
        let info = try XCTUnwrap(catalog.relationsPack, "tariffs.json names the relation pack (scripts/build_tariffs.py)")
        XCTAssertEqual(info.url, "relations-pack.bin")
        let file = try Data(contentsOf: F.repoRoot.appendingPathComponent("data/relations-pack.bin"))
        XCTAssertEqual(file.count, info.bytes, "data/relations-pack.bin is not the file tariffs.json describes")
        XCTAssertEqual(TestSHA256.hex(file), info.sha256)
        // The validator accepts it against the bundled table, which is what the app does at install time.
        let reference = RelationPackValidator.Reference(table: try F.bundledTable())
        let pack = try PackBuilder.validator.validate(file, expected: info, reference: reference)
        XCTAssertEqual(pack.version, info.version)
        XCTAssertEqual(pack.validFrom, info.validFrom)
    }

    func testBundledPackMatchesTheBundledTable() throws {
        let table = try F.bundledTable()
        XCTAssertEqual(table.count, F.bundledPairCount, "relations.bin was rebuilt: update TariffFixtures.bundledPairCount")
        let catalog = try F.bundledCatalog()
        let file = try Data(contentsOf: F.repoRoot.appendingPathComponent("data/relations-pack.bin"))
        let pack = try RelationPack.parse(file)
        XCTAssertEqual(pack.pairCount, table.count)
        XCTAssertEqual(pack.validFrom, table.validFrom)
        XCTAssertEqual(pack.version, table.version, "the published pack is the bundled table until a newer one is published")
        // Spot checks: the same prices through the pack table and the bundled table.
        let packTable = pack.table()
        let ids = pack.points.map(\.stationID)
        var compared = 0
        for a in stride(from: 0, to: ids.count, by: 7) {
            for b in stride(from: a + 1, to: ids.count, by: 11) {
                XCTAssertEqual(packTable.price(from: ids[a], to: ids[b]), table.price(from: ids[a], to: ids[b]))
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 1_000)
        XCTAssertEqual(catalog.relationsPack?.validFrom, table.validFrom)
    }

    // MARK: Old documents still decode

    func testACatalogueWithoutRelationsPackStillDecodes() throws {
        let data = try Data(contentsOf: F.resources.appendingPathComponent("tariffs.json"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object.removeValue(forKey: "relationsPack"))
        let old = try TariffCatalog.decode(from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.relationsPack)
        XCTAssertEqual(old.products.count, 80)
        XCTAssertTrue(old.isUsable)
    }

    func testAMinimalOldCatalogueStillDecodes() throws {
        let json = """
        {"version":1,"updatedAt":"2026-01-01","currency":"EUR","products":[],"fareModel":{"baseFee":0.456,"bands":[],"minimumFare":2.4,
        "maximumFare":101.2,"roundingStep":0.1,"firstClassFactor":1.951,"detourFactor":1.2,"discountFactors":{}},"cityFares":[],
        "kilometergeldEUR":0.5,"carFullCostPerKmEUR":0.47,"emissions":{"car":174,"train":7.2,"bus":50.7,"tram":7.2},"notes":[]}
        """
        let catalog = try TariffCatalog.decode(from: Data(json.utf8))
        XCTAssertNil(catalog.relationsPack)
        XCTAssertNil(catalog.fareIndex)
    }

    func testRelationPackBlockRoundTrips() throws {
        let info = RelationsPackInfo(url: "relations-pack.bin", sha256: "ab", version: 2, validFrom: "2026-12-13", bytes: 10)
        let catalog = F.catalog(pack: info)
        let back = try TariffCatalog.decode(from: JSONEncoder().encode(catalog))
        XCTAssertEqual(back.relationsPack, info)
    }

    // MARK: Pack URLs

    func testPackURLResolvesNextToTheTariffsDocument() throws {
        let tariffs = URL(string: "https://github.com/Jecuro1/KLIMATICKET-APP/releases/latest/download/tariffs.json")!
        let info = RelationsPackInfo(url: "relations-pack.bin", sha256: "", version: 2, validFrom: "2026-12-13", bytes: 1)
        XCTAssertEqual(info.resolvedURL(relativeTo: tariffs)?.absoluteString,
                       "https://github.com/Jecuro1/KLIMATICKET-APP/releases/latest/download/relations-pack.bin")
    }

    func testPackURLMustStayOnTheOwnersHostAndBeHTTPS() {
        let tariffs = URL(string: "https://github.com/o/r/releases/latest/download/tariffs.json")
        func resolved(_ url: String, _ base: URL? = tariffs) -> URL? {
            RelationsPackInfo(url: url, sha256: "", version: 2, validFrom: "2026-12-13", bytes: 1).resolvedURL(relativeTo: base)
        }
        XCTAssertNotNil(resolved("https://github.com/o/r/releases/latest/download/relations-pack.bin"))
        XCTAssertNotNil(resolved("https://raw.githubusercontent.com/o/r/main/data/relations-pack.bin"), "GitHub's own raw host")
        XCTAssertNil(resolved("https://example.com/relations-pack.bin"), "another host")
        XCTAssertNil(resolved("http://github.com/o/r/relations-pack.bin"), "no plain http")
        XCTAssertNil(resolved("https://user:pw@github.com/o/r/relations-pack.bin"), "no user info")
        XCTAssertNil(resolved("ftp://github.com/relations-pack.bin"))
        XCTAssertNil(resolved("relations-pack.bin", nil), "nothing to anchor a relative path to")
        XCTAssertNil(resolved("https://github.com/x.bin", URL(string: "https://example.com/tariffs.json")), "tariffs elsewhere")
        XCTAssertNotNil(resolved("https://example.com/relations-pack.bin", URL(string: "https://example.com/tariffs.json")))
        XCTAssertNil(resolved(""))
    }

    // MARK: A newer table never counts an increase twice

    func testRelativeFareFactor() {
        let catalog = F.catalog()   // fare index: +3,5 % from 2026-12-13
        let after = F.vienna(2026, 12, 14), before = F.vienna(2026, 10, 1)
        // The bundled table (2025-12-14) does not hold the increase: it applies from 13 December.
        XCTAssertEqual(catalog.fareFactor(on: after, relativeTo: "2025-12-14"), 1.035, accuracy: 1e-12)
        XCTAssertEqual(catalog.fareFactor(on: before, relativeTo: "2025-12-14"), 1, accuracy: 1e-12)
        // A table valid from 13 December holds it: no second increase, and a trip before it is brought back.
        XCTAssertEqual(catalog.fareFactor(on: after, relativeTo: "2026-12-13"), 1, accuracy: 1e-12)
        XCTAssertEqual(catalog.fareFactor(on: before, relativeTo: "2026-12-13"), 1 / 1.035, accuracy: 1e-12)
        // No usable day: the plain factor, as before.
        XCTAssertEqual(catalog.fareFactor(on: after, relativeTo: ""), 1.035, accuracy: 1e-12)
        XCTAssertEqual(catalog.fareFactor(on: after), 1.035, accuracy: 1e-12)
    }

    func testEstimatorDoesNotApplyTheIncreaseAgainForANewerTable() throws {
        let a = Station(id: "at:test:a", name: "A", lat: 47.0, lon: 11.0, state: "T")
        let b = Station(id: "at:test:b", name: "B", lat: 47.3, lon: 11.3, state: "T")
        func table(validFrom: String) throws -> RelationPriceTable {
            let json = "{\"validFrom\":\"\(validFrom)\",\"source\":\"test\",\"points\":[{\"name\":\"A\",\"stationID\":\"at:test:a\"},"
                + "{\"name\":\"B\",\"stationID\":\"at:test:b\"}],\"prices\":[[0,1,3500]]}"
            return try RelationPriceTable(jsonData: Data(json.utf8))
        }
        let catalog = F.catalog()
        let day = F.vienna(2026, 12, 20)
        let old = FareEstimator(catalog: catalog, relations: try table(validFrom: "2025-12-14"))
            .estimate(from: a, to: b, mode: .train, date: day)
        XCTAssertEqual(old.method, .officialTable)
        XCTAssertEqual(old.fareEUR, 36.2, accuracy: 0.001, "€ 35,00 + 3,5 %")
        let new = FareEstimator(catalog: catalog, relations: try table(validFrom: "2026-12-13"))
            .estimate(from: a, to: b, mode: .train, date: day)
        XCTAssertEqual(new.fareEUR, 35.0, accuracy: 0.001, "the table already holds the increase")
        XCTAssertTrue(new.explanation.contains("Tarif ab 13.12.2026"), new.explanation)
        // And an old trip against the new table comes back to the old level.
        let early = FareEstimator(catalog: catalog, relations: try table(validFrom: "2026-12-13"))
            .estimate(from: a, to: b, mode: .train, date: F.vienna(2026, 10, 1))
        XCTAssertEqual(early.fareEUR, 33.8, accuracy: 0.001, "€ 35,00 / 1,035, rounded to 10 cent")
    }

    func testPreferredTablePrefersANewerPackFromItsValidFromDay() throws {
        func table(_ version: Int, _ validFrom: String, price: Int) -> RelationPriceTable {
            let units = price / 10   // 10-cent units
            return RelationPriceTable(validFrom: validFrom, source: "test", pointIDs: ["a", "b"],
                                      triples: Data([0, 0, 1, 0, UInt8(units & 0xFF), UInt8(units >> 8)]), version: version)
        }
        let bundled = table(1, "2025-12-14", price: 3500)
        let pack = table(2, "2026-12-13", price: 3640)
        XCTAssertEqual(RelationPriceTable.preferred(bundled: bundled, pack: pack, today: "2026-12-12").validFrom, "2025-12-14", "not yet valid")
        XCTAssertEqual(RelationPriceTable.preferred(bundled: bundled, pack: pack, today: "2026-12-13").validFrom, "2026-12-13")
        XCTAssertEqual(RelationPriceTable.preferred(bundled: bundled, pack: nil, today: "2027-01-01").validFrom, "2025-12-14")
        // A pack that is not newer than the bundled table (an app update shipped the same or a newer one) is ignored.
        let same = table(1, "2026-12-13", price: 3640)
        XCTAssertEqual(RelationPriceTable.preferred(bundled: bundled, pack: same, today: "2027-01-01").validFrom, "2025-12-14")
        XCTAssertEqual(RelationPriceTable.preferred(bundled: pack, pack: bundled, today: "2027-01-01").validFrom, "2026-12-13")
        XCTAssertEqual(RelationPriceTable.preferred(bundled: bundled, pack: pack, today: "").validFrom, "2025-12-14", "no usable day")
    }
}
