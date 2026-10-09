import Foundation
import SwiftData
import KlimaCore
import KlimaCloud

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
    /// One fetch per table into an id index (not one fetch per row, which also re-scanned every pending insert:
    /// quadratic on the main thread). The index is updated on insert, so ids repeated within the file still merge.
    static func importBackup(_ data: Data, context: ModelContext) throws -> ImportResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(BackupFile.self, from: data)
        var result = ImportResult()
        result.tickets = try merge(file.tickets, context: context, id: \TicketEntity.id, updatedAt: \.updatedAt,
                                   apply: { $0.apply(to: $1) }, make: { $0.makeEntity() })
        result.trips = try merge(file.trips, context: context, id: \TripEntity.id, updatedAt: \.updatedAt,
                                 apply: { $0.apply(to: $1) }, make: { $0.makeEntity() })
        result.favorites = try merge(file.favorites, context: context, id: \FavoriteRouteEntity.id, updatedAt: \.updatedAt,
                                     apply: { $0.apply(to: $1) }, make: { $0.makeEntity() })
        try context.save()
        return result
    }

    /// Inserts rows with unknown ids and applies rows newer than the local entity. Returns the number of changed rows.
    private static func merge<Row: SyncRow, Entity: PersistentModel>(
        _ rows: [Row], context: ModelContext, id: KeyPath<Entity, UUID>, updatedAt: KeyPath<Entity, Date>,
        apply: (Row, Entity) -> Void, make: (Row) -> Entity
    ) throws -> Int {
        guard !rows.isEmpty else { return 0 }
        var byID: [UUID: Entity] = [:]
        for entity in try context.fetch(FetchDescriptor<Entity>()) where byID[entity[keyPath: id]] == nil {
            byID[entity[keyPath: id]] = entity
        }
        var changed = 0
        for row in rows {
            if let entity = byID[row.id] {
                if row.updated_at > entity[keyPath: updatedAt] {
                    apply(row, entity)
                    changed += 1
                }
            } else {
                let entity = make(row)
                context.insert(entity)
                byID[row.id] = entity
                changed += 1
            }
        }
        return changed
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
