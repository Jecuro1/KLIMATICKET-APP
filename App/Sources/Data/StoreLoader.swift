import Foundation
import SwiftData
import UIKit
import OSLog

/// Opens the SwiftData store and keeps the app away from it until it really is open.
///
/// There is deliberately no in-memory fallback: the app would show onboarding / "Noch kein Ticket" and silently drop
/// everything entered (quick logs drained from the widget queue, a confirmed trip suggestion, a re-created ticket).
/// Instead:
/// • Before the first unlock after a restart (region-monitoring relaunch, notification action, prewarming) the store
///   file is still encrypted. The loader waits and retries on `protectedDataDidBecomeAvailable`, when the scene becomes
///   active and when the recovery screen appears.
/// • When opening fails although the data is readable (failed migration, corrupt file, disk full), the store files are
///   copied into `StoreBackups/` next to the store and the recovery screen explains what happened. "Neu beginnen" moves
///   the unreadable store aside (kept, never deleted) and creates an empty one.
/// • Before a new app build opens the store for the first time (a migration may run), a copy is kept as well.
@Observable
@MainActor
final class StoreLoader {
    enum Phase: Equatable {
        /// Not open yet: the launch attempt failed before the UI existed; decided on the next retry.
        case opening
        /// The iPhone has not been unlocked since it restarted – the data is still encrypted.
        case waitingForUnlock
        case ready
        case failed(Failure)
    }

    struct Failure: Equatable {
        var kind: Kind
        /// Technical detail for support ("NSCocoaErrorDomain 134110 …").
        var detail: String
        /// Copy of the store taken when opening failed; nil when there was nothing to copy or copying failed.
        var backup: URL?
        /// The files in `backup` (for "Sicherungskopie teilen").
        var backupFiles: [URL]

        enum Kind: Equatable { case diskFull, unreadable }
    }

    enum OpenEvent: Equatable {
        /// Opened at launch, as usual.
        case launch
        /// Opened on a retry (after the first unlock, or from the recovery screen).
        case recovered
        /// "Neu beginnen": a new, empty store replaced the unreadable one.
        case startedFresh
    }

    private(set) var phase: Phase = .opening
    private(set) var container: ModelContainer?

    /// Called on the main actor once the store is open.
    @ObservationIgnored var onOpen: ((ModelContainer, OpenEvent) -> Void)?

    private let files: StoreFiles?
    @ObservationIgnored private var unlockObserver: NSObjectProtocol?
    @ObservationIgnored private var failureBackup: URL?
    private let isPreview: Bool

    static let log = Logger(subsystem: "com.knitelarlberg.klimabilanz", category: "store")
    private static let lastOpenedBuildKey = "store.lastOpenedBuild"

    init(storeURL: URL = DataSchema.storeURL) {
        files = StoreFiles(storeURL: storeURL)
        isPreview = false
    }

    /// An already open container (CI screenshots: in-memory demo data).
    init(container: ModelContainer) {
        files = nil
        isPreview = false
        self.container = container
        phase = .ready
    }

    /// CI screenshots of the recovery screen: a fixed phase, retries and actions do nothing.
    init(previewPhase: Phase) {
        files = nil
        isPreview = true
        phase = previewPhase
    }

    /// First attempt, from `App.init`. `UIApplication.shared` may not exist yet (prewarming), so a failure is not
    /// classified here – the recovery screen's retry does that once the UI exists.
    func start() {
        if let container {
            onOpen?(container, .launch)
            return
        }
        guard !isPreview else { return }
        observeUnlock()
        backupBeforeNewBuildIfNeeded()
        do {
            try open(.launch)
        } catch {
            Self.log.error("store open at launch failed: \(String(describing: error), privacy: .public)")
            phase = .opening
        }
    }

    /// Retries while the store is not open – after the first unlock, when the scene becomes active, when the recovery
    /// screen appears. A failure that is not about locked data is only retried explicitly (`retry()`).
    func retryIfNeeded() {
        guard container == nil, !isPreview else { return }
        if case .failed = phase { return }
        attempt()
    }

    /// "Erneut versuchen".
    func retry() {
        guard container == nil, !isPreview else { return }
        attempt()
    }

