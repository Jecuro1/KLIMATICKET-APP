import Foundation

/// A relation-price table as one downloadable file ("KBRP", docs/TARIFF_FRESHNESS.md §3): the same content as the bundled
/// `relations-points.json` + `relations.bin`, plus what the app needs to trust it. Little endian:
///
/// ```
///  0 "KBRP" | 4 u16 format (1) | 6 u16 flags (0) | 8 u32 data version | 12 u32 validFrom (yyyymmdd)
/// 16 u32 pointCount | 20 u32 pairCount | 24 u32 pointsStoredLength | 28 u32 pointsRawLength
/// 32 u32 pairsStoredLength | 36 u32 pointsCRC32 | 40 u32 pairsCRC32 | 44 u32 0
/// 48 points section: raw DEFLATE of UTF-8 JSON {"source": "…", "points": [{"name": …, "stationID": …}]}
///    pairs section: raw DEFLATE of pairCount × (u16 pointA, u16 pointB, u16 price in 10-cent units)
/// ```
///
/// Pairs are stored once (A < B), strictly ascending by (A, B): that is what "symmetric" means here – a relation has one
/// price, valid in both directions, and no second, possibly different one. The file must be exactly header + sections.
public struct RelationPack: Sendable {
    public static let magic: [UInt8] = [0x4B, 0x42, 0x52, 0x50]   // "KBRP"
    public static let formatVersion = 1
    public static let headerSize = 48
    /// Largest file accepted (the bundled table is 0.6 MB).
    public static let maxBytes = 8 << 20
    /// Decoded points JSON (≈ 100 KB today) may not exceed this.
    static let maxPointsRawBytes = 4 << 20
    /// Most relations a pack may declare (the bundled table has 178 013): a header that claims more is damaged and must not
    /// make the app allocate gigabytes before the plausibility checks run.
    static let maxPairs = 4_000_000

    public let version: Int
    /// ISO day "2026-12-13".
    public let validFrom: String
    public let source: String
    public let points: [RelationPriceTable.File.Point]
    /// Decoded pairs, 6 bytes each (u16 A, u16 B, u16 price in 10-cent units), little endian.
    public let triples: Data

    public var pairCount: Int { triples.count / 6 }

    /// The pack as a price table (what the estimators use).
    public func table() -> RelationPriceTable {
        RelationPriceTable(validFrom: validFrom, source: source, pointIDs: points.map(\.stationID), triples: triples,
                           version: version)
    }

    /// Reads the structure: magic, format, lengths, CRC-32 of both sections, JSON. Nothing about the *content* is judged
    /// here (see `RelationPackValidator`).
    public static func parse(_ data: Data) throws -> RelationPack {
        guard data.count <= maxBytes else { throw RelationPackError.tooLarge }
        guard data.count >= headerSize else { throw RelationPackError.truncated }
        let bytes = [UInt8](data)
        guard Array(bytes[0..<4]) == magic else { throw RelationPackError.badMagic }
        let format = Int(u16(bytes, 4))
        guard format == formatVersion else { throw RelationPackError.unsupportedFormat(format) }
        guard u16(bytes, 6) == 0 else { throw RelationPackError.corrupt("flags") }
        let version = Int(u32(bytes, 8))
        let day = Int(u32(bytes, 12))
        let pointCount = Int(u32(bytes, 16)), pairCount = Int(u32(bytes, 20))
        let pointsStored = Int(u32(bytes, 24)), pointsRaw = Int(u32(bytes, 28)), pairsStored = Int(u32(bytes, 32))
        let pointsCRC = u32(bytes, 36), pairsCRC = u32(bytes, 40)
        let (y, m, d) = (day / 10_000, day / 100 % 100, day % 100)
        let validFrom = String(format: "%04d-%02d-%02d", y, m, d)
        guard TariffFreshness.isISODay(validFrom) else { throw RelationPackError.corrupt("validFrom") }
        guard pointCount > 0, pointCount <= 0x10000, pairCount > 0, pairCount <= maxPairs else {
            throw RelationPackError.corrupt("counts")
        }
        guard pointsStored >= 0, pairsStored >= 0, pointsRaw > 0, pointsRaw <= maxPointsRawBytes,
              headerSize + pointsStored + pairsStored == data.count else { throw RelationPackError.sizeMismatch }

        let pointsBytes = try section(bytes, offset: headerSize, stored: pointsStored, raw: pointsRaw, crc: pointsCRC, name: "points")
        let pairsBytes = try section(bytes, offset: headerSize + pointsStored, stored: pairsStored, raw: pairCount * 6,
                                     crc: pairsCRC, name: "pairs")
        struct PointsBlock: Decodable {
            var source: String
            var points: [RelationPriceTable.File.Point]
        }
        guard let block = try? JSONDecoder().decode(PointsBlock.self, from: Data(pointsBytes)), block.points.count == pointCount else {
            throw RelationPackError.corrupt("points")
        }
        return RelationPack(version: version, validFrom: validFrom, source: block.source, points: block.points,
                            triples: Data(pairsBytes))
    }

    private static func section(_ bytes: [UInt8], offset: Int, stored: Int, raw: Int, crc: UInt32, name: String) throws -> [UInt8] {
        // DEFLATE cannot expand beyond ~1032:1; a larger claim is a corrupt header, not a reason to allocate.
        guard stored > 0, raw <= stored * 1032 + 1024 else { throw RelationPackError.corrupt(name) }
        let out: [UInt8]
        do {
            out = try bytes.withUnsafeBytes { buffer in
                try Inflate.decompress(UnsafeRawBufferPointer(rebasing: buffer[offset..<(offset + stored)]), expectedSize: raw)
            }
        } catch {
            throw RelationPackError.corrupt(name)
        }
        guard CRC32.checksum(out) == crc else { throw RelationPackError.corrupt(name) }
        return out
    }

    private static func u16(_ b: [UInt8], _ o: Int) -> UInt16 { UInt16(b[o]) | UInt16(b[o + 1]) << 8 }
    private static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }
}

/// Why a pack was not accepted. The app never shows these; it keeps the table it has (the diagnostics line names it).
public enum RelationPackError: Error, Equatable, Sendable {
    case tooLarge
    case truncated
    case badMagic
    case unsupportedFormat(Int)
    case sizeMismatch
    case hashMismatch
    case versionMismatch
    case validFromMismatch
    case corrupt(String)
    case pairCountOutlier(Int)
    case pairOrder
    case priceOutOfRange
    case priceOutlier
    case notNewer
    case notYetValid
}
