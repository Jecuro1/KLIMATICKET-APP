import Foundation
import SwiftData
import KlimaCore
import KlimaCloud

// MARK: data – version 3 of the JSON backup (docs/DATA_HUB.md §3): version 2 plus the allow-listed settings and a CRC-32 checksum.
// Writing, checking before a restore, the stamps for „Das ändert sich“, and the settings of this device. KlimaCore holds the rules
// (BackupChecksum, BackupInspection, BackupDiff, BackupSettingsPolicy); this file maps the app's rows onto them.

extension Backup {
    /// The full backup as a sealed version-3 file. Runs on any context (the share item and the automatic backup use a
    /// background one). `settings` is filtered again here, so nothing outside the allow-list can reach the file.
    nonisolated static func exportV3(context: ModelContext, settings: [String: BackupSettingValue]) throws -> Data {
        let tickets = try context.fetch(FetchDescriptor<TicketEntity>()).map { TicketDTO($0, userID: "") }
        let trips = try context.fetch(FetchDescriptor<TripEntity>()).map { BackupTripRow(entity: $0) }   // MARK: timebalance
        let favorites = try context.fetch(FetchDescriptor<FavoriteRouteEntity>()).map { FavoriteDTO($0, userID: "") }
        let benefits = try context.fetch(FetchDescriptor<BenefitEntity>()).map { BenefitDTO($0, userID: "") }
        var file = BackupFile(tickets: tickets, trips: trips, favorites: favorites, benefits: benefits,
                              settings: BackupSettingsPolicy.filter(settings).kept, checksum: BackupChecksum.placeholder)
        file.version = BackupFormat.currentVersion
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let sealed = BackupChecksum.seal(try encoder.encode(file)) else { throw CocoaError(.fileWriteUnknown) }
        return sealed
    }

    nonisolated static func decodeFile(_ data: Data) throws -> BackupFile {
        try BackupEnvelope.decoder().decode(BackupFile.self, from: data)
    }

    /// Restore with the checks of version 3: a damaged or foreign file is refused before a single row is read or written.
    /// Version-1 and version-2 files (no checksum) restore as before.
    static func restoreChecked(_ data: Data, context: ModelContext) throws -> ImportResult {
        let inspection = BackupInspection.inspect(data)
        if let problem = inspection.problem { throw DataHubRestoreError.refused(problem) }
        return try importBackup(data, context: context)
    }

    /// What the merge compares, per table, for the rows of a file.
    nonisolated static func stamps(of file: BackupFile) -> [BackupTable: [BackupRowStamp]] {
        [
            .tickets: file.tickets.map { BackupRowStamp(id: $0.id, updatedAt: $0.updated_at, isDeleted: $0.deleted_at != nil) },
            .trips: file.trips.map { BackupRowStamp(id: $0.base.id, updatedAt: $0.base.updated_at, isDeleted: $0.base.deleted_at != nil) },
            .favorites: file.favorites.map { BackupRowStamp(id: $0.id, updatedAt: $0.updated_at, isDeleted: $0.deleted_at != nil) },
            .benefits: (file.benefits ?? []).map { BackupRowStamp(id: $0.id, updatedAt: $0.updated_at, isDeleted: $0.deleted_at != nil) },
        ]
    }

    /// … and for the rows on this iPhone (tombstones included, like the merge sees them).
    nonisolated static func currentStamps(context: ModelContext) throws -> [BackupTable: [BackupRowStamp]] {
        [
            .tickets: try context.fetch(FetchDescriptor<TicketEntity>()).map { BackupRowStamp(id: $0.id, updatedAt: $0.updatedAt, isDeleted: $0.deletedAt != nil) },
            .trips: try context.fetch(FetchDescriptor<TripEntity>()).map { BackupRowStamp(id: $0.id, updatedAt: $0.updatedAt, isDeleted: $0.deletedAt != nil) },
            .favorites: try context.fetch(FetchDescriptor<FavoriteRouteEntity>()).map { BackupRowStamp(id: $0.id, updatedAt: $0.updatedAt, isDeleted: $0.deletedAt != nil) },
            .benefits: try context.fetch(FetchDescriptor<BenefitEntity>()).map { BackupRowStamp(id: $0.id, updatedAt: $0.updatedAt, isDeleted: $0.deletedAt != nil) },
        ]
    }

    /// The visible rows per table (tombstones left out) – the counts a backup row shows.
    nonisolated static func counts(of file: BackupFile) -> DataHubCounts {
        DataHubCounts(trips: file.trips.filter { $0.base.deleted_at == nil }.count,
                      tickets: file.tickets.filter { $0.deleted_at == nil }.count,
                      favorites: file.favorites.filter { $0.deleted_at == nil }.count,
                      benefits: (file.benefits ?? []).filter { $0.deleted_at == nil }.count)
    }