    /// "Neu beginnen": moves the unreadable store aside (into `StoreBackups/`, never deleted) and creates an empty one.
    func startFresh() throws {
        guard container == nil, !isPreview, let files else { return }
        let aside = files.items().isEmpty ? nil : try files.moveAside(kind: "ersetzt")
        do {
            try open(.startedFresh)
        } catch {
            // Not even an empty store opens (e.g. no space left): put the old one back where it was.
            if let aside {
                do { try files.restore(from: aside) } catch {
                    Self.log.error("store restore failed, old store kept in \(aside.lastPathComponent, privacy: .public)")
                }
            }
            fail(with: error)
            throw error
        }
        if let aside { Self.log.notice("started with an empty store, old one kept in \(aside.lastPathComponent, privacy: .public)") }
    }

    // MARK: Private

    private func attempt() {
        guard UIApplication.shared.isProtectedDataAvailable else {
            phase = .waitingForUnlock
            return
        }
        do {
            try open(.recovered)
        } catch {
            fail(with: error)
        }
    }

    private func open(_ event: OpenEvent) throws {
        let container = try DataSchema.openPersistentContainer()
        self.container = container
        phase = .ready
        UserDefaults.standard.set(Self.currentBuild, forKey: Self.lastOpenedBuildKey)
        if let unlockObserver {
            NotificationCenter.default.removeObserver(unlockObserver)
            self.unlockObserver = nil
        }
        if event != .launch { Self.log.notice("store opened (\(String(describing: event), privacy: .public))") }
        onOpen?(container, event)
    }

    /// Opening failed although the data is readable: keep a copy (once per launch) and show the recovery screen.
    private func fail(with error: Error) {
        Self.log.fault("store cannot be opened: \(String(describing: error), privacy: .public)")
        if failureBackup == nil, let files, files.exists {
            do {
                failureBackup = try files.backup(kind: "fehler")
            } catch {
                Self.log.error("store backup failed: \(String(describing: error), privacy: .public)")
            }
        }
        let backup = failureBackup
        phase = .failed(Failure(kind: StoreFiles.isDiskFull(error) ? .diskFull : .unreadable,
                                detail: StoreFiles.describe(error),
                                backup: backup,
                                backupFiles: backup.map(StoreFiles.files(in:)) ?? []))
    }

    private func observeUnlock() {
        guard unlockObserver == nil else { return }
        unlockObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.retryIfNeeded() }
        }
    }

    /// A new build may migrate the store on its first open: keep the previous state (APFS clone, practically free).
    private func backupBeforeNewBuildIfNeeded() {
        guard let files, files.exists else { return }
        let last = UserDefaults.standard.string(forKey: Self.lastOpenedBuildKey)
        guard last != Self.currentBuild else { return }
        // `last == nil` also happens before the first unlock (defaults unreadable) – copying fails then, harmlessly.
        do {
            try files.backup(kind: "update", detail: "b\(Self.currentBuild)", keep: 2)
        } catch {
            Self.log.notice("pre-update store backup skipped: \(String(describing: error), privacy: .public)")
        }
    }

    private static var currentBuild: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"
    }
}

/// The files that make up the SwiftData store (SQLite file, `-wal`/`-shm`, external-storage folder) and the dated
/// copies in `StoreBackups/` next to it.
struct StoreFiles {
    let storeURL: URL

    var directory: URL { storeURL.deletingLastPathComponent() }
    var backupsDirectory: URL { directory.appending(path: "StoreBackups", directoryHint: .isDirectory) }
    /// SwiftData's folder for `.externalStorage` attributes (ticket photos): ".KlimaBilanz_SUPPORT".
    var supportFolderName: String { "." + storeURL.deletingPathExtension().lastPathComponent + "_SUPPORT" }

    var exists: Bool { FileManager.default.fileExists(atPath: storeURL.path) }

