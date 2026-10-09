import SwiftUI

extension View {
    /// Every number that changes animates: the digits roll (`.numericText`) with `Motion.number` whenever `value`
    /// changes. Put it on the `Text` that shows the value (with a `monospacedDigit()` font).
    /// Reduce Motion: a cross-fade. Screenshot mode: no animation.
    ///
    ///     Text(Format.euro(total)).font(Theme.Typography.numberMedium).numericValue(total)
    func numericValue(_ value: Double, countsDown: Bool = false) -> some View {
        modifier(NumericValueModifier(value: value, countsDown: countsDown))
    }
}

private struct NumericValueModifier: ViewModifier {
    let value: Double
    let countsDown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .opacity : (countsDown ? .numericText(countsDown: true) : .numericText(value: value)))
            .animation(MotionPolicy.isStatic ? nil : Motion.resolved(Motion.number, reduceMotion: reduceMotion), value: value)
    }
}

/// A hero value that counts in once on its first appearance (0 → value, `Motion.countIn`) and afterwards rolls its digits
/// on every change like `numericValue`. Style it like a `Text` (font, colour, `monospacedDigit`).
/// VoiceOver always reads the final value. Reduce Motion / screenshot mode: the final value at once.
///
///     CountUpText(value: snapshot.summary.totalValue) { Format.euro($0) }
///         .font(Theme.Typography.priceNumeral)
struct CountUpText: View {
    var value: Double
    /// Where the count starts (0, or e.g. the previous total for "73 → 77 %").
    var from: Double = 0
    var delay: Double = 0
    /// Must be cheap: it runs on every frame of the count (Format.* is fine – it uses cached format styles).
    var format: (Double) -> String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// nil until the first appearance; then the animated value of the count-in.
    @State private var counted: Double?
    @State private var isSettled = MotionPolicy.isStatic

    init(value: Double, from: Double = 0, delay: Double = 0, format: @escaping (Double) -> String) {
        self.value = value
        self.from = from
        self.delay = delay
        self.format = format
    }

    var body: some View {
        Group {
            if isSettled {
                Text(format(value))
                    .numericValue(value)
            } else {
                CountingLabel(value: counted ?? from, format: format)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(format(value)))
            }
        }
        .onAppear(perform: countIn)
        .onChange(of: value) { _, new in
            // A new value while counting in: retarget the running count instead of jumping at the end.
            guard !isSettled, counted != nil else { return }
            withAnimation(Motion.number) { counted = new }
        }
    }

    private func countIn() {
        guard !isSettled, counted == nil else { return }
        guard !reduceMotion, value != from else {
            isSettled = true
            return
        }
        counted = from
        withAnimation(Motion.countIn.delay(delay)) {
            counted = value
        } completion: {
            isSettled = true   // same string as the last frame of the count: the swap is invisible
        }
    }
}

/// Interpolates the number itself (not the glyphs) so a count-in reads like a counter.
private struct CountingLabel: View, Animatable {
    var value: Double
    let format: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(format(value))
    }
}
