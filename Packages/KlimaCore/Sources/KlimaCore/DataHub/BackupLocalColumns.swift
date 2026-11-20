import Foundation

// MARK: review-daten – the columns a row has only on this iPhone (docs/DATA_HUB.md §3.1). The sync rows a backup is made of do not
// carry them: where a fare came from („Live-Preis ÖBB · Sparschiene“), the planner's journey reference, the trip's lines
// („Railjet Xpress“, which the Verspätungs-Nachweis prints) and the weekday pattern of a saved route („Meine Routen“). Without them
// a „Komplettsicherung“ restored into an empty store lost all of that. They travel in one optional top-level block `local`, so a
// version-2 or early version-3 reader ignores it, and a file without it leaves these columns of this iPhone as they are.

/// A trip's local columns. Empty strings and nil are „none“; only rows with something are written (the block stays small).
public struct TripLocalColumns: Codable, Hashable, Sendable {
    /// `PriceSource` raw value ("" = not recorded).
    public var priceSource: String
    public var priceProvider: String
    public var priceProduct: String
    public var priceFetchedAt: Date?
    public var journeyRef: String
    public var lineSummary: String

    enum CodingKeys: String, CodingKey {
        case priceSource = "price_source"
        case priceProvider = "price_provider"
        case priceProduct = "price_product"
        case priceFetchedAt = "price_fetched_at"
        case journeyRef = "journey_ref"
        case lineSummary = "line_summary"
    }

    public static let empty = TripLocalColumns()

    public init(priceSource: String = "", priceProvider: String = "", priceProduct: String = "", priceFetchedAt: Date? = nil,
                journeyRef: String = "", lineSummary: String = "") {
        self.priceSource = priceSource
        self.priceProvider = priceProvider
        self.priceProduct = priceProduct
        self.priceFetchedAt = priceFetchedAt
        self.journeyRef = journeyRef
        self.lineSummary = lineSummary
    }

    /// Tolerant: a key that is missing or does not decode is „none“ – one odd value never blocks a restore.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(priceSource: (try? c.decodeIfPresent(String.self, forKey: .priceSource)) ?? "",
                  priceProvider: (try? c.decodeIfPresent(String.self, forKey: .priceProvider)) ?? "",
                  priceProduct: (try? c.decodeIfPresent(String.self, forKey: .priceProduct)) ?? "",
                  priceFetchedAt: try? c.decodeIfPresent(Date.self, forKey: .priceFetchedAt),
                  journeyRef: (try? c.decodeIfPresent(String.self, forKey: .journeyRef)) ?? "",
                  lineSummary: (try? c.decodeIfPresent(String.self, forKey: .lineSummary)) ?? "")
    }

    /// Only what is set.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !priceSource.isEmpty { try c.encode(priceSource, forKey: .priceSource) }
        if !priceProvider.isEmpty { try c.encode(priceProvider, forKey: .priceProvider) }
        if !priceProduct.isEmpty { try c.encode(priceProduct, forKey: .priceProduct) }
        try c.encodeIfPresent(priceFetchedAt, forKey: .priceFetchedAt)
        if !journeyRef.isEmpty { try c.encode(journeyRef, forKey: .journeyRef) }
        if !lineSummary.isEmpty { try c.encode(lineSummary, forKey: .lineSummary) }
    }

    public var isEmpty: Bool { self == .empty }
}

/// A saved route's local column: the „Meine Routen“ pattern (`RouteSchedule.raw`, "" = none).
public struct FavoriteLocalColumns: Codable, Hashable, Sendable {
    public var schedule: String

    public static let empty = FavoriteLocalColumns()

    public init(schedule: String = "") {
        self.schedule = schedule
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schedule = (try? c.decodeIfPresent(String.self, forKey: .schedule)) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !schedule.isEmpty { try c.encode(schedule, forKey: .schedule) }
    }

    private enum CodingKeys: String, CodingKey { case schedule }

    public var isEmpty: Bool { schedule.isEmpty }
}

/// The block `local` of a backup: per row id (lower-case UUID), the local columns that are set.
///
/// The rule on restore: when the file has the block, a row the merge takes from the file (new, or newer than here) gets exactly the
/// file's local columns – none when the block has no entry for it, like every other column of that row. Without the block (an older
/// file, or a block that does not decode) the merge leaves this iPhone's local columns alone.
public struct BackupLocalBlock: Codable, Hashable, Sendable {
    public var trips: [String: TripLocalColumns]
    public var favorites: [String: FavoriteLocalColumns]

    public init(trips: [String: TripLocalColumns] = [:], favorites: [String: FavoriteLocalColumns] = [:]) {
        self.trips = trips.filter { !$0.value.isEmpty }
        self.favorites = favorites.filter { !$0.value.isEmpty }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(trips: (try? c.decodeIfPresent([String: TripLocalColumns].self, forKey: .trips)) ?? [:],
                  favorites: (try? c.decodeIfPresent([String: FavoriteLocalColumns].self, forKey: .favorites)) ?? [:])
    }

    private enum CodingKeys: String, CodingKey { case trips, favorites }

    public static func key(_ id: UUID) -> String { id.uuidString.lowercased() }

    /// What a trip taken from the file gets.
    public func trip(_ id: UUID) -> TripLocalColumns { trips[Self.key(id)] ?? .empty }

    /// What a saved route taken from the file gets.
    public func favorite(_ id: UUID) -> FavoriteLocalColumns { favorites[Self.key(id)] ?? .empty }

    /// Builds the block from (id, columns) pairs; empty columns are left out.
    public static func make(trips: [(UUID, TripLocalColumns)], favorites: [(UUID, FavoriteLocalColumns)]) -> BackupLocalBlock {
        BackupLocalBlock(trips: Dictionary(trips.map { (key($0.0), $0.1) }, uniquingKeysWith: { _, last in last }),
                         favorites: Dictionary(favorites.map { (key($0.0), $0.1) }, uniquingKeysWith: { _, last in last }))
    }
}
