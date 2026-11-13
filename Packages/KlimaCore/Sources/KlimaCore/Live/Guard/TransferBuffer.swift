import Foundation

// Anschluss-Wächter (docs/CONNECTION_GUARD.md §2): the one minute formula of a change. The connection detail
// (`JourneyPresentation.transfers`), the guard card and the follow's „Anschluss knapp“ notice all call it, so the same data
// can never give two different numbers on two screens.

/// Spare minutes of a change: the connecting departure minus the feeder's arrival, rounded to whole minutes, minus the walk.
public enum TransferBuffer {
    /// `departure − arrival` in whole minutes (half to even, as `JourneyPresentation.minutesBetween`), then the walk subtracted.
    /// 4 min 40 s → 5, −30 s → 0, −90 s → −2. Negative: you are short of that many minutes.
    public static func minutes(arrival: Date, departure: Date, walkMinutes: Int) -> Int {
        roundedMinutes(from: arrival, to: departure) - walkMinutes
    }

    /// Whole minutes from `a` to `b`, half to even (Python `round`, the reference of the planner presentation).
    public static func roundedMinutes(from a: Date, to b: Date) -> Int {
        Int((b.timeIntervalSince(a) / 60).rounded(.toNearestOrEven))
    }

    /// The `TransferRisk.ok` threshold: from this many spare minutes on a change counts as safe.
    public static let safeMinutes = 5
}
