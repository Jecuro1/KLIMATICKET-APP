import Foundation
import SwiftData
import KlimaCore

// MARK: data – Documents/Sicherungen (docs/DATA_HUB.md §4): the only folder of the app the Files app shows („Auf meinem iPhone ›
// KlimaBilanz › Sicherungen“, UIFileSharingEnabled). Listing, writing and pruning; all of it runs off the main thread.

/// One file in the folder, as its name and the file system describe it (the content is read only on demand).
struct DataHubBackupFile: Identifiable, Hashable, Sendable {
    var url: URL
    var name: String
    var date: Date
    var kind: BackupKind
    var size: Int
    /// A file the app did not name (copied in by the person): listed and shareable, never pruned.
    var isForeign: Bool

    var id: String { name }
}

/// What a backup holds – read when the list shows it, again after „Prüfen“.
struct DataHubBackupDetails: Equatable, Sendable {
    var counts: DataHubCounts
    var version: Int
    var exportedAt: Date?
    var appVersion: String?
    var settingsCount: Int
    var verdict: BackupChecksum.Verdict
    var problem: BackupInspection.Problem?

    var canRestore: Bool { problem == nil }
}

enum DataHubFolder {
    static let folderName = "Sicherungen"

    nonisolated static var url: URL { URL.documentsDirectory.appending(path: folderName, directoryHint: .isDirectory) }

    /// Newest first. Our own names sort by their date; a foreign `.json` by its modification date.
    nonisolated static func list(in folder: URL = url) -> [DataHubBackupFile] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        let urls = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        let files = urls.compactMap { url -> DataHubBackupFile? in
            guard url.pathExtension.lowercased() == "json",
                  let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return nil }
            let name = url.lastPathComponent
            let size = values.fileSize ?? 0
            if let parsed = BackupFileName.parse(name) {
                return DataHubBackupFile(url: url, name: name, date: parsed.date, kind: parsed.kind, size: size, isForeign: false)
            }
            return DataHubBackupFile(url: url, name: name, date: values.contentModificationDate ?? .distantPast, kind: .daily,
                                     size: size, isForeign: true)
        }
        return files.sorted { ($0.date, $0.name) > ($1.date, $1.name) }
    }

    /// Writes a backup atomically (a write cut short by the system never leaves a half file) and returns it.
    nonisolated static func write(_ data: Data, kind: BackupKind, now: Date = Date(), in folder: URL = url) throws -> DataHubBackupFile {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = BackupFileName.unique(BackupFileName.make(date: now, kind: kind)) {
            fm.fileExists(atPath: folder.appending(path: $0).path)
        }
        let target = folder.appending(path: name)
        // Readable after the first unlock, so the background write when the app goes away works with a locked screen too.
        try data.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return DataHubBackupFile(url: target, name: name, date: now, kind: kind, size: data.count, isForeign: false)
    }

    /// Applies BackupRetention to the app's own files; returns the deleted names.
    @discardableResult
    nonisolated static func prune(now: Date = Date(), in folder: URL = url) -> [String] {
        let own = list(in: folder).filter { !$0.isForeign }
        let plan = BackupRetention.plan(own.map { .init(id: $0.name, date: $0.date, kind: $0.kind) }, now: now)
        var deleted: [String] = []
        for name in plan.delete {
            if (try? FileManager.default.removeItem(at: folder.appending(path: name))) != nil { deleted.append(name) }
        }
        return deleted
    }

    /// Reads and checks one file: counts, version, settings and the checksum's verdict.
    nonisolated static func details(of url: URL) -> DataHubBackupDetails? {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return details(of: data)
    }

    nonisolated static func details(of data: Data) -> DataHubBackupDetails {
        let inspection = BackupInspection.inspect(data)
        let file = inspection.canRestore ? try? Backup.decodeFile(data) : nil
        return DataHubBackupDetails(counts: file.map(Backup.counts(of:)) ?? DataHubCounts(),
                                    version: inspection.envelope?.version ?? 0,
                                    exportedAt: inspection.envelope?.exportedAt,
                                    appVersion: inspection.envelope?.appVersion,
                                    settingsCount: inspection.envelope?.settings?.count ?? 0,
                                    verdict: inspection.verdict,
                                    problem: inspection.problem ?? (inspection.canRestore && file == nil ? .notABackup : nil))
    }

    /// The store-file copies of StoreLoader (before an update, after a failed open): listed read-only, shareable.
    nonisolated static func storeCopies() -> [DataHubStoreCopy] {
        let files = StoreFiles(storeURL: DataSchema.storeURL)
        return files.backups().prefix(12).map { folder in
            let parts = StoreFiles.files(in: folder)
            let size = parts.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            return DataHubStoreCopy(folder: folder, files: parts, kind: StoreFiles.kind(of: folder.lastPathComponent) ?? "",
                                    date: DataHubStoreCopy.date(of: folder.lastPathComponent), size: size)
        }
    }
}

/// A copy of the database files (StoreBackups/<date>-<kind>), made by the app itself before an update or when opening failed.
struct DataHubStoreCopy: Identifiable, Hashable, Sendable {
    var folder: URL
    var files: [URL]
    var kind: String
    var date: Date?
    var size: Int

    var id: String { folder.lastPathComponent }

    var title: String {
        switch kind {
        case "update": "Vor einem App-Update"
        case "fehler": "Als das Öffnen fehlschlug"
        case "ersetzt": "Vor „Neu beginnen“"
        default: "Datenbank-Kopie"
        }
    }

    /// „20261009-174512-update-b139“ → 9 Oct 2026 17:45:12 UTC.
    static func date(of folderName: String) -> Date? {
        let stamp = folderName.prefix(15)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.date(from: String(stamp))
    }
}
