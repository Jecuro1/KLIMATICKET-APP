import Foundation

/// Exact ÖBB Standard-Ticket prices (2nd class, online, day of travel) between tariff points, from the official
/// "Relationspreise" tables. Keys are bundled station IDs (see stations.json); prices are assumed symmetric.
public struct RelationPriceTable: Sendable {
    public struct File: Codable, Sendable {
        public struct Point: Codable, Sendable {
            public var name: String
            public var stationID: String
        }

        public var validFrom: String
        public var source: String
        public var points: [Point]
        /// [originIndex, destinationIndex, priceInCents]
        public var prices: [[Int]]
    }

    /// Metadata file accompanying the binary table (relations-points.json).
    public struct PointsFile: Codable, Sendable {
        public var validFrom: String
        public var source: String
        public var points: [File.Point]
    }

    public let validFrom: String
    public let source: String
    private let pointIndex: [String: Int]
    /// Relation keys `(minIndex << 16) | maxIndex`, ascending and unique, and the price in cents at the same index.
    /// Two flat arrays searched by bisection: no ~4 MB hash table to build at launch for 178.000 relations.
    private let keys: [UInt32]
    private let cents: [Int32]

    public init(file: File) {
        validFrom = file.validFrom
        source = file.source
        var index: [String: Int] = [:]
        for (i, p) in file.points.enumerated() { index[p.stationID] = i }
        var rows: [(key: UInt32, cents: Int32)] = []
        rows.reserveCapacity(file.prices.count)
        for row in file.prices where row.count == 3 && row[0] < file.points.count && row[1] < file.points.count
            && row[0] >= 0 && row[1] >= 0 && row[0] <= 0xFFFF && row[1] <= 0xFFFF {
            rows.append((UInt32(RelationPriceTable.key(row[0], row[1])), Int32(clamping: row[2])))
        }
        pointIndex = index
        (keys, cents) = RelationPriceTable.sortedUnique(rows)
    }

    public init(jsonData: Data) throws {
        self.init(file: try JSONDecoder().decode(File.self, from: jsonData))
    }

    /// Compact binary form: `triples` = little-endian UInt16 (pointA, pointB, price in 10-cent units), already
    /// decompressed. The bundled table is written sorted by relation key, so this is a single linear pass.
    public init(validFrom: String, source: String, pointIDs: [String], triples: Data) {
        self.validFrom = validFrom
        self.source = source
        var index: [String: Int] = [:]
        for (i, id) in pointIDs.enumerated() { index[id] = i }
        let count = triples.count / 6
        var keys: [UInt32] = []
        var cents: [Int32] = []
        keys.reserveCapacity(count)
        cents.reserveCapacity(count)
        var ordered = true
        triples.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for i in 0..<count {
                let o = i * 6
                let a = Int(UInt16(raw[o]) | UInt16(raw[o + 1]) << 8)
                let b = Int(UInt16(raw[o + 2]) | UInt16(raw[o + 3]) << 8)
                let v = Int32(UInt16(raw[o + 4]) | UInt16(raw[o + 5]) << 8)
                guard a < pointIDs.count, b < pointIDs.count else { continue }
                let k = UInt32(RelationPriceTable.key(a, b))
                if let last = keys.last, k <= last { ordered = false }
                keys.append(k)
                cents.append(v * 10)
            }
        }
        pointIndex = index
        if ordered {
            self.keys = keys
            self.cents = cents
        } else {
            (self.keys, self.cents) = RelationPriceTable.sortedUnique(zip(keys, cents).map { (key: $0, cents: $1) })
        }
    }

    public static let empty = RelationPriceTable(file: File(validFrom: "", source: "", points: [], prices: []))

    public var count: Int { keys.count }

    /// Full 2nd-class price in EUR, or nil when the relation is not in the table.
    public func price(from a: String, to b: String) -> Double? {
        guard a != b, let i = pointIndex[a], let j = pointIndex[b] else { return nil }
        let k = UInt32(RelationPriceTable.key(i, j))
        var lo = 0, hi = keys.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if keys[mid] < k { lo = mid + 1 } else { hi = mid }
        }
        guard lo < keys.count, keys[lo] == k else { return nil }
        return Double(cents[lo]) / 100
    }

    /// Sorted by key; for a key listed twice the later row wins (as it did in the former dictionary).
    private static func sortedUnique(_ rows: [(key: UInt32, cents: Int32)]) -> ([UInt32], [Int32]) {
        let sorted = rows.enumerated().sorted { ($0.element.key, $0.offset) < ($1.element.key, $1.offset) }
        var keys: [UInt32] = [], cents: [Int32] = []
        keys.reserveCapacity(sorted.count)
        cents.reserveCapacity(sorted.count)
        for (_, row) in sorted {
            if let last = keys.last, last == row.key {
                cents[cents.count - 1] = row.cents
            } else {
                keys.append(row.key)
                cents.append(row.cents)
            }
        }
        return (keys, cents)
    }

    static func key(_ a: Int, _ b: Int) -> Int { a < b ? (a << 16) | b : (b << 16) | a }
}
