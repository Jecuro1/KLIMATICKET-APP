import Foundation
import XCTest
@testable import KlimaCore

/// Fixtures of the tariff-freshness tests: the bundled catalogue and relation table read through the repo-relative path,
/// Vienna dates, small catalogues and a pack builder (stored DEFLATE blocks – no compressor needed).
enum TariffFixtures {
    static let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    static let repoRoot = testsDir.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let resources = repoRoot.appendingPathComponent("App/Resources")
    static let cal = Calendar.vienna

    static func vienna(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// The bundled tariffs.json, decoded like the app does.
    static func bundledCatalog() throws -> TariffCatalog {
        try TariffCatalog.decode(from: Data(contentsOf: resources.appendingPathComponent("tariffs.json")))
    }

    /// Relations in the bundled relations.bin (raw DEFLATE without a header, so the decoded size must be given: 6 bytes
    /// per relation). Update when relations.bin is rebuilt – `testBundledPackMatchesTheBundledTable` says so.
    static let bundledPairCount = 178_013

    /// The bundled relations-points.json and the decoded pairs of relations.bin.
    static func bundledParts() throws -> (meta: RelationPriceTable.PointsFile, triples: [UInt8]) {
        let meta = try JSONDecoder().decode(RelationPriceTable.PointsFile.self,
                                            from: Data(contentsOf: resources.appendingPathComponent("relations-points.json")))
        let packed = [UInt8](try Data(contentsOf: resources.appendingPathComponent("relations.bin")))
        return (meta, try Inflate.decompress(packed, expectedSize: bundledPairCount * 6))
    }

    /// The bundled table as the app builds it.
    static func bundledTable() throws -> RelationPriceTable {
        let (meta, triples) = try bundledParts()
        return RelationPriceTable(validFrom: meta.validFrom, source: meta.source, pointIDs: meta.points.map(\.stationID),
                                  triples: Data(triples), version: meta.version ?? 1)
    }

    /// A minimal catalogue: KlimaTicket Ö with prices from `oeFrom` on (older entries in the history), a fare index.
    static func catalog(updatedAt: String = "2026-10-09", oeFrom: String = "2026-01-01", history: [String] = ["2025-08-01"],
                        fareIndex: [(String, Double)]? = [("2026-12-13", 1.035)],
                        pack: RelationsPackInfo? = nil) -> TariffCatalog {
        let oe = TicketProduct(id: "oe-klassik", family: .oe, name: "KlimaTicket Ö Klassik", variant: .klassik, priceEUR: 1400,
                               validFrom: oeFrom, priceHistory: history.map { .init(validFrom: $0, priceEUR: 1300) })
        let regional = TicketProduct(id: "t-klassik", family: .regional, states: ["T"], name: "Tirol Klassik", variant: .klassik,
                                     priceEUR: 600, validFrom: "2026-04-01")
        return TariffCatalog(version: 5, updatedAt: updatedAt, products: [oe, regional], fareModel: .fallback, cityFares: [],
                             kilometergeldEUR: 0.5, carFullCostPerKmEUR: 0.47, emissions: .fallback,
                             fareIndex: fareIndex?.map { .init(validFrom: $0.0, factor: $0.1) }, relationsPack: pack)
    }
}

// MARK: - Pack builder

/// Builds KBRP packs the way scripts/build_relations_pack.py does, but with stored (uncompressed) DEFLATE blocks.
enum PackBuilder {
    struct Options {
        var magic: [UInt8] = RelationPack.magic
        var format: UInt16 = 1
        var flags: UInt16 = 0
        var pointsCRCDelta: UInt32 = 0
        var trailing: [UInt8] = []
        var dropLast = 0
    }

    /// Raw DEFLATE made of stored blocks (RFC 1951 §3.2.4).
    static func storedDeflate(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var offset = 0
        repeat {
            let n = min(65_535, bytes.count - offset)
            let final = offset + n >= bytes.count
            out.append(final ? 1 : 0)
            out += [UInt8(n & 0xFF), UInt8(n >> 8), UInt8(~n & 0xFF), UInt8((~n >> 8) & 0xFF)]
            out += bytes[offset..<(offset + n)]
            offset += n
        } while offset < bytes.count
        return out
    }

