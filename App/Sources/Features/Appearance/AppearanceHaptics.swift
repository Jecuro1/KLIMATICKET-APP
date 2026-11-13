import SwiftUI
import KlimaCore

// MARK: themes – Haptik „Aus · Dezent · Voll“ (docs/THEMES.md §5): every `Haptic` plays what the KlimaCore table says for the
// chosen level. Voll is exactly what the app played before levels existed (a test compares the table with `Haptic.feedback`).

extension Haptic {
    /// The same case in KlimaCore's table.
    var event: HapticEvent {
        switch self {
        case .success: .success
        case .warning: .warning
        case .error: .error
        case .selection: .selection
        case .tap: .tap
        case .snap: .snap
        case .increase: .increase
        case .decrease: .decrease
        case .milestone: .milestone
        case .start: .start
        case .stop: .stop
        }
    }

    /// What plays at `level`; nil plays nothing.
    func feedback(at level: HapticLevel) -> SensoryFeedback? {
        HapticTable.output(event, level: level).sensoryFeedback
    }
}

extension HapticOutput {
    var sensoryFeedback: SensoryFeedback? {
        switch self {
        case .none: nil
        case .success: .success
        case .warning: .warning
        case .error: .error
        case .selection: .selection
        case let .impact(weight, intensity): .impact(weight: weight.sensoryWeight, intensity: intensity)
        case .increase: .increase
        case .decrease: .decrease
        case .levelChange: .levelChange
        case .start: .start
        case .stop: .stop
        }
    }
}

extension HapticOutput.Weight {
    var sensoryWeight: SensoryFeedback.Weight {
        switch self {
        case .light: .light
        case .medium: .medium
        case .heavy: .heavy
        }
    }
}
