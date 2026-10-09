import Foundation

// CONTRACT (Step 0) – owned by WP-B after the contracts commit. WP-B additions: `PriceRequest.via`, `PriceAlternative.text`.

/// Where a regular fare came from. Raw values are persisted (TripEntity.priceSourceRaw, Supabase) – never rename.
public enum PriceSource: String, Codable, Sendable, CaseIterable, Hashable {
    /// ÖBB ticket shop, offer FLEX + all products ONEWAY (Standard-Ticket or Verbund single ticket sold by ÖBB).
    case liveOebb
    /// VAO trfRes.totalPrice – Verbund single ticket (adult, 2nd class).
    case liveVerbund
    /// Official ÖBB Relationspreise table (offline, × fare index).
    case table
    /// Kernzone single ticket from the tariff catalog.
    case cityTicket
    /// Distance model estimate.
    case distanceModel
    /// Entered by the user – never overwritten automatically.
    case manual

    public var isLive: Bool { self == .liveOebb || self == .liveVerbund }
}

/// Shop price tier by purchase lead time (matches the three columns of the official ÖBB fare tables).
public enum LeadTimeTier: String, Codable, Sendable, Hashable {
    /// Bought on the day of travel ("ST VP 000") – the valuation basis of KlimaBilanz.
    case travelDay
    /// 1–14 days ahead ("014-001", ≈ −1.9 %).
    case advanceShort
    /// 15+ days ahead ("180-015", ≈ −5.9 %).
    case advanceLong

    /// Vienna calendar days between purchase (`now`) and departure.
    public static func tier(departure: Date, now: Date, calendar: Calendar = .vienna) -> LeadTimeTier {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: departure)).day ?? 0
        if days <= 0 { return .travelDay }
        return days <= 14 ? .advanceShort : .advanceLong
    }
}

/// One end of a priced relation. Fill as much as is known; the price service resolves the rest.
public struct PriceEndpoint: Codable, Sendable, Hashable {
    /// App station id from stations.json ("at:47:1187", "uic:8100227", "wl:60201349", "osm:hub:…").
    public var stationID: String?
    public var name: String
    public var coordinate: GeoPoint?
    /// ÖBB HAFAS extId = shop station `number` (from the planner).
    public var hafasExtId: String?

    public init(stationID: String? = nil, name: String, coordinate: GeoPoint? = nil, hafasExtId: String? = nil) {
        self.stationID = stationID
        self.name = name
        self.coordinate = coordinate
        self.hafasExtId = hafasExtId
    }

    public init(station: Station) {
        self.init(stationID: station.id, name: station.name, coordinate: station.location,
                  hafasExtId: station.id.hasPrefix("uic:") ? String(station.id.dropFirst(4)) : nil)
    }
}

public struct PriceRequest: Codable, Sendable, Hashable {
    public var from: PriceEndpoint
    public var to: PriceEndpoint
    /// Departure (absolute). Only its Vienna calendar day matters for relation quotes.
    public var departure: Date
    public var mode: TransportMode
    public var travelClass: TravelClass
    public var discount: FareDiscount
    /// Set when the trip comes from the planner: the shop then prices exactly this connection (SPEC §B4.3).
    public var journey: Journey?
    /// Via stops in travel order ("Über", owner request 2026-10-09; at most `JourneyQuery.maxViaStops` are used).
    /// Empty = direct relation. See `LivePriceService` for how a via route is priced.
    public var via: [PriceEndpoint]

    public init(from: PriceEndpoint, to: PriceEndpoint, departure: Date, mode: TransportMode = .train,
                travelClass: TravelClass = .second, discount: FareDiscount = .none, journey: Journey? = nil,
                via: [PriceEndpoint] = []) {
        self.from = from
        self.to = to
        self.departure = departure
        self.mode = mode
        self.travelClass = travelClass
        self.discount = discount
        self.journey = journey
        self.via = via
    }

    private enum CodingKeys: String, CodingKey { case from, to, departure, mode, travelClass, discount, journey, via }

