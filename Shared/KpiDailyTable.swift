import Foundation
import KlimaCore

// MARK: siri – where the table behind „Fragen an KlimaBilanz“ lives (docs/SIRI_QUESTIONS.md §2): one small JSON file in the App Group
// container (sums per day, no trips, no stations). The app writes it (SiriKpiWriter); Siri and the Kurzbefehle-App read it without
// opening the SwiftData store. Shared source: compiled into the app and the widget extension, so it uses no app-only API.

enum SiriKpiFile {
    static let fileName = "kpi-daily.v1.json"

    /// In the App Group container; Application Support when the group is unavailable (unsigned simulator builds – the intents run
    /// in the app's process there, so they find it all the same).
    static var url: URL? {
        if let container = AppGroup.containerURL { return container.appendingPathComponent(fileName) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName)
    }

    /// nil when there is none yet or it cannot be read (the answer then asks to open the app).
    static func load() -> KpiDailyTable? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return KpiDailyTable.decode(data)
    }

    /// Atomic: a reader sees the old table or the new one, never half a file.
    @discardableResult
    static func save(_ table: KpiDailyTable) -> Bool {
        guard let url, let data = table.encoded() else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
