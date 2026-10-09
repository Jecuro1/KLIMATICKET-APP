import Foundation

/// A synced row (contract §3.5). Property names are the wire/D1 column names. Encoding omits nil optionals, so a push
/// row has exactly the keys of `backend/test/fixtures/contract-rows.json` › push; `server_rev` is assigned by the
/// server and stripped before pushing.
public protocol SyncRow: Codable, Equatable, Sendable {
    static var table: String { get }
    var id: UUID { get }
    var user_id: String { get set }
    var updated_at: Date { get }
    var deleted_at: Date? { get }
    var server_rev: Int64? { get set }
}

public struct TicketDTO: SyncRow {
    public static let table = "tickets"

    public var id: UUID
    public var user_id: String
    public var product_id: String
    public var name: String
    public var variant: String
    public var family: String
    public var states: String
    public var price: Double
    public var start_date: Date
    public var end_date: Date
    public var holder_name: String
    public var ticket_number: String
    public var theme: String
    public var reminders: String
    public var is_monthly_payment: Bool?
    public var auto_renews: Bool?
    public var employer_contribution: Double?
    public var add_on_price: Double?
    public var add_ons: String?
    public var created_at: Date
    public var updated_at: Date
    public var deleted_at: Date?
    /// Assigned by the server; never sent.
    public var server_rev: Int64?

    public init(id: UUID, user_id: String, product_id: String, name: String, variant: String, family: String,
                states: String, price: Double, start_date: Date, end_date: Date, holder_name: String,
                ticket_number: String, theme: String, reminders: String, is_monthly_payment: Bool? = nil,
                auto_renews: Bool? = nil, employer_contribution: Double? = nil, add_on_price: Double? = nil,
                add_ons: String? = nil, created_at: Date, updated_at: Date, deleted_at: Date? = nil,
                server_rev: Int64? = nil) {
        self.id = id
        self.user_id = user_id
        self.product_id = product_id
        self.name = name
        self.variant = variant
        self.family = family
        self.states = states
        self.price = price
        self.start_date = start_date
        self.end_date = end_date
        self.holder_name = holder_name
        self.ticket_number = ticket_number
        self.theme = theme
        self.reminders = reminders
        self.is_monthly_payment = is_monthly_payment
        self.auto_renews = auto_renews
        self.employer_contribution = employer_contribution
        self.add_on_price = add_on_price
        self.add_ons = add_ons
        self.created_at = created_at
        self.updated_at = updated_at
        self.deleted_at = deleted_at
        self.server_rev = server_rev
    }
}

public struct TripDTO: SyncRow {
    public static let table = "trips"

    public var id: UUID
    public var user_id: String
    public var date: Date
    public var from_name: String
    public var to_name: String
    public var from_station_id: String?
    public var to_station_id: String?
    public var mode: String
    public var distance_km: Double
    public var fare_eur: Double
    public var is_fare_manual: Bool
    public var is_round_trip: Bool
    public var travel_class: String
    public var companions: Int
    public var states: String
    public var note: String
    public var category: String?
    public var is_induced: Bool?
    /// Via stops (`TripViaCodec` text, '' = direct; docs/VIA.md). Sent only to a server with the `trip_via` feature;
    /// nil = not sent / not known (the server then keeps what it has).
    public var via: String?
    /// "Reise mit Etappen" (docs/JOURNEYS.md): the journey this trip is a leg of (lowercase UUID, '' = none) and its place in
    /// travel order. Sent only to a server with the `trip_journey` feature; nil = not sent / not known (kept).
    public var journey_id: String?
    public var leg_index: Int?
    public var created_at: Date
    public var updated_at: Date
    public var deleted_at: Date?
    /// Assigned by the server; never sent.
    public var server_rev: Int64?