    /// Tolerant decoding: `via` is missing in requests encoded before 2026-10-09.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        from = try c.decode(PriceEndpoint.self, forKey: .from)
        to = try c.decode(PriceEndpoint.self, forKey: .to)
        departure = try c.decode(Date.self, forKey: .departure)
        mode = try c.decodeIfPresent(TransportMode.self, forKey: .mode) ?? .train
        travelClass = try c.decodeIfPresent(TravelClass.self, forKey: .travelClass) ?? .second
        discount = try c.decodeIfPresent(FareDiscount.self, forKey: .discount) ?? .none
        journey = try c.decodeIfPresent(Journey.self, forKey: .journey)
        via = try c.decodeIfPresent([PriceEndpoint].self, forKey: .via) ?? []
    }
}

public struct PriceAlternative: Codable, Sendable, Hashable {
    public var source: PriceSource
    public var amountEUR: Double
    /// German label ("Tarif-Tabelle", "VVT-Tarif", "Vorverkauf heute").
    public var label: String

    public init(source: PriceSource, amountEUR: Double, label: String) {
        self.source = source
        self.amountEUR = amountEUR
        self.label = label
    }

    /// Display line with the amount after the label and before a parenthesised note:
    /// "Vorverkauf heute € 66,40", "ÖBB-Ticketshop € 91,50 (andere Route)", "Tarif-Tabelle € 67,70".
    public var text: String {
        let amount = FareEstimator.euro(amountEUR)
        if let open = label.range(of: " (") {
            return "\(label[..<open.lowerBound]) \(amount)\(label[open.lowerBound...])"
        }
        return "\(label) \(amount)"
    }
}

/// A regular fare for ONE direction and ONE person (what the trip would have cost without the KlimaTicket).
public struct PriceQuote: Codable, Sendable, Hashable {
    public var amountEUR: Double
    public var source: PriceSource
    /// Ticket owner short name: "ÖBB", "VVT", "VOR", "OÖVV", "SVV", "VVV", "STV", "VKG" (nil offline).
    public var provider: String?
    /// "Standard-Ticket", "VVT Einzelticket", "VOR Einzelfahrt", "Einzelticket" …
    public var productName: String?
    public var travelClass: TravelClass
    public var discount: FareDiscount
    public var travelDate: Date
    /// When the live value was fetched (nil for offline sources).
    public var fetchedAt: Date?
    public var leadTime: LeadTimeTier?
    /// Opaque shop connection id when a specific connection was priced.
    public var connectionID: String?
    /// Purchase hand-off (never buy in-app).
    public var shopURL: URL?
    /// Distance of the relation in km when known (from the estimator / journey geometry).
    public var distanceKm: Double?
    /// Short German explanation ("Standard-Ticket 2. Kl. · ÖBB-Ticketshop · abgefragt 11:58").
    public var explanation: String
    /// Other prices found for transparency ("Tarif-Tabelle € 23,50").
    public var alternatives: [PriceAlternative]

    public init(amountEUR: Double, source: PriceSource, provider: String? = nil, productName: String? = nil,
                travelClass: TravelClass = .second, discount: FareDiscount = .none, travelDate: Date, fetchedAt: Date? = nil,
                leadTime: LeadTimeTier? = nil, connectionID: String? = nil, shopURL: URL? = nil, distanceKm: Double? = nil,
                explanation: String, alternatives: [PriceAlternative] = []) {
        self.amountEUR = amountEUR
        self.source = source
        self.provider = provider
        self.productName = productName
        self.travelClass = travelClass
        self.discount = discount
        self.travelDate = travelDate
        self.fetchedAt = fetchedAt
        self.leadTime = leadTime
        self.connectionID = connectionID
        self.shopURL = shopURL
        self.distanceKm = distanceKm
        self.explanation = explanation
        self.alternatives = alternatives
    }

    public var isLive: Bool { source.isLive }
}

/// Plugs live prices into `FareEstimator` (SPEC §B7). Throws `LiveError` whenever no live price is available;
/// `FareEstimator.estimateLive` then falls back to the offline chain (table → city ticket → distance model).
public protocol LivePriceProvider: Sendable {
    func livePrice(_ request: PriceRequest) async throws -> PriceQuote
}
