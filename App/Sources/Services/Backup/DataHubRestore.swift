import Foundation
import SwiftData
import KlimaCore

// MARK: data – restore with a preview (docs/DATA_HUB.md §5): read and check the file, count what the merge would change, and only on
// „Wiederherstellen“ take a safety backup, merge (newer wins, nothing is deleted that the file does not delete) and report as before.
// Live-data consent and sign-in are never part of a backup, so a restore cannot change them.

/// What a file would change – everything the preview sheet shows.
struct DataHubRestorePreview: Identifiable {
    let id = UUID()
    var title: String
    var data: Data
    var details: DataHubBackupDetails
    var diff: BackupDiff
    /// The file's settings that differ from this iPhone's (allowed keys only).
    var settingsChanges: [String]
    var settings: [String: BackupSettingValue]
    var isFromNewerApp: Bool
}

enum DataHubRestore {
    enum Failure: Error, Equatable {
        case unreadable
        case refused(BackupInspection.Problem)

        var message: String {
            switch self {
            case .unreadable: "Die Datei konnte nicht geöffnet werden."
            case .refused(let problem): problem.message
            }
        }
    }

    /// Reads a picked or listed file off the main thread and builds the preview. Nothing is written.
    static func preview(url: URL, title: String, container: ModelContainer) async -> Result<DataHubRestorePreview, Failure> {
        await Task.detached(priority: .userInitiated) { () -> Result<DataHubRestorePreview, Failure> in
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return .failure(.unreadable) }
            return makePreview(data: data, title: title, context: ModelContext(container))
        }.value
    }

    static func preview(data: Data, title: String, container: ModelContainer) async -> Result<DataHubRestorePreview, Failure> {
        await Task.detached(priority: .userInitiated) { makePreview(data: data, title: title, context: ModelContext(container)) }.value
    }

    nonisolated static func makePreview(data: Data, title: String, context: ModelContext) -> Result<DataHubRestorePreview, Failure> {
        let inspection = BackupInspection.inspect(data)
        if let problem = inspection.problem { return .failure(.refused(problem)) }
        guard let file = try? Backup.decodeFile(data), let current = try? Backup.currentStamps(context: context) else {
            return .failure(.refused(.notABackup))
        }
        let settings = file.settings ?? [:]
        return .success(DataHubRestorePreview(
            title: title, data: data, details: DataHubFolder.details(of: data),
            diff: BackupDiff.make(file: Backup.stamps(of: file), current: current),
            settingsChanges: LaunchMode.isSandboxed ? Array(settings.keys).sorted() : BackupSettingsSnapshot.changes(in: settings),
            settings: settings, isFromNewerApp: inspection.isFromNewerApp))
    }

    enum Outcome: Equatable {
        /// The toast's subtitle („140 Fahrten, 2 Tickets … importiert“).
        case restored(String)
        case failed(String)
    }

    /// „Wiederherstellen“: safety backup first (no copy, no restore), then the merge, the reminders of restored tickets and the
    /// staged settings.
    @MainActor
    static func run(_ preview: DataHubRestorePreview, includeSettings: Bool, app: AppState, context: ModelContext) async -> Outcome {
        let safety = await AutoBackupService.shared.safetyBackup(.beforeRestore, container: context.container)
        guard safety.allowsDestructiveStep else {
            return .failed("Die Sicherung davor ging nicht – es wurde nichts geändert.")
        }
        do {
            let imported = try Backup.restoreChecked(preview.data, context: context)
            let repository = Repository(context: context, app: app)
            repository.commit()
            // Restored tickets need their renewal reminders (no-op when reminders are off).
            for ticket in repository.liveTickets() where !ticket.isExpired {
                repository.scheduleReminders(for: ticket)
            }
            if includeSettings && !preview.settings.isEmpty { BackupSettingsSnapshot.stage(preview.settings) }
            return .restored(imported.summary + (includeSettings && !preview.settingsChanges.isEmpty ? " · Einstellungen beim nächsten Start" : ""))
        } catch let error as DataHubRestoreError {
            return .failed(error.errorDescription ?? "Die Datei ist kein gültiges KlimaBilanz-Backup.")
        } catch {
            return .failed("Die Datei ist kein gültiges KlimaBilanz-Backup.")
        }
    }

    /// German names of the settings keys, for the preview (unknown keys say what they are by their group).
    static func settingTitle(_ key: String) -> String {
        switch key {
        case "appearance": "Erscheinungsbild"
        case "defaultDiscount": "Ermäßigung"
        case "defaultTravelClass": "Klasse"
        case "homeStationID": "Heimatbahnhof"
        case "hapticsEnabled": "Haptik"
        case "autoUpdateCheck": "Update-Prüfung"
        case "renewalRemindersEnabled": "Verlängerungs-Erinnerung"
        case "weeklySummaryEnabled": "Wochenrückblick"
        case "localAIEnabled": "KI auf dem Gerät"
        case "map.layers", "atlas.mapLook": "Karte"
        case "planner.options", "planner.sort": "Fahrplan"
        case "commute.settings.v1": "Pendeln"
        case "calendarSuggestions.prefs.v1": "Kalender-Vorschläge"
        case "kb.whatif.scenarios.v1": "Was-wäre-wenn"
        case "rules.v1": "Automatik-Regeln"
        default:
            if key.hasPrefix("theme.") { "Look & Feel" }
            else if key.hasPrefix("features.") { "Funktionen" }
            else if key.hasPrefix("radar") { "Zug-Radar" }
            else if key.hasPrefix("dash.") || key.hasPrefix("goals.") { "Übersicht" }
            else { key }
        }
    }

    /// „Look & Feel, Zug-Radar, Pendeln“ – each group once.
    static func settingsLine(_ keys: [String]) -> String {
        var seen: [String] = []
        for title in keys.map(settingTitle) where !seen.contains(title) { seen.append(title) }
        return seen.joined(separator: ", ")
    }
}
