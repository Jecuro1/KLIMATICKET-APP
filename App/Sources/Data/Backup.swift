import Foundation
import SwiftData
import KlimaCore
import KlimaCloud

/// Full JSON backup (Einstellungen › Daten › Sichern/Wiederherstellen) – merge-import by id.
///
/// Rows are the KlimaCloud sync DTOs (same column names as the server). Version 2 adds the benefits ("Vorteile") and
/// relies on the DTOs' phase-2 columns (trip category & "ohne Ticket nicht gefahren", favourite category, ticket
/// auto-renewal, employer contribution, add-ons). Version-1 files still restore: those columns are optional, and when a
/// file lacks them the values of an existing entity stay untouched (new entities keep the model defaults).
struct BackupFile: Codable {
    var format: String = "klimabilanz-backup"
    var version: Int = 2
    var exportedAt: Date = Date()
    var appVersion: String = AppConfig.appVersion
    var tickets: [TicketDTO]
    var trips: [TripDTO]
    var favorites: [FavoriteDTO]
    /// Absent in version-1 backups.
    var benefits: [BenefitDTO]?

    private enum CodingKeys: String, CodingKey {
        case format, version, exportedAt, appVersion, tickets, trips, favorites, benefits
    }

    init(tickets: [TicketDTO], trips: [TripDTO], favorites: [FavoriteDTO], benefits: [BenefitDTO]?) {
        self.tickets = tickets
        self.trips = trips
        self.favorites = favorites
        self.benefits = benefits
    }

    /// Tickets, trips and favourites must be readable; the benefits section is optional and tolerant
    /// (rows from early version-2 test builds carry no `user_id`).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? "klimabilanz-backup"
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        exportedAt = (try? c.decodeIfPresent(Date.self, forKey: .exportedAt)) ?? Date()
        appVersion = (try? c.decodeIfPresent(String.self, forKey: .appVersion)) ?? ""
        tickets = try c.decode([TicketDTO].self, forKey: .tickets)
        trips = try c.decode([TripDTO].self, forKey: .trips)
        favorites = try c.decode([FavoriteDTO].self, forKey: .favorites)
        benefits = try c.decodeIfPresent([BackupBenefitRow].self, forKey: .benefits)?.map(\.dto)
    }
}

/// Lenient reader for a benefit row: `user_id` and `note` may be missing.
private struct BackupBenefitRow: Decodable {
    var id: UUID
    var user_id: String?
    var date: Date
    var partner_id: String
    var title: String
    var saved_eur: Double
    var note: String?
    var created_at: Date
    var updated_at: Date
    var deleted_at: Date?

    var dto: BenefitDTO {
        BenefitDTO(id: id, user_id: user_id ?? "", date: date, partner_id: partner_id, title: title,
                   saved_eur: max(0, saved_eur), note: note ?? "", created_at: created_at, updated_at: updated_at,
                   deleted_at: deleted_at)
    }
}

@MainActor
enum Backup {
    static func export(context: ModelContext) throws -> Data {
        let tickets = try context.fetch(FetchDescriptor<TicketEntity>()).map { TicketDTO($0, userID: "") }
        let trips = try context.fetch(FetchDescriptor<TripEntity>()).map { TripDTO($0, userID: "") }
        let favorites = try context.fetch(FetchDescriptor<FavoriteRouteEntity>()).map { FavoriteDTO($0, userID: "") }
        let benefits = try context.fetch(FetchDescriptor<BenefitEntity>()).map { BenefitDTO($0, userID: "") }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(BackupFile(tickets: tickets, trips: trips, favorites: favorites, benefits: benefits))
    }

    struct ImportResult {
        var tickets = 0
        var trips = 0
        var favorites = 0
        var benefits = 0
        var summary: String {
            var text = "\(trips) Fahrten, \(tickets) Tickets, \(favorites) Favoriten"
            if benefits > 0 { text += ", \(benefits) Vorteile" }
            return text + " importiert"
        }
    }

