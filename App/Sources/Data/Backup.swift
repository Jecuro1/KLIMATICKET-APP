import Foundation
import SwiftData
import KlimaCore

/// Full JSON backup (Einstellungen › Daten › Sichern/Wiederherstellen) – merge-import by id.
///
/// Version 2 adds the phase-2 fields (trip category & "ohne Ticket nicht gefahren", favourite category, ticket auto-renewal,
/// employer contribution, add-ons) and the benefits ("Vorteile"). Version-1 files still restore: every new key is optional
/// and missing values leave the existing entity untouched (new entities keep their model defaults).
struct BackupFile: Codable {
    var format: String = "klimabilanz-backup"
    var version: Int = 2
    var exportedAt: Date = Date()
    var appVersion: String = AppConfig.appVersion
    var tickets: [RepBackupTicket]
    var trips: [RepBackupTrip]
    var favorites: [RepBackupFavorite]
    /// Absent in version-1 backups.
    var benefits: [RepBackupBenefit]?
}

@MainActor
enum Backup {
    static func export(context: ModelContext) throws -> Data {
        let tickets = try context.fetch(FetchDescriptor<TicketEntity>()).map { RepBackupTicket($0) }
        let trips = try context.fetch(FetchDescriptor<TripEntity>()).map { RepBackupTrip($0) }
        let favorites = try context.fetch(FetchDescriptor<FavoriteRouteEntity>()).map { RepBackupFavorite($0) }
        let benefits = try context.fetch(FetchDescriptor<BenefitEntity>()).map { RepBackupBenefit($0) }
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
        for row in file.tickets {
            let dto = row.base
            let id = dto.id
            if let e = try context.fetch(FetchDescriptor<TicketEntity>(predicate: #Predicate { $0.id == id })).first {
                if dto.updated_at > e.updatedAt { row.apply(to: e); result.tickets += 1 }
            } else {
                let e = TicketEntity(productID: dto.product_id, name: dto.name, variant: .klassik, family: .oe, price: dto.price, startDate: dto.start_date)
                e.id = dto.id
                row.apply(to: e)
                context.insert(e)
                result.tickets += 1
            }
        }
        for row in file.trips {
            let dto = row.base
            let id = dto.id
            if let e = try context.fetch(FetchDescriptor<TripEntity>(predicate: #Predicate { $0.id == id })).first {
                if dto.updated_at > e.updatedAt { row.apply(to: e); result.trips += 1 }
            } else {
                let e = TripEntity(date: dto.date, fromName: dto.from_name, toName: dto.to_name, mode: .train, distanceKm: dto.distance_km, fareEUR: dto.fare_eur)
                e.id = dto.id
                row.apply(to: e)
                context.insert(e)
                result.trips += 1
            }
        }
        for row in file.favorites {
            let dto = row.base
            let id = dto.id
            if let e = try context.fetch(FetchDescriptor<FavoriteRouteEntity>(predicate: #Predicate { $0.id == id })).first {
                if dto.updated_at > e.updatedAt { row.apply(to: e); result.favorites += 1 }
            } else {
                let e = FavoriteRouteEntity(fromName: dto.from_name, toName: dto.to_name, mode: .train, distanceKm: dto.distance_km, fareEUR: dto.fare_eur)
                e.id = dto.id
                row.apply(to: e)
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

// MARK: - Backup rows (sync DTO + phase-2 fields, flattened into one JSON object)

/// Ticket row: all `TicketDTO` columns plus auto-renewal, employer contribution and add-ons.
struct RepBackupTicket: Codable {
    var base: TicketDTO
    var auto_renews: Bool?
    var employer_contribution: Double?
    var add_on_price: Double?
    var add_ons: String?

    private enum ExtraKeys: String, CodingKey { case auto_renews, employer_contribution, add_on_price, add_ons }

    init(_ e: TicketEntity) {
        base = TicketDTO(e, userID: "")
        auto_renews = e.autoRenews
        employer_contribution = e.employerContribution
        add_on_price = e.addOnPrice
        add_ons = e.addOnsRaw
    }

    init(from decoder: Decoder) throws {
        base = try TicketDTO(from: decoder)
        let c = try decoder.container(keyedBy: ExtraKeys.self)
        auto_renews = try c.decodeIfPresent(Bool.self, forKey: .auto_renews)
        employer_contribution = try c.decodeIfPresent(Double.self, forKey: .employer_contribution)
        add_on_price = try c.decodeIfPresent(Double.self, forKey: .add_on_price)
        add_ons = try c.decodeIfPresent(String.self, forKey: .add_ons)
    }

    func encode(to encoder: Encoder) throws {
        try base.encode(to: encoder)
        var c = encoder.container(keyedBy: ExtraKeys.self)
        try c.encodeIfPresent(auto_renews, forKey: .auto_renews)
        try c.encodeIfPresent(employer_contribution, forKey: .employer_contribution)
        try c.encodeIfPresent(add_on_price, forKey: .add_on_price)
        try c.encodeIfPresent(add_ons, forKey: .add_ons)
    }

    func apply(to e: TicketEntity) {
        base.apply(to: e)
        if let auto_renews { e.autoRenews = auto_renews }
        if let employer_contribution { e.employerContribution = max(0, employer_contribution) }
        if let add_on_price { e.addOnPrice = max(0, add_on_price) }
        if let add_ons { e.addOnsRaw = add_ons }
    }
}

/// Trip row: all `TripDTO` columns plus category and "ohne Ticket nicht gefahren".
struct RepBackupTrip: Codable {
    var base: TripDTO
    var category: String?
    var is_induced: Bool?

    private enum ExtraKeys: String, CodingKey { case category, is_induced }

    init(_ e: TripEntity) {
        base = TripDTO(e, userID: "")
        category = e.categoryRaw
        is_induced = e.isInduced
    }

    init(from decoder: Decoder) throws {
        base = try TripDTO(from: decoder)
        let c = try decoder.container(keyedBy: ExtraKeys.self)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        is_induced = try c.decodeIfPresent(Bool.self, forKey: .is_induced)
    }

    func encode(to encoder: Encoder) throws {
        try base.encode(to: encoder)
        var c = encoder.container(keyedBy: ExtraKeys.self)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(is_induced, forKey: .is_induced)
    }

    func apply(to e: TripEntity) {
        base.apply(to: e)
        if let category { e.categoryRaw = TripCategory(rawValue: category) == nil ? "" : category }
        if let is_induced { e.isInduced = is_induced }
    }
}

/// Favourite row: all `FavoriteDTO` columns plus the category applied to trips logged from it.
struct RepBackupFavorite: Codable {
    var base: FavoriteDTO
    var category: String?

    private enum ExtraKeys: String, CodingKey { case category }

    init(_ e: FavoriteRouteEntity) {
        base = FavoriteDTO(e, userID: "")
        category = e.categoryRaw
    }

    init(from decoder: Decoder) throws {
        base = try FavoriteDTO(from: decoder)
        let c = try decoder.container(keyedBy: ExtraKeys.self)
        category = try c.decodeIfPresent(String.self, forKey: .category)
    }

    func encode(to encoder: Encoder) throws {
        try base.encode(to: encoder)
        var c = encoder.container(keyedBy: ExtraKeys.self)
        try c.encodeIfPresent(category, forKey: .category)
    }

    func apply(to e: FavoriteRouteEntity) {
        base.apply(to: e)
        if let category { e.categoryRaw = TripCategory(rawValue: category) == nil ? "" : category }
    }
}

/// A used KlimaTicket benefit ("Vorteilswelt"), new in backup version 2.
struct RepBackupBenefit: Codable {
    var id: UUID
    var date: Date
    var partner_id: String
    var title: String
    var saved_eur: Double
    var note: String?
    var created_at: Date
    var updated_at: Date
    var deleted_at: Date?

    init(_ e: BenefitEntity) {
        id = e.id; date = e.date; partner_id = e.partnerID; title = e.title; saved_eur = e.savedEUR; note = e.note
        created_at = e.createdAt; updated_at = e.updatedAt; deleted_at = e.deletedAt
    }

    func apply(to e: BenefitEntity) {
        e.date = date; e.partnerID = partner_id; e.title = title; e.savedEUR = max(0, saved_eur); e.note = note ?? ""
        e.createdAt = created_at; e.updatedAt = updated_at; e.deletedAt = deleted_at
    }
}
