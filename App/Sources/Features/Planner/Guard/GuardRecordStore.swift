import Foundation
import KlimaCore

// MARK: anschluss – where the Anschluss-Wächter keeps its one record (docs/CONNECTION_GUARD.md §7): `Guard/record.json` in
// Application Support, excluded from backups and readable after the first unlock (a background refresh of the follow can
// restore it while the iPhone is locked). It is your itinerary to the final destination, so it is not in UserDefaults (part of
// the iPhone backup), not in the app's export and not synced. Demo and screenshot launches never read or write it.

enum GuardRecordStore {
    static let folder = "Guard"
    static let fileName = "record.json"

    /// Off in demo (`-KBDemo`), screenshot and performance launches.
    static var isEnabled: Bool { !LaunchMode.isSandboxed && !LaunchMode.useDemoData }

    /// The folder (reading never creates it).
    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: folder, directoryHint: .isDirectory)
    }

    static var url: URL { directory.appending(path: fileName) }

    /// The saved record; nil when there is none, it is unreadable, of another version, or the store is off.
    static func load() -> GuardRecord? {
        guard isEnabled, let data = try? Data(contentsOf: url) else { return nil }
        return GuardRecord.decode(data)
    }

    /// `nil` removes the file.
    static func save(_ record: GuardRecord?) {
        guard isEnabled else { return }
        guard let record, let data = record.encoded() else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        ensureDirectory()
        var target = url
        try? data.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
    }

    /// Creates the folder on the first write: excluded from backups, readable after the first unlock.
    private static func ensureDirectory() {
        let base = directory
        guard !FileManager.default.fileExists(atPath: base.path) else { return }
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var folderURL = base
        try? folderURL.setResourceValues(values)
    }
}
