import Foundation
import KlimaCore

// MARK: radar2-radarmine – where „Meine Fahrzeuge“ keeps what it must keep (docs/RADAR_MINE.md §6): one small JSON file `RadarMine/mine.json` in
// Application Support (not the App Group: no widget reads it), excluded from the iPhone backup, readable after the first unlock only – the pattern of
// `DetectionFiles`. Not UserDefaults: those are part of the backup, and the last five stops say where you wait. Per device: not in the app's export,
// backup or sync. Screenshot and perf launches never read or write it (an in-memory store), so a scene never shows what a person remembered.

@MainActor
final class RadarMineStore {
    static let shared = RadarMineStore(inMemory: LaunchMode.isSandboxed)

    private static let folder = "RadarMine"
    static let fileName = "mine.json"

    private let inMemory: Bool
    private var memory = RadarMineFile.empty

    init(inMemory: Bool) {
        self.inMemory = inMemory
    }

    private static var directory: URL {
        URL.applicationSupportDirectory.appending(path: folder, directoryHint: .isDirectory)
    }

    private static var url: URL { directory.appending(path: fileName) }

    func load() -> RadarMineFile {
        guard !inMemory else { return memory }
        guard let data = try? Data(contentsOf: Self.url) else { return .empty }
        return RadarMineFile(data: data)
    }

    /// Writes the file; an empty one is deleted (nothing remembered, nothing on disk).
    func save(_ file: RadarMineFile) {
        guard !inMemory else {
            memory = file
            return
        }
        guard !file.isEmpty else {
            try? FileManager.default.removeItem(at: Self.url)
            return
        }
        ensureDirectory()
        var url = Self.url
        try? file.encoded().write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// „Alle Daten löschen“ and „Alles vergessen“ in the panel: the file goes.
    func deleteAll() {
        memory = .empty
        guard !inMemory else { return }
        try? FileManager.default.removeItem(at: Self.url)
    }

    /// The folder on the first write: excluded from backups, readable after the first unlock.
    private func ensureDirectory() {
        let base = Self.directory
        guard !FileManager.default.fileExists(atPath: base.path) else { return }
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = base
        try? url.setResourceValues(values)
    }
}
