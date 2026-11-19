import Foundation
import SwiftData
import UIKit
import OSLog
import KlimaCore

// MARK: data – „Tägliche Sicherung“ and the safety backups (docs/DATA_HUB.md §4). When the app goes to the background, at most once
// per Vienna day and only when tickets, trips, favourites, benefits or the allowed settings changed since the last backup, a version-3
// file goes to Documents/Sicherungen; then BackupRetention prunes. Before „Alle Daten löschen“, replacing the data with an account's
// and every restore, a safety backup is written that retention keeps for 30 days. Nothing leaves the iPhone.

@Observable
@MainActor
final class AutoBackupService {
    static let shared = AutoBackupService()

    private static let enabledKey = "backup.auto"
    private static let stampKey = "backup.lastCommitStamp"
    private static let lastDayKey = "backup.lastBackupDay"
    nonisolated private static let log = Logger(subsystem: "com.knitelarlberg.klimabilanz", category: "backup")

    /// „Tägliche Sicherung“ – on unless switched off.
    var isEnabled: Bool {
        didSet {
            guard !LaunchMode.isSandboxed else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
        }
    }

    /// The folder's files, newest first (refreshed by `refresh()` and after every write).
    private(set) var files: [DataHubBackupFile] = []
    private(set) var isWriting = false
    /// The demo's files (screenshot runs): the list shows them instead of the folder.
    @ObservationIgnored private var demoFiles: [DataHubBackupFile]?

    private init() {
        isEnabled = LaunchMode.isSandboxed ? true : (UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true)
    }

    var newest: DataHubBackupFile? { files.first }

    func refresh() async {
        if let demoFiles { files = demoFiles; return }
        files = await Task.detached(priority: .utility) { DataHubFolder.list() }.value
    }

    /// CI scenes: fixed files, nothing on disk is read or written.
    func installDemo(_ files: [DataHubBackupFile]) {
        demoFiles = files
        self.files = files
    }

    // MARK: Daily

    /// RootView, scene phase `.background` (`// MARK: data`). Cheap when nothing is due: one day check, then a stamp of counts
    /// and change dates. The write runs in a background task that iOS gives a few seconds; an atomic write is either whole or absent.
    func runIfDue(container: ModelContainer, now: Date = Date()) {
        guard isEnabled, !LaunchMode.isSandboxed, demoFiles == nil, !isWriting else { return }
        let today = Self.dayKey(now)
        guard UserDefaults.standard.string(forKey: Self.lastDayKey) != today else { return }
        let lastStamp = UserDefaults.standard.string(forKey: Self.stampKey)
        isWriting = true
        let backgroundTask = DataHubBackgroundTask(name: "KlimaBilanz-Sicherung")
        Task {
            let outcome = await Task.detached(priority: .utility) { () -> (file: DataHubBackupFile?, stamp: String?) in
                let context = ModelContext(container)
                guard let stamp = Self.changeStamp(context: context), stamp != lastStamp else { return (nil, nil) }
                do {
                    let data = try Backup.export(context: context)
                    let file = try DataHubFolder.write(data, kind: .daily, now: now)
                    DataHubFolder.prune(now: now)
                    return (file, stamp)
                } catch {
                    Self.log.error("daily backup failed: \(String(describing: error), privacy: .public)")
                    return (nil, nil)
                }
            }.value
            if outcome.file != nil, let stamp = outcome.stamp {
                UserDefaults.standard.set(stamp, forKey: Self.stampKey)
                UserDefaults.standard.set(today, forKey: Self.lastDayKey)
            }
            isWriting = false
            await refresh()
            backgroundTask.end()
        }
    }

