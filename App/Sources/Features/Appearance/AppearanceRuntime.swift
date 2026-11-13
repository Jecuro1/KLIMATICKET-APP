import Foundation
import KlimaCore

// MARK: themes – the Look & Feel values the app's static helpers read (docs/THEMES.md): `Format` (amounts, CO₂ unit),
// `MotionPolicy` (Bewegung „Aus“), the sky, count-ins, tilt and the shrinking hero (Bewegung „Ruhig“), and the screens with
// a week (Übersicht week card, Statistik weekdays and calendar). `AppearanceStore` sets them at launch and when the
// Settings sheet closes – never while a screen is half drawn. Readable from any thread (formatters run off the main actor).

enum AppearanceRuntime {
    /// Bewegung as applied to the screens.
    static var motion: MotionLevel { storage.withLock { $0.motion } }

    /// Zahlen as applied to the screens.
    static var format: FormatPrefs { storage.withLock { $0.format } }

    /// Sky drift, count-ins, tilt parallax and the shrinking hero run: only at Bewegung „Voll“ (the system's Reduce Motion
    /// is checked where they run, and it always wins).
    static var allowsDecoration: Bool { motion == .full }

    /// `Calendar.vienna` with the chosen first day of the week (Montag by default, like before the option).
    static var weekCalendar: Calendar { storage.withLock { $0.weekCalendar } }

    /// "Mo" … "So" in the order a week is shown (Sonntag first when the week starts on Sunday).
    static var weekdayColumns: [String] {
        let order = format.weekStart.mondayFirstOrder
        return order.map { AppearanceFormat.weekdayShort[$0] }
    }

    /// Seven Monday-first values (Mo … So) in display order. Anything that is not seven values comes back unchanged.
    static func weekOrdered<T>(_ mondayFirst: [T]) -> [T] {
        guard mondayFirst.count == 7 else { return mondayFirst }
        return format.weekStart.mondayFirstOrder.map { mondayFirst[$0] }
    }

    /// Applies motion and number format (the palette goes through `ThemeRuntime`).
    static func apply(_ prefs: AppearancePrefs) {
        storage.withLock { state in
            state.motion = prefs.motion
            if state.format != prefs.format {
                state.format = prefs.format
                state.weekCalendar = prefs.format.weekStart.calendar(from: .vienna)
            }
        }
    }

    // MARK: Storage

    private struct State {
        var motion: MotionLevel = .full
        var format: FormatPrefs = .standard
        var weekCalendar: Calendar = .vienna
    }

    private final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var state = State()

        func withLock<T>(_ body: (inout State) -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return body(&state)
        }
    }

    private static let storage = Storage()
}