    /// Store items currently next to the store file.
    func items() -> [URL] {
        let base = storeURL.lastPathComponent
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasPrefix(base) || $0 == supportFolderName }.sorted().map { directory.appending(path: $0) }
    }

    /// Copies the store into `StoreBackups/<date>-<kind>[-<detail>]/`. Keeps the newest `keep` copies of this kind.
    /// `kind` and `detail` must not contain "-".
    @discardableResult
    func backup(kind: String, detail: String? = nil, keep: Int = 3, now: Date = Date()) throws -> URL {
        let fm = FileManager.default
        let sources = items()
        guard !sources.isEmpty else { throw CocoaError(.fileNoSuchFile) }
        let folder = try makeFolder(kind: kind, detail: detail, now: now)
        do {
            for source in sources {
                try fm.copyItem(at: source, to: folder.appending(path: source.lastPathComponent))
            }
        } catch {
            try? fm.removeItem(at: folder)   // never leave a partial copy that looks complete
            throw error
        }
        prune(kind: kind, keep: keep)
        return folder
    }

    /// Moves the store into `StoreBackups/<date>-<kind>/` so a new store can be created at the same place.
    /// Nothing is deleted; use a kind that `backup` never prunes.
    /// All or nothing: when one item cannot be moved, the ones already moved are put back.
    @discardableResult
    func moveAside(kind: String, now: Date = Date()) throws -> URL {
        let fm = FileManager.default
        let folder = try makeFolder(kind: kind, detail: nil, now: now)
        var moved: [URL] = []
        do {
            for source in items() {
                try fm.moveItem(at: source, to: folder.appending(path: source.lastPathComponent))
                moved.append(source)
            }
        } catch {
            for source in moved { try? fm.moveItem(at: folder.appending(path: source.lastPathComponent), to: source) }
            if (try? fm.contentsOfDirectory(atPath: folder.path))?.isEmpty ?? false { try? fm.removeItem(at: folder) }
            throw error
        }
        return folder
    }

    /// Undoes `moveAside`: removes what was created at the store's place since, then moves the old store back.
    /// When that fails the old store simply stays in `folder`.
    func restore(from folder: URL) throws {
        let fm = FileManager.default
        for item in items() { try fm.removeItem(at: item) }
        for name in (try fm.contentsOfDirectory(atPath: folder.path)).sorted() {
            try fm.moveItem(at: folder.appending(path: name), to: directory.appending(path: name))
        }
        try? fm.removeItem(at: folder)
    }

    /// The regular files of a backup folder (the SQLite files; the photo folder is left out of sharing).
    static func files(in folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.sorted().map { folder.appending(path: $0) }.filter { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }
    }

    /// Backup folders, newest first.
    func backups() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: backupsDirectory.path)) ?? []
        return names.sorted(by: >).map { backupsDirectory.appending(path: $0, directoryHint: .isDirectory) }
    }

    private func makeFolder(kind: String, detail: String?, now: Date) throws -> URL {
        let name = "\(Self.stampFormatter.string(from: now))-\(kind)" + (detail.map { "-\($0)" } ?? "")
        var folder = backupsDirectory.appending(path: name, directoryHint: .isDirectory)
        var counter = 2
        while FileManager.default.fileExists(atPath: folder.path) {
            folder = backupsDirectory.appending(path: "\(name)~\(counter)", directoryHint: .isDirectory)
            counter += 1
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func prune(kind: String, keep: Int) {
        let matching = backups().filter { Self.kind(of: $0.lastPathComponent) == kind }
        for old in matching.dropFirst(max(1, keep)) { try? FileManager.default.removeItem(at: old) }
    }

    /// "20261009-174512-update-b139~2" → "update".
    static func kind(of folderName: String) -> String? {
        let parts = folderName.split(separator: "~").first?.split(separator: "-") ?? []
        return parts.count >= 3 ? String(parts[2]) : nil
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    // MARK: Errors

    /// SQLite or the file system ran out of space anywhere in the underlying error chain.
    static func isDiskFull(_ error: Error) -> Bool {
        errorChain(error).contains { e in
            (e.domain == NSCocoaErrorDomain && e.code == NSFileWriteOutOfSpaceError)
                || (e.domain == NSPOSIXErrorDomain && e.code == Int(ENOSPC))
                || (e.domain == sqliteErrorDomain && e.code == 13)                          // SQLITE_FULL
                || (e.userInfo[sqliteErrorDomain] as? NSNumber)?.intValue == 13            // Core Data's wrapping
        }
    }

    static func describe(_ error: Error) -> String {
        errorChain(error).map { "\($0.domain) \($0.code)" }.joined(separator: " → ")
    }

    private static let sqliteErrorDomain = "NSSQLiteErrorDomain"

    private static func errorChain(_ error: Error) -> [NSError] {
        var chain: [NSError] = []
        var current: NSError? = error as NSError
        while let e = current, chain.count < 6 {
            chain.append(e)
            current = e.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return chain
    }
}
