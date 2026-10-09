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

    public let validFrom: String
    public let source: String
    private let cents: [String: Int]

    public init(file: File) {
        validFrom = file.validFrom
        source = file.source
        var map: [String: Int] = [:]
        map.reserveCapacity(file.prices.count)
        for row in file.prices where row.count == 3 && row[0] < file.points.count && row[1] < file.points.count {
            let a = file.points[row[0]].stationID, b = file.points[row[1]].stationID
            map[RelationPriceTable.key(a, b)] = row[2]
        }
        cents = map
    }

    public init(jsonData: Data) throws {
        self.init(file: try JSONDecoder().decode(File.self, from: jsonData))
    }

    public static let empty = RelationPriceTable(file: File(validFrom: "", source: "", points: [], prices: []))

    public var count: Int { cents.count }

    /// Full 2nd-class price in EUR, or nil when the relation is not in the table.
    public func price(from a: String, to b: String) -> Double? {
        guard a != b, let c = cents[RelationPriceTable.key(a, b)] else { return nil }
        return Double(c) / 100
    }

    static func key(_ a: String, _ b: String) -> String { a < b ? "\(a)|\(b)" : "\(b)|\(a)" }
}
