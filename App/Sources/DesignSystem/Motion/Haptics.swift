import SwiftUI

/// The app's haptics vocabulary (docs/MOTION.md §6). One meaning per haptic, used the same way on every screen.
/// All of them respect Einstellungen › Haptik (`AppSettings.hapticsEnabled`) and are silent in screenshot mode.
enum Haptic {
    /// Something was saved or logged: trip saved, favourite logged, ticket added, import finished.
    case success
    /// Something was removed or is about to be lost: trip deleted, "Alles löschen" confirmed.
    case warning
    /// An action failed: save error, sign-in failed.
    case error
    /// A value was picked: segment, chip, mode, ticket year, picker wheel.
    case selection
    /// A light physical tap: button press, card flip, swap stations, expand/collapse.
    case tap
    /// A firmer snap: something docked into place – a carousel landing, a drag dropped, a toggle that matters.
    case snap
    /// A value stepped up / down (steppers, passengers, price adjust).
    case increase, decrease
    /// A threshold was crossed: 25/50/75 % milestones, break-even, a new achievement tier.
    case milestone
    /// A long-running thing began / ended: live ride started / ended, trip detection on / off.
    case start, stop

    var feedback: SensoryFeedback {
        switch self {
        case .success: .success
        case .warning: .warning
        case .error: .error
        case .selection: .selection
        case .tap: .impact(weight: .light, intensity: 0.7)
        case .snap: .impact(weight: .medium, intensity: 0.85)
        case .increase: .increase
        case .decrease: .decrease
        case .milestone: .levelChange
        case .start: .start
        case .stop: .stop
        }
    }
}

extension View {
    /// Plays `haptic` whenever `trigger` changes (if haptics are on in Einstellungen).
    ///
    ///     .haptic(.success, trigger: savedCount)
    func haptic<T: Equatable>(_ haptic: Haptic, trigger: T) -> some View {
        modifier(HapticModifier(haptic: haptic, trigger: trigger, condition: { _, _ in true }))
    }

    /// Plays `haptic` when `trigger` changes and `condition(old, new)` holds.
    ///
    ///     .haptic(.milestone, trigger: summary.isPaidOff, when: { old, new in !old && new })
    func haptic<T: Equatable>(_ haptic: Haptic, trigger: T, when condition: @escaping (T, T) -> Bool) -> some View {
        modifier(HapticModifier(haptic: haptic, trigger: trigger, condition: condition))
    }
}

private struct HapticModifier<T: Equatable>: ViewModifier {
    let haptic: Haptic
    let trigger: T
    let condition: (T, T) -> Bool
    /// Optional: the design-system gallery and previews run without an AppState.
    @Environment(AppState.self) private var app: AppState?

    func body(content: Content) -> some View {
        content.sensoryFeedback(haptic.feedback, trigger: trigger) { old, new in
            guard !MotionPolicy.isStatic, app?.settings.hapticsEnabled ?? true else { return false }
            return condition(old, new)
        }
    }
}
