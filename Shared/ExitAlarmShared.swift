import AlarmKit
import AppIntents
import Foundation

// Aussteige-Wecker (docs/EXIT_ALARM.md §3): what the app and the widget extension share about the system alarm. AlarmKit
// shows its alarm as a Live Activity, so the extension needs the metadata type to draw it. Compiled into both targets.

/// The data that travels with an AlarmKit alarm (rendered by the widget extension's alarm Live Activity).
struct ExitAlarmMetadata: AlarmMetadata {
    var stopName: String
    var lineName: String
    /// "arrival" (Aussteigen!), "passed" (Vorbeigefahren) or "test".
    var kind: String
}

/// The "Öffnen" button of the ringing alarm: opens the app, where the full-screen "Aussteigen!" moment waits. A
/// `LiveActivityIntent` runs in the app's process, so the type lives in `Shared/` for both targets.
struct ExitAlarmOpenIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Aussteige-Wecker öffnen"
    static let description = IntentDescription("Öffnet KlimaBilanz beim klingelnden Aussteige-Wecker.")
    static let isDiscoverable = false
    static let openAppWhenRun = true

    init() {}

    func perform() async throws -> some IntentResult {
        .result()
    }
}
