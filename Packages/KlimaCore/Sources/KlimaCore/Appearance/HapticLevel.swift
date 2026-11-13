import Foundation

// MARK: themes – „Haptik“ in Look & Feel (docs/THEMES.md §5): one table from every haptic of the app to what plays.

/// How strongly the app answers by touch. Replaces the old switch „Haptisches Feedback“ (`hapticsEnabled`).
public enum HapticLevel: String, CaseIterable, Codable, Sendable, Identifiable {
    case off = "aus"
    case subtle = "dezent"
    case full = "voll"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: "Aus"
        case .subtle: "Dezent"
        case .full: "Voll"
        }
    }

    public var detail: String {
        switch self {
        case .off: "Kein Vibrieren."
        case .subtle: "Leichtere Stöße, keine Ticks beim Auswählen. Bestätigungen bleiben."
        case .full: "Jede Bestätigung, jede Auswahl und jedes Einrasten ist spürbar."
        }
    }

    /// The old Bool setting: `false` becomes Aus, `true` and „never set“ become Voll.
    public static func migrated(hapticsEnabled: Bool?) -> HapticLevel {
        hapticsEnabled == false ? .off : .full
    }
}

/// The app's haptics vocabulary (App/Sources/DesignSystem/Motion/Haptics.swift, docs/MOTION.md §6) – one case per `Haptic`
/// case, same names (a test reads Haptics.swift and compares).
public enum HapticEvent: String, CaseIterable, Sendable {
    case success, warning, error, selection, tap, snap, increase, decrease, milestone, start, stop
}

/// What the phone plays.
public enum HapticOutput: Equatable, Sendable {
    public enum Weight: Int, Comparable, Sendable {
        case light, medium, heavy
        public static func < (lhs: Weight, rhs: Weight) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    case none
    case success, warning, error
    case selection
    case impact(Weight, intensity: Double)
    case increase, decrease
    case levelChange
    case start, stop

    public var isSilent: Bool { self == .none }
}

public enum HapticTable {
    /// Voll: what the app played before levels existed.
    public static func full(_ event: HapticEvent) -> HapticOutput {
        switch event {
        case .success: .success
        case .warning: .warning
        case .error: .error
        case .selection: .selection
        case .tap: .impact(.light, intensity: 0.7)
        case .snap: .impact(.medium, intensity: 0.85)
        case .increase: .increase
        case .decrease: .decrease
        case .milestone: .levelChange
        case .start: .start
        case .stop: .stop
        }
    }

    /// Lowest intensity a light impact is lowered to (light is the lightest weight there is).
    public static let subtleLightIntensity = 0.45

    /// The output of `event` at `level`. Dezent lowers every impact one step (medium → light, light → a softer light)
    /// and drops the selection ticks; confirmations, warnings and milestones stay as they are.
    public static func output(_ event: HapticEvent, level: HapticLevel) -> HapticOutput {
        switch level {
        case .off:
            return .none
        case .full:
            return full(event)
        case .subtle:
            switch full(event) {
            case .selection:
                return .none
            case let .impact(weight, intensity):
                if weight == .light { return .impact(.light, intensity: min(intensity, subtleLightIntensity)) }
                return .impact(HapticOutput.Weight(rawValue: weight.rawValue - 1) ?? .light, intensity: intensity)
            case let other:
                return other
            }
        }
    }
}
