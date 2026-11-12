import Foundation
import Observation
import KlimaCore

// Aussteige-Wecker: the user's choices (docs/EXIT_ALARM.md §4). UserDefaults only, on this device. They are read by the sheet
// (default lead), by the schedulers (sound) and by Settings (all three).

enum ExitAlarmSound: String, CaseIterable, Identifiable {
    /// The system's standard alarm tone.
    case standard
    case glocke
    case signal
    case sanft

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .glocke: "Glocke"
        case .signal: "Signal"
        case .sanft: "Sanft"
        }
    }

    var subtitle: String {
        switch self {
        case .standard: "Der Alarmton von iOS"
        case .glocke: "Drei helle Glockenschläge"
        case .signal: "Kurze, dringende Töne"
        case .sanft: "Aufsteigender Klang"
        }
    }

    /// File in the app bundle (App/Resources, written by scripts/gen_exit_alarm_sounds.py); nil for the system tone.
    var fileName: String? {
        self == .standard ? nil : "exitalarm-\(rawValue).wav"
    }

    static func from(key: String) -> ExitAlarmSound { ExitAlarmSound(rawValue: key) ?? .standard }
}

@MainActor
@Observable
final class ExitAlarmPrefs {
    static let shared = ExitAlarmPrefs()

    private enum Keys {
        static let lead = "exitAlarm.lead"
        static let sound = "exitAlarm.sound"
        static let transfers = "exitAlarm.transfers"
    }

    /// The lead the sheet starts with (docs: 5 minutes).
    var defaultLead: ExitAlarmLead {
        didSet { UserDefaults.standard.set(defaultLead.minutes, forKey: Keys.lead) }
    }

    var sound: ExitAlarmSound {
        didSet { UserDefaults.standard.set(sound.rawValue, forKey: Keys.sound) }
    }

    /// The sheet pre-selects the end of a leg that is a transfer. Off: the user ticks it themselves.
    var alsoForTransfers: Bool {
        didSet { UserDefaults.standard.set(alsoForTransfers, forKey: Keys.transfers) }
    }

    init(defaults: UserDefaults = .standard) {
        defaultLead = defaults.object(forKey: Keys.lead) == nil ? .standard : ExitAlarmLead(minutes: defaults.integer(forKey: Keys.lead))
        sound = ExitAlarmSound.from(key: defaults.string(forKey: Keys.sound) ?? "")
        alsoForTransfers = defaults.object(forKey: Keys.transfers) == nil ? true : defaults.bool(forKey: Keys.transfers)
    }
}