    /// „Jetzt sichern“: a backup right away, whatever the day and the stamp say. Counts as today's daily backup.
    @discardableResult
    func backupNow(container: ModelContainer, now: Date = Date()) async throws -> DataHubBackupFile {
        isWriting = true
        defer { isWriting = false }
        let file = try await Task.detached(priority: .userInitiated) { () throws -> (DataHubBackupFile, String?) in
            let context = ModelContext(container)
            let data = try Backup.export(context: context)
            let file = try DataHubFolder.write(data, kind: .daily, now: now)
            DataHubFolder.prune(now: now)
            return (file, Self.changeStamp(context: context))
        }.value
        if !LaunchMode.isSandboxed {
            if let stamp = file.1 { UserDefaults.standard.set(stamp, forKey: Self.stampKey) }
            UserDefaults.standard.set(Self.dayKey(now), forKey: Self.lastDayKey)
        }
        await refresh()
        return file.0
    }

    // MARK: Safety

    enum SafetyOutcome: Equatable {
        case written(String)
        /// Nothing to keep (no ticket, no trip): the destructive step may go on.
        case nothingToKeep
        case failed(String)

        /// Whether the step after it may run: only when the copy exists or there was nothing to copy.
        var allowsDestructiveStep: Bool {
            if case .failed = self { return false }
            return true
        }
    }

    /// A „vor dem Löschen“ / „vor dem Wiederherstellen“ backup. In screenshot and perf runs nothing is written.
    func safetyBackup(_ kind: BackupKind, container: ModelContainer, now: Date = Date()) async -> SafetyOutcome {
        guard !LaunchMode.isSandboxed else { return .nothingToKeep }
        isWriting = true
        defer { isWriting = false }
        let outcome = await Task.detached(priority: .userInitiated) { () -> SafetyOutcome in
            let context = ModelContext(container)
            guard !Backup.counts(context: context).isEmpty else { return .nothingToKeep }
            do {
                let data = try Backup.export(context: context)
                return .written(try DataHubFolder.write(data, kind: kind, now: now).name)
            } catch {
                Self.log.error("safety backup failed: \(String(describing: error), privacy: .public)")
                return .failed(StoreFiles.describe(error))
            }
        }.value
        await refresh()
        return outcome
    }

    // MARK: Stamp

    /// Counts, newest change and deletion per table plus the CRC-32 of the allowed settings. Equal stamps: nothing to back up.
    /// nil when the store is empty (no ticket, no trip) – an empty store gets no daily backup.
    nonisolated static func changeStamp(context: ModelContext) -> String? {
        func part<T: PersistentModel>(_ type: T.Type, _ updated: KeyPath<T, Date>, _ label: String) -> (String, Int) {
            let count = (try? context.fetchCount(FetchDescriptor<T>())) ?? 0
            var newest = FetchDescriptor<T>(sortBy: [SortDescriptor(updated, order: .reverse)])
            newest.fetchLimit = 1
            let latest = (try? context.fetch(newest))?.first?[keyPath: updated].timeIntervalSince1970 ?? 0
            return ("\(label)\(count)@\(Int(latest * 1000))", count)
        }
        let tickets = part(TicketEntity.self, \TicketEntity.updatedAt, "k")
        let trips = part(TripEntity.self, \TripEntity.updatedAt, "t")
        let favorites = part(FavoriteRouteEntity.self, \FavoriteRouteEntity.updatedAt, "f")
        let benefits = part(BenefitEntity.self, \BenefitEntity.updatedAt, "b")
        guard tickets.1 + trips.1 > 0 else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let settings = (try? encoder.encode(BackupSettingsSnapshot.current())) ?? Data()
        return [tickets.0, trips.0, favorites.0, benefits.0, "s" + DataHubCRC32.hex(DataHubCRC32.checksum(settings))].joined(separator: "|")
    }

    /// „2026-11-19“ in Vienna.
    nonisolated static func dayKey(_ date: Date) -> String {
        let c = Calendar.vienna.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// The few seconds iOS grants after the app went to the background, ended as soon as the write is done (or when iOS says time is up).
@MainActor
final class DataHubBackgroundTask {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
