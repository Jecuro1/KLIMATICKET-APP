import Foundation
import SwiftData
import KlimaCore

/// Two-way cloud sync (Supabase/PostgREST) with last-writer-wins on `updated_at` and soft deletes.
@Observable
@MainActor
final class SyncService {
    enum State: Equatable {
        case disabled
        case idle
        case syncing
        case synced(Date)
        case failed(String)
    }

    private(set) var state: State
    private let client: SupabaseClient?
    private let defaults = UserDefaults.standard

    init(config: AppConfig) {
        if let url = config.supabase {
            client = SupabaseClient(baseURL: url, anonKey: config.supabaseAnonKey)
            state = .idle
        } else {
            client = nil
            state = .disabled
        }
    }

    var lastSync: Date? { defaults.object(forKey: "sync.lastSync") as? Date }

    func sync(context: ModelContext, auth: AuthService) async {
        guard let client else { state = .disabled; return }
        guard state != .syncing else { return }
        guard let session = await auth.validSession() else { state = .idle; return }
        state = .syncing
        let since = lastSync ?? .distantPast
        let started = Date()
        do {
            // Push local changes.
            let tickets = try context.fetch(FetchDescriptor<TicketEntity>(predicate: #Predicate { $0.updatedAt > since }))
            let trips = try context.fetch(FetchDescriptor<TripEntity>(predicate: #Predicate { $0.updatedAt > since }))
            let favorites = try context.fetch(FetchDescriptor<FavoriteRouteEntity>(predicate: #Predicate { $0.updatedAt > since }))
            let uid = session.user.id
            try await client.upsert("tickets", rows: tickets.map { TicketDTO($0, userID: uid) }, session: session)
            try await client.upsert("trips", rows: trips.map { TripDTO($0, userID: uid) }, session: session)
            try await client.upsert("favorite_routes", rows: favorites.map { FavoriteDTO($0, userID: uid) }, session: session)

            // Pull remote changes.
            let filter = [URLQueryItem(name: "select", value: "*"),
                          URLQueryItem(name: "updated_at", value: "gt.\(ISO8601DateFormatter().string(from: since))")]
            let remoteTickets: [TicketDTO] = try await client.select("tickets", query: filter, session: session)
            let remoteTrips: [TripDTO] = try await client.select("trips", query: filter, session: session)
            let remoteFavorites: [FavoriteDTO] = try await client.select("favorite_routes", query: filter, session: session)
            try merge(remoteTickets, remoteTrips, remoteFavorites, into: context)
            try context.save()
            defaults.set(started, forKey: "sync.lastSync")
            state = .synced(Date())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func resetSyncCursor() { defaults.removeObject(forKey: "sync.lastSync") }

    private func merge(_ tickets: [TicketDTO], _ trips: [TripDTO], _ favorites: [FavoriteDTO], into context: ModelContext) throws {
        for dto in tickets {
            let id = dto.id
            let existing = try context.fetch(FetchDescriptor<TicketEntity>(predicate: #Predicate { $0.id == id })).first
            if let e = existing {
                if dto.updated_at > e.updatedAt { dto.apply(to: e) }
            } else {
                let e = TicketEntity(productID: dto.product_id, name: dto.name, variant: .klassik, family: .oe, price: dto.price, startDate: dto.start_date)
                e.id = dto.id
                dto.apply(to: e)
                context.insert(e)
            }
        }
        for dto in trips {
            let id = dto.id
            let existing = try context.fetch(FetchDescriptor<TripEntity>(predicate: #Predicate { $0.id == id })).first
            if let e = existing {
                if dto.updated_at > e.updatedAt { dto.apply(to: e) }
            } else {
                let e = TripEntity(date: dto.date, fromName: dto.from_name, toName: dto.to_name, mode: .train, distanceKm: dto.distance_km, fareEUR: dto.fare_eur)
                e.id = dto.id
                dto.apply(to: e)
                context.insert(e)
            }
        }
        for dto in favorites {
            let id = dto.id
            let existing = try context.fetch(FetchDescriptor<FavoriteRouteEntity>(predicate: #Predicate { $0.id == id })).first
            if let e = existing {
                if dto.updated_at > e.updatedAt { dto.apply(to: e) }
            } else {
                let e = FavoriteRouteEntity(fromName: dto.from_name, toName: dto.to_name, mode: .train, distanceKm: dto.distance_km, fareEUR: dto.fare_eur)
                e.id = dto.id
                dto.apply(to: e)
                context.insert(e)
            }
        }
    }
}

// MARK: - DTOs (snake_case = Postgres columns, see supabase/migrations)

struct TicketDTO: Codable {
    var id: UUID
    var user_id: String
    var product_id: String
    var name: String
    var variant: String
    var family: String
    var states: String
    var price: Double
    var start_date: Date
    var end_date: Date
    var holder_name: String
    var ticket_number: String
    var theme: String
    var reminders: String
    var is_monthly_payment: Bool?
    var created_at: Date
    var updated_at: Date
    var deleted_at: Date?

    init(_ e: TicketEntity, userID: String) {
        id = e.id; user_id = userID; product_id = e.productID; name = e.name; variant = e.variantRaw; family = e.familyRaw
        states = e.statesRaw; price = e.price; start_date = e.startDate; end_date = e.endDate; holder_name = e.holderName
        ticket_number = e.ticketNumber; theme = e.themeRaw; reminders = e.remindersRaw; is_monthly_payment = e.isMonthlyPayment
        created_at = e.createdAt
        updated_at = e.updatedAt; deleted_at = e.deletedAt
    }

    func apply(to e: TicketEntity) {
        e.productID = product_id; e.name = name; e.variantRaw = variant; e.familyRaw = family; e.statesRaw = states
        e.price = price; e.startDate = start_date; e.endDate = end_date; e.holderName = holder_name; e.ticketNumber = ticket_number
        e.themeRaw = theme; e.remindersRaw = reminders; e.isMonthlyPayment = is_monthly_payment ?? false
        e.createdAt = created_at; e.updatedAt = updated_at; e.deletedAt = deleted_at
    }
}

struct TripDTO: Codable {
    var id: UUID
    var user_id: String
    var date: Date
    var from_name: String
    var to_name: String
    var from_station_id: String?
    var to_station_id: String?
    var mode: String
    var distance_km: Double
    var fare_eur: Double
    var is_fare_manual: Bool
    var is_round_trip: Bool
    var travel_class: String
    var companions: Int
    var states: String
    var note: String
    var created_at: Date
    var updated_at: Date
    var deleted_at: Date?

    init(_ e: TripEntity, userID: String) {
        id = e.id; user_id = userID; date = e.date; from_name = e.fromName; to_name = e.toName
        from_station_id = e.fromStationID; to_station_id = e.toStationID; mode = e.modeRaw; distance_km = e.distanceKm
        fare_eur = e.fareEUR; is_fare_manual = e.isFareManual; is_round_trip = e.isRoundTrip; travel_class = e.travelClassRaw
        companions = e.companions; states = e.statesRaw; note = e.note; created_at = e.createdAt; updated_at = e.updatedAt
        deleted_at = e.deletedAt
    }

    func apply(to e: TripEntity) {
        e.date = date; e.fromName = from_name; e.toName = to_name; e.fromStationID = from_station_id; e.toStationID = to_station_id
        e.modeRaw = mode; e.distanceKm = distance_km; e.fareEUR = fare_eur; e.isFareManual = is_fare_manual
        e.isRoundTrip = is_round_trip; e.travelClassRaw = travel_class; e.companions = companions; e.statesRaw = states
        e.note = note; e.createdAt = created_at; e.updatedAt = updated_at; e.deletedAt = deleted_at
    }
}

struct FavoriteDTO: Codable {
    var id: UUID
    var user_id: String
    var title: String
    var from_name: String
    var to_name: String
    var from_station_id: String?
    var to_station_id: String?
    var mode: String
    var distance_km: Double
    var fare_eur: Double
    var is_round_trip: Bool
    var states: String
    var sort_index: Int
    var usage_count: Int
    var created_at: Date
    var updated_at: Date
    var deleted_at: Date?

    init(_ e: FavoriteRouteEntity, userID: String) {
        id = e.id; user_id = userID; title = e.title; from_name = e.fromName; to_name = e.toName
        from_station_id = e.fromStationID; to_station_id = e.toStationID; mode = e.modeRaw; distance_km = e.distanceKm
        fare_eur = e.fareEUR; is_round_trip = e.isRoundTrip; states = e.statesRaw; sort_index = e.sortIndex
        usage_count = e.usageCount; created_at = e.createdAt; updated_at = e.updatedAt; deleted_at = e.deletedAt
    }

    func apply(to e: FavoriteRouteEntity) {
        e.title = title; e.fromName = from_name; e.toName = to_name; e.fromStationID = from_station_id; e.toStationID = to_station_id
        e.modeRaw = mode; e.distanceKm = distance_km; e.fareEUR = fare_eur; e.isRoundTrip = is_round_trip; e.statesRaw = states
        e.sortIndex = sort_index; e.usageCount = usage_count; e.createdAt = created_at; e.updatedAt = updated_at; e.deletedAt = deleted_at
    }
}