    public init(id: UUID, user_id: String, date: Date, from_name: String, to_name: String, from_station_id: String? = nil,
                to_station_id: String? = nil, mode: String, distance_km: Double, fare_eur: Double, is_fare_manual: Bool,
                is_round_trip: Bool, travel_class: String, companions: Int, states: String, note: String,
                category: String? = nil, is_induced: Bool? = nil, via: String? = nil, journey_id: String? = nil,
                leg_index: Int? = nil, created_at: Date, updated_at: Date, deleted_at: Date? = nil, server_rev: Int64? = nil) {
        self.id = id
        self.user_id = user_id
        self.date = date
        self.from_name = from_name
        self.to_name = to_name
        self.from_station_id = from_station_id
        self.to_station_id = to_station_id
        self.mode = mode
        self.distance_km = distance_km
        self.fare_eur = fare_eur
        self.is_fare_manual = is_fare_manual
        self.is_round_trip = is_round_trip
        self.travel_class = travel_class
        self.companions = companions
        self.states = states
        self.note = note
        self.category = category
        self.is_induced = is_induced
        self.via = via
        self.journey_id = journey_id
        self.leg_index = leg_index
        self.created_at = created_at
        self.updated_at = updated_at
        self.deleted_at = deleted_at
        self.server_rev = server_rev
    }
}

public struct FavoriteDTO: SyncRow {
    public static let table = "favorite_routes"

    public var id: UUID
    public var user_id: String
    public var title: String
    public var from_name: String
    public var to_name: String
    public var from_station_id: String?
    public var to_station_id: String?
    public var mode: String
    public var distance_km: Double
    public var fare_eur: Double
    public var is_round_trip: Bool
    public var states: String
    public var sort_index: Int
    public var usage_count: Int
    public var category: String?
    /// Via stops, as on `TripDTO.via`.
    public var via: String?
    /// "Kombi-Vorlage": the legs of a multi-leg favourite (`JourneyLegCodec` JSON, '' = one route; docs/JOURNEYS.md).
    /// Sent only to a server with the `trip_journey` feature; nil = not sent / not known (kept).
    public var legs: String?
    public var created_at: Date
    public var updated_at: Date
    public var deleted_at: Date?
    /// Assigned by the server; never sent.
    public var server_rev: Int64?

    public init(id: UUID, user_id: String, title: String, from_name: String, to_name: String, from_station_id: String? = nil,
                to_station_id: String? = nil, mode: String, distance_km: Double, fare_eur: Double, is_round_trip: Bool,
                states: String, sort_index: Int, usage_count: Int, category: String? = nil, via: String? = nil,
                legs: String? = nil, created_at: Date, updated_at: Date, deleted_at: Date? = nil, server_rev: Int64? = nil) {
        self.id = id
        self.user_id = user_id
        self.title = title
        self.from_name = from_name
        self.to_name = to_name
        self.from_station_id = from_station_id
        self.to_station_id = to_station_id
        self.mode = mode
        self.distance_km = distance_km
        self.fare_eur = fare_eur
        self.is_round_trip = is_round_trip
        self.states = states
        self.sort_index = sort_index
        self.usage_count = usage_count
        self.category = category
        self.via = via
        self.legs = legs
        self.created_at = created_at
        self.updated_at = updated_at
        self.deleted_at = deleted_at
        self.server_rev = server_rev
    }
}

public struct BenefitDTO: SyncRow {
    public static let table = "benefits"

    public var id: UUID
    public var user_id: String
    public var date: Date
    public var partner_id: String
    public var title: String
    public var saved_eur: Double
    public var note: String
    public var created_at: Date
    public var updated_at: Date
    public var deleted_at: Date?
    /// Assigned by the server; never sent.
    public var server_rev: Int64?

    public init(id: UUID, user_id: String, date: Date, partner_id: String, title: String, saved_eur: Double, note: String,
                created_at: Date, updated_at: Date, deleted_at: Date? = nil, server_rev: Int64? = nil) {
        self.id = id
        self.user_id = user_id
        self.date = date
        self.partner_id = partner_id
        self.title = title
        self.saved_eur = saved_eur
        self.note = note
        self.created_at = created_at
        self.updated_at = updated_at
        self.deleted_at = deleted_at
        self.server_rev = server_rev
    }
}

/// The four synced tables in sync order.
public enum SyncTables {
    public static let all = [TicketDTO.table, TripDTO.table, FavoriteDTO.table, BenefitDTO.table]
}
