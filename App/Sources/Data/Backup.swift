import Foundation
import SwiftData
import KlimaCore

/// Full JSON backup (Einstellungen › Daten › Sichern/Wiederherstellen) – merge-import by id.
struct BackupFile: Codable {
    var format: String = "klimabilanz-backup"
    var version: Int = 1
    var exportedAt: Date = Date()
    var appVersion: String = AppConfig.appVersion
    var tickets: [TicketDTO]
    var trips: [TripDTO]
    var favorites: [FavoriteDTO]
}

@MainActor
enum Backup {
    static func export(context: ModelContext) throws -> Data {
        let tickets = try context.fetch(FetchDescriptor<TicketEntity>()).map { TicketDTO($0, userID: "") }
        let trips = try context.fetch(FetchDescriptor<TripEntity>()).map { TripDTO($0, userID: "") }
        let favorites = try context.fetch(FetchDescriptor<FavoriteRouteEntity>()).map { FavoriteDTO($0, userID: "") }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(BackupFile(tickets: tickets, trips: trips, favorites: favorites))
    }

    struct ImportResult {
        var tickets = 0
        var trips = 0
        var favorites = 0
        var summary: String { "\(trips) Fahrten, \(tickets) Tickets, \(favorites) Favoriten importiert" }
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
                if dto.updated_at > e.updatedAt { dto.apply(to: e); result.tickets += 1 }
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
                if dto.updated_at > e.updatedAt { dto.apply(to: e); result.trips += 1 }
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
                if dto.updated_at > e.updatedAt { dto.apply(to: e); result.favorites += 1 }
            } else {
                let e = FavoriteRouteEntity(fromName: dto.from_name, toName: dto.to_name, mode: .train, distanceKm: dto.distance_km, fareEUR: dto.fare_eur)
                e.id = dto.id
                dto.apply(to: e)
                context.insert(e)
                result.favorites += 1
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

    static func csv(context: ModelContext) throws -> Data {
        let trips = try context.fetch(FetchDescriptor<TripEntity>(predicate: #Predicate { $0.deletedAt == nil }))
        return Data(CSVExport.trips(trips.map(\.record)).utf8)
    }

    static var timestampedName: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "KlimaBilanz-\(f.string(from: Date()))"
    }
}
