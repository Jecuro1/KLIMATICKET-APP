import Foundation

/// Decides whether a downloaded (or stored) relation pack may replace the table in use. Every check must pass; one failure
/// and the app keeps the table it has – a wrong price table is worse than an old one.
///
/// Checks, in this order: size cap (8 MB) and exact size from the catalogue, SHA-256 from the catalogue, magic and format,
/// data version and validity day agree with the catalogue, sections inflate and match their CRC-32, relations are stored
/// once (A < B) in strictly ascending order (so symmetric, without duplicates), every price is a UInt16 in 10-cent units
/// (not zero, not the clamp value 65 535, not above € 3.000), the number of relations is within ±25 % of the table in use,
/// and the prices are in the same range as that table's (median ratio on up to 4 000 shared relations).
///
/// Foundation only: SHA-256 comes in as a function (CryptoKit in the app, a pure-Swift one in the Linux tests).
public struct RelationPackValidator: Sendable {
    public typealias Hasher = @Sendable (Data) -> String

    /// What the table in use looks like, for the plausibility checks.
    public struct Reference: Sendable {
        public var pairCount: Int
        public var table: RelationPriceTable?

        public init(pairCount: Int, table: RelationPriceTable? = nil) {
            self.pairCount = pairCount
            self.table = table
        }

        public init(table: RelationPriceTable) {
            self.init(pairCount: table.count, table: table)
        }
    }

    /// Allowed deviation of the relation count from the table in use.
    public static let pairCountTolerance = 0.25
    /// Highest accepted price in 10-cent units (€ 3.000); 65 535 is what the build script clamps to and never valid.
    public static let maxPriceUnits = 30_000
    /// Accepted range of the median price ratio (pack / table in use) – wide enough for a tariff increase, narrow enough
    /// to catch a wrong unit (cents instead of 10-cent units).
    public static let plausibleMedianRatio = 0.7...1.5
    private static let minSharedPairs = 200
    private static let maxSampledPairs = 4_000

    private let hasher: Hasher

    public init(hasher: @escaping Hasher) {
        self.hasher = hasher
    }

    /// Parses and checks `data` against what the catalogue promised. Throws the first failed check.
    public func validate(_ data: Data, expected: RelationsPackInfo, reference: Reference) throws -> RelationPack {
        guard expected.bytes > 0, expected.bytes <= RelationPack.maxBytes, data.count <= RelationPack.maxBytes else {
            throw RelationPackError.tooLarge
        }
        guard data.count == expected.bytes else { throw RelationPackError.sizeMismatch }
        guard hasher(data).lowercased() == expected.sha256.lowercased() else { throw RelationPackError.hashMismatch }
        let pack = try RelationPack.parse(data)
        guard pack.version == expected.version else { throw RelationPackError.versionMismatch }
        guard pack.validFrom == expected.validFrom else { throw RelationPackError.validFromMismatch }
        try checkContent(pack, reference: reference)
        return pack
    }

    func checkContent(_ pack: RelationPack, reference: Reference) throws {
        // Points: station IDs are the keys everywhere else, so each must be there and unique.
        var seen = Set<String>()
        for point in pack.points {
            guard !point.stationID.isEmpty, point.stationID.count <= 64, seen.insert(point.stationID).inserted else {
                throw RelationPackError.corrupt("points")
            }
        }

        // Pairs: A < B < pointCount, ascending by (A, B), price in 1…maxPriceUnits.
        let count = pack.pairCount
        guard pack.triples.count == count * 6 else { throw RelationPackError.sizeMismatch }
        let triples = [UInt8](pack.triples)
        var lastKey: Int64 = -1
        for i in 0..<count {
            let o = i * 6
            let a = Int(triples[o]) | Int(triples[o + 1]) << 8
            let b = Int(triples[o + 2]) | Int(triples[o + 3]) << 8
            let price = Int(triples[o + 4]) | Int(triples[o + 5]) << 8
            guard a < b, b < pack.points.count else { throw RelationPackError.pairOrder }
            let key = Int64(a) << 16 | Int64(b)
            guard key > lastKey else { throw RelationPackError.pairOrder }
            lastKey = key
            guard price >= 1, price <= Self.maxPriceUnits else { throw RelationPackError.priceOutOfRange }
        }

        // Size against the table in use.
        if reference.pairCount > 0 {
            guard abs(count - reference.pairCount) * 4 <= reference.pairCount else {
                throw RelationPackError.pairCountOutlier(count)
            }
        }

        // Price level against the table in use (on the relations both know).
        guard let table = reference.table else { return }
        var ratios: [Double] = []
        let step = max(1, count / Self.maxSampledPairs)
        var i = 0
        while i < count {
            let o = i * 6
            let a = Int(triples[o]) | Int(triples[o + 1]) << 8
            let b = Int(triples[o + 2]) | Int(triples[o + 3]) << 8
            let price = Double(Int(triples[o + 4]) | Int(triples[o + 5]) << 8) / 10
            if let known = table.price(from: pack.points[a].stationID, to: pack.points[b].stationID), known > 0 {
                ratios.append(price / known)
            }
            i += step
        }
        if ratios.count >= Self.minSharedPairs {
            let median = ratios.sorted()[ratios.count / 2]
            guard Self.plausibleMedianRatio.contains(median) else { throw RelationPackError.priceOutlier }
        }
    }
}