    static func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
    static func le32(_ v: Int) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * $0)) & 0xFF) } }

    /// `pairs` are (pointA, pointB, price in 10-cent units); they are written as given (so tests can break the order).
    static func make(version: Int, validFrom: String, source: String = "test", pointIDs: [String], pairs: [(Int, Int, Int)],
                     options: Options = Options()) -> Data {
        let points = pointIDs.map { "{\"name\":\"\($0)\",\"stationID\":\"\($0)\"}" }.joined(separator: ",")
        let pointsRaw = [UInt8]("{\"source\":\"\(source)\",\"points\":[\(points)]}".utf8)
        var pairsRaw: [UInt8] = []
        pairsRaw.reserveCapacity(pairs.count * 6)
        for (a, b, p) in pairs { pairsRaw += le16(a) + le16(b) + le16(p) }
        return assemble(version: version, validFrom: validFrom, pointCount: pointIDs.count, pairsRaw: pairsRaw,
                        pointsRaw: pointsRaw, options: options)
    }

    /// A pack of the bundled table (same points, same prices times `factor`), as the owner would publish it.
    static func bundled(version: Int, validFrom: String, factor: Double = 1) throws -> Data {
        let (meta, triples) = try TariffFixtures.bundledParts()
        var raw = triples
        if factor != 1 {
            for i in stride(from: 4, to: raw.count, by: 6) {
                let price = Int((Double(Int(raw[i]) | Int(raw[i + 1]) << 8) * factor).rounded())
                raw[i] = UInt8(price & 0xFF)
                raw[i + 1] = UInt8(price >> 8)
            }
        }
        let points = try String(decoding: JSONEncoder().encode(meta.points), as: UTF8.self)
        let pointsRaw = [UInt8]("{\"source\":\"\(meta.source)\",\"points\":\(points)}".utf8)
        return assemble(version: version, validFrom: validFrom, pointCount: meta.points.count, pairsRaw: raw,
                        pointsRaw: pointsRaw, options: Options())
    }

    private static func assemble(version: Int, validFrom: String, pointCount: Int, pairsRaw: [UInt8], pointsRaw: [UInt8],
                                 options: Options) -> Data {
        let p = validFrom.split(separator: "-").map { Int($0)! }
        let pointsStored = storedDeflate(pointsRaw), pairsStored = storedDeflate(pairsRaw)
        var out: [UInt8] = options.magic
        out += le16(Int(options.format)) + le16(Int(options.flags)) + le32(version) + le32(p[0] * 10_000 + p[1] * 100 + p[2])
        out += le32(pointCount) + le32(pairsRaw.count / 6) + le32(pointsStored.count) + le32(pointsRaw.count)
        out += le32(pairsStored.count) + le32(Int(CRC32.checksum(pointsRaw) &+ options.pointsCRCDelta))
        out += le32(Int(CRC32.checksum(pairsRaw))) + le32(0)
        out += pointsStored + pairsStored + options.trailing
        if options.dropLast > 0 { out.removeLast(options.dropLast) }
        return Data(out)
    }

    /// The catalogue block that describes `data` (hash by the test SHA-256).
    static func info(for data: Data, version: Int, validFrom: String, url: String = "relations-pack.bin") -> RelationsPackInfo {
        RelationsPackInfo(url: url, sha256: TestSHA256.hex(data), version: version, validFrom: validFrom, bytes: data.count)
    }

    static let validator = RelationPackValidator(hasher: TestSHA256.hex)

    /// 30 points, every pair once: 435 relations priced 100…534 (€ 10,00…€ 53,40), the shape of a tiny table.
    static func smallPairs(priceScale: Int = 1) -> (ids: [String], pairs: [(Int, Int, Int)]) {
        let ids = (0..<30).map { "at:test:\($0)" }
        var pairs: [(Int, Int, Int)] = []
        var n = 0
        for a in 0..<30 {
            for b in (a + 1)..<30 {
                pairs.append((a, b, (100 + n) * priceScale))
                n += 1
            }
        }
        return (ids, pairs)
    }
}
