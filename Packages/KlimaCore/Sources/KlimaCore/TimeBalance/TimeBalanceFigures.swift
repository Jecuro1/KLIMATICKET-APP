import Foundation

// MARK: - „Zeitbilanz“: how a duration is shown, as numbers (docs/TIME_BALANCE.md §8)

/// A duration as the Zeitbilanz shows it: whole minutes below an hour („45 Min.“), hours to a tenth below ten hours
/// („4,5 Std.“, „4 Std.“), whole hours from there („128 Std.“). The app adds the words and the de-AT number format.
public struct TimeBalanceFigure: Hashable, Sendable {
    public enum Unit: Hashable, Sendable {
        case minutes
        case hours
    }

    /// In `unit`.
    public var value: Double
    /// Decimals to show (1 only for a tenth of an hour that is not whole).
    public var decimals: Int
    public var unit: Unit

    public init(value: Double, decimals: Int, unit: Unit) {
        self.value = value
        self.decimals = decimals
        self.unit = unit
    }

    /// `minutes` (negative, NaN or infinite count as 0) rounded the way the screen shows it.
    public init(minutes: Double) {
        let rounded = max(0, minutes.isFinite ? minutes.rounded() : 0)
        if rounded < 60 {
            self.init(value: rounded, decimals: 0, unit: .minutes)
            return
        }
        let hours = rounded / 60
        if hours < 10 {
            let tenths = (hours * 10).rounded() / 10
            self.init(value: tenths, decimals: tenths == tenths.rounded() ? 0 : 1, unit: .hours)
            return
        }
        self.init(value: hours.rounded(), decimals: 0, unit: .hours)
    }

    /// The shown figure in minutes: 45 Min. → 45, 4,5 Std. → 270, 128 Std. → 7680.
    public var shownMinutes: Double { unit == .minutes ? value : value * 60 }

    /// The precision a shown figure has, in minutes: 1 below an hour, 6 (a tenth of an hour) below ten hours, 60 above.
    public static func stepMinutes(ofShown minutes: Double) -> Double {
        if minutes < 60 { return 1 }
        return minutes < 600 ? 6 : 60
    }
}

/// Figures on one card that a reader adds up or subtracts: worked out from what is shown, so that they agree.
public enum TimeBalanceRounding {
    /// `parts` (minutes) in the precision of their shown sum, adding up to exactly that sum (largest remainder): under
    /// „72 Std.“ the parts read „26 Std.“ and „46 Std.“, never „26 Std.“ and „45 Std.“ (each rounded on its own). Returns shown minutes per part, in
    /// the input order. A part above 0 that gets no whole step comes back as 0 – the app shows it as „< 1 Std.“.
    public static func split(_ parts: [Double]) -> [Double] {
        let clean = parts.map { $0.isFinite ? max(0, $0) : 0 }
        let total = TimeBalanceFigure(minutes: clean.reduce(0, +)).shownMinutes
        guard total > 0 else { return clean.map { _ in 0 } }
        let step = TimeBalanceFigure.stepMinutes(ofShown: total)
        let units = Int((total / step).rounded())
        let exact = clean.map { $0 / step }
        var shown = exact.map { Int($0.rounded(.down)) }
        var missing = units - shown.reduce(0, +)
        // The steps rounding down left over go to the largest remainders (ties: the earlier part).
        let order = exact.indices
            .filter { exact[$0] - Double(shown[$0]) > 1e-9 }
            .sorted { lhs, rhs in
                let a = exact[lhs] - Double(shown[lhs]), b = exact[rhs] - Double(shown[rhs])
                return abs(a - b) > 1e-9 ? a > b : lhs < rhs
            }
        for index in order where missing > 0 {
            shown[index] += 1
            missing -= 1
        }
        return shown.map { Double($0) * step }
    }

    /// The gap between two figures as the reader sees it: the difference of the two shown figures (79 Std. − 72 Std. =
    /// 7 Std., not the 7,3 Std. between the unrounded values; 12 Std. − 9,6 Std. = 2,4 Std.). When both show the same
    /// figure, the unrounded gap. Minutes.
    public static func shownGap(_ a: Double, _ b: Double) -> Double {
        let shown = abs(TimeBalanceFigure(minutes: a).shownMinutes - TimeBalanceFigure(minutes: b).shownMinutes)
        guard shown > 0 else {
            let raw = abs(a - b)
            return raw.isFinite ? raw : 0
        }
        return shown
    }
}
