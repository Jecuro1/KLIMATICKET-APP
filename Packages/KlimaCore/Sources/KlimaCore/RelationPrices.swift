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
    /// key = (minIndex << 16) | maxIndex → cents
    private let cents: [Int: Int]

    public init(file: File) {
        validFrom = file.validFrom
        source = file.source
        var index: [String: Int] = [:]
        for (i, p) in file.points.enumerated() { index[p.stationID] = i }
        var map: [Int: Int] = [:]
        map.reserveCapacity(file.prices.count)
        for row in file.prices where row.count == 3 && row[0] < file.points.count && row[1] < file.points.count {
            map[RelationPriceTable.key(row[0], row[1])] = row[2]
        }
        pointIndex = index
        cents = map
    }

    public init(jsonData: Data) throws {
        self.init(file: try JSONDecoder().decode(File.self, from: jsonData))
    }

    /// Compact binary form: `triples` = little-endian UInt16 (pointA, pointB, price in 10-cent units), already decompressed.
    public init(validFrom: String, source: String, pointIDs: [String], triples: Data) {
        self.validFrom = validFrom
        self.source = source
        var index: [String: Int] = [:]
        for (i, id) in pointIDs.enumerated() { index[id] = i }
        var map: [Int: Int] = [:]
        let count = triples.count / 6
        map.reserveCapacity(count)
        triples.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for i in 0..<count {
                let o = i * 6
                let a = Int(UInt16(raw[o]) | UInt16(raw[o + 1]) << 8)
                let b = Int(UInt16(raw[o + 2]) | UInt16(raw[o + 3]) << 8)
                let v = Int(UInt16(raw[o + 4]) | UInt16(raw[o + 5]) << 8)
                guard a < pointIDs.count, b < pointIDs.count else { continue }
                map[RelationPriceTable.key(a, b)] = v * 10
            }
        }
        pointIndex = index
        cents = map
    }

    public static let empty = RelationPriceTable(file: File(validFrom: "", source: "", points: [], prices: []))

    public var count: Int { cents.count }

    /// Full 2nd-class price in EUR, or nil when the relation is not in the table.
    public func price(from a: String, to b: String) -> Double? {
        guard a != b, let i = pointIndex[a], let j = pointIndex[b], let c = cents[RelationPriceTable.key(i, j)] else { return nil }
        return Double(c) / 100
    }

    static func key(_ a: Int, _ b: Int) -> Int { a < b ? (a << 16) | b : (b << 16) | a }
}