    nonisolated static func counts(context: ModelContext) -> DataHubCounts {
        DataHubCounts(trips: (try? context.fetchCount(FetchDescriptor<TripEntity>(predicate: #Predicate { $0.deletedAt == nil }))) ?? 0,
                      tickets: (try? context.fetchCount(FetchDescriptor<TicketEntity>(predicate: #Predicate { $0.deletedAt == nil }))) ?? 0,
                      favorites: (try? context.fetchCount(FetchDescriptor<FavoriteRouteEntity>(predicate: #Predicate { $0.deletedAt == nil }))) ?? 0,
                      benefits: (try? context.fetchCount(FetchDescriptor<BenefitEntity>(predicate: #Predicate { $0.deletedAt == nil }))) ?? 0)
    }
}

enum DataHubRestoreError: LocalizedError {
    case refused(BackupInspection.Problem)

    var errorDescription: String? {
        switch self {
        case .refused(let problem): problem.message
        }
    }
}

/// Visible rows per table.
struct DataHubCounts: Hashable, Sendable {
    var trips = 0
    var tickets = 0
    var favorites = 0
    var benefits = 0

    var isEmpty: Bool { trips + tickets + favorites + benefits == 0 }

    /// „123 Fahrten · 2 Tickets · 5 Favoriten“ (Vorteile only when there are some).
    var line: String {
        var parts = [DataHubFormat.count(trips, "Fahrt", "Fahrten"), DataHubFormat.count(tickets, "Ticket", "Tickets"),
                     DataHubFormat.count(favorites, "Favorit", "Favoriten")]
        if benefits > 0 { parts.append(DataHubFormat.count(benefits, "Vorteil", "Vorteile")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Settings

/// The settings a backup carries (BackupSettingsPolicy decides) and their way back: a restore stages them, and they are written
/// before the app state is built at the next launch – the stores read their keys once and would otherwise write over them.
enum BackupSettingsSnapshot {
    static let pendingKey = "backup.pendingSettings"

    /// Look & Feel lives in the App Group (the widgets read it); everything else in the app's own defaults.
    nonisolated static func isGroupKey(_ key: String) -> Bool { key.hasPrefix("theme.") }

    /// This device's allowed settings. Never in screenshot or perf runs (their settings are not the person's).
    nonisolated static func current() -> [String: BackupSettingValue] {
        guard !LaunchMode.isSandboxed else { return [:] }
        var values: [String: BackupSettingValue] = [:]
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where !isGroupKey(key) && BackupSettingsPolicy.allows(key) {
            if let setting = BackupSettingValue(plist: value) { values[key] = setting }
        }
        for (key, value) in AppGroup.defaults.dictionaryRepresentation() where isGroupKey(key) && BackupSettingsPolicy.allows(key) {
            if let setting = BackupSettingValue(plist: value) { values[key] = setting }
        }
        return BackupSettingsPolicy.filter(values).kept
    }

    /// The settings of a file that differ from this device's.
    nonisolated static func changes(in file: [String: BackupSettingValue]?) -> [String] {
        guard let file else { return [] }
        return BackupSettingsPolicy.changes(file: file, current: current())
    }

    static var hasPending: Bool { UserDefaults.standard.data(forKey: pendingKey) != nil }

    /// Keeps the file's settings for the next launch (allowed keys only, checked again when they are applied).
    static func stage(_ settings: [String: BackupSettingValue]) {
        guard !LaunchMode.isSandboxed, let data = try? JSONEncoder().encode(BackupSettingsPolicy.filter(settings).kept) else { return }
        UserDefaults.standard.set(data, forKey: pendingKey)
    }

    static func discardPending() {
        UserDefaults.standard.removeObject(forKey: pendingKey)
    }

    /// Called once per launch before AppState exists (KlimaBilanzApp, `// MARK: data`). Live-data consent, sign-in and
    /// anything outside the allow-list are never written, whatever the file says.
    static func applyPendingIfNeeded() {
        guard !LaunchMode.isSandboxed, let data = UserDefaults.standard.data(forKey: pendingKey) else { return }
        UserDefaults.standard.removeObject(forKey: pendingKey)
        guard let settings = try? JSONDecoder().decode([String: BackupSettingValue].self, from: data) else { return }
        for (key, value) in BackupSettingsPolicy.filter(settings).kept where BackupSettingsPolicy.allows(key) {
            (isGroupKey(key) ? AppGroup.defaults : UserDefaults.standard).set(value.plistValue, forKey: key)
        }
    }
}