    /// Imports a backup; existing rows are only overwritten when the backup row is newer.
    static func importBackup(_ data: Data, context: ModelContext) throws -> ImportResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(BackupFile.self, from: data)
        var result = ImportResult()
        for dto in file.tickets {
            let id = dto.id
            if let e = try context.fetch(FetchDescriptor<TicketEntity>(predicate: #Predicate { $0.id == id })).first {
                if dto.updated_at > e.updatedAt { dto.keepingLocalExtras(of: e).apply(to: e); result.tickets += 1 }
            } else {
                let e = TicketEntity(productID: dto.product_id, name: dto.name, variant: .klassik, family: .oe, price: dto.price, startDate: dto.start_date)
                e.id = dto.id
                dto.apply(to: e)
                context.insert(e)
                result.tickets += 1
            }
        }
        for dto in file.trips {
            let id = dto.id
            if let e = try context.fetch(FetchDescriptor<TripEntity>(predicate: #Predicate { $0.id == id })).first {
                if dto.updated_at > e.updatedAt { dto.keepingLocalExtras(of: e).apply(to: e); result.trips += 1 }
            } else {
                let e = TripEntity(date: dto.date, fromName: dto.from_name, toName: dto.to_name, mode: .train, distanceKm: dto.distance_km, fareEUR: dto.fare_eur)
                e.id = dto.id
                dto.apply(to: e)
                context.insert(e)
                result.trips += 1
            }
        }
        for dto in file.favorites {
            let id = dto.id
            if let e = try context.fetch(FetchDescriptor<FavoriteRouteEntity>(predicate: #Predicate { $0.id == id })).first {
                if dto.updated_at > e.updatedAt { dto.keepingLocalExtras(of: e).apply(to: e); result.favorites += 1 }
            } else {
                let e = FavoriteRouteEntity(fromName: dto.from_name, toName: dto.to_name, mode: .train, distanceKm: dto.distance_km, fareEUR: dto.fare_eur)
                e.id = dto.id
                dto.apply(to: e)
                context.insert(e)
                result.favorites += 1
            }
        }
        for dto in file.benefits ?? [] {
            let id = dto.id
            if let e = try context.fetch(FetchDescriptor<BenefitEntity>(predicate: #Predicate { $0.id == id })).first {
                if dto.updated_at > e.updatedAt { dto.apply(to: e); result.benefits += 1 }
            } else {
                let e = BenefitEntity(date: dto.date, partnerID: dto.partner_id, title: dto.title, savedEUR: dto.saved_eur)
                e.id = dto.id
                dto.apply(to: e)
                context.insert(e)
                result.benefits += 1
            }
        }
        try context.save()
        return result
    }

    /// Writes export data to a temporary file suitable for ShareLink / fileExporter.
    static func temporaryFile(named name: String, data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: name)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// CSV v2 (Excel AT): incl. category, "ohne Ticket nicht gefahren" and notes – re-importable via CSV-Import.
    static func csv(context: ModelContext) throws -> Data {
        let trips = try context.fetch(FetchDescriptor<TripEntity>(predicate: #Predicate { $0.deletedAt == nil }))
        var notes: [UUID: String] = [:]
        for trip in trips where !trip.note.isEmpty { notes[trip.id] = trip.note }
        return Data(TripCSVExport.trips(trips.map(\.record), notes: notes).utf8)
    }

    static var timestampedName: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "KlimaBilanz-\(f.string(from: Date()))"
    }
}

// MARK: - Version-1 files: keep what the file does not know

/// A version-1 backup has no phase-2 columns (nil after decoding). Restoring such a row over an existing entity must not
/// reset category, "ohne Ticket nicht gefahren", auto-renewal, employer contribution or add-ons to their defaults.
private extension TicketDTO {
    func keepingLocalExtras(of e: TicketEntity) -> TicketDTO {
        var dto = self
        if dto.is_monthly_payment == nil { dto.is_monthly_payment = e.isMonthlyPayment }
        if dto.auto_renews == nil { dto.auto_renews = e.autoRenews }
        if dto.employer_contribution == nil { dto.employer_contribution = e.employerContribution }
        if dto.add_on_price == nil { dto.add_on_price = e.addOnPrice }
        if dto.add_ons == nil { dto.add_ons = e.addOnsRaw }
        return dto
    }
}

private extension TripDTO {
    func keepingLocalExtras(of e: TripEntity) -> TripDTO {
        var dto = self
        if dto.category == nil { dto.category = e.categoryRaw }
        if dto.is_induced == nil { dto.is_induced = e.isInduced }
        return dto
    }
}

private extension FavoriteDTO {
    func keepingLocalExtras(of e: FavoriteRouteEntity) -> FavoriteDTO {
        var dto = self
        if dto.category == nil { dto.category = e.categoryRaw }
        return dto
    }
}
