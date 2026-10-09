import SwiftUI

/// Motion tokens – the single source of truth for springs, durations, stagger and distances (docs/MOTION.md).
/// Shared by the app and the widget extension; the app's modifiers (App/Sources/DesignSystem/Motion) build on these.
///
/// Rule of thumb: **snappy** for anything the finger touched, **smooth** for layout and glass morphs, **bouncy** only for
/// a confirmation the user should feel, **gentle** for big numbers and charts settling.
enum Motion {
    // MARK: Springs

    /// Taps, toggles, chips, selection capsules, small state changes. Fast, a hint of life, no visible overshoot.
    static let snappy = Animation.spring(duration: 0.3, bounce: 0.12)
    /// Layout changes, expanding cards, glass morphs, content swaps. Critically damped.
    static let smooth = Animation.spring(duration: 0.42, bounce: 0)
    /// Confirmations the user should feel: swap button, favourite star, a logged trip popping in. Use sparingly.
    static let bouncy = Animation.spring(duration: 0.5, bounce: 0.32)
    /// Large, calm settling: hero numerals, charts drawing, background changes.
    static let gentle = Animation.spring(duration: 0.8, bounce: 0.06)

    /// Staggered content reveal on first appearance.
    static let reveal = Animation.spring(duration: 0.55, bounce: 0.12)
    /// Number changes (`.numericText` digit roll).
    static let number = Animation.spring(duration: 0.5, bounce: 0.1)
    /// Hero values counting in once (fast start, long soft landing – "ease-out expo").
    static let countIn = Animation.timingCurve(0.16, 1, 0.3, 1, duration: Duration.countIn)
    /// Finger down: immediate, no bounce.
    static let press = Animation.spring(duration: 0.18, bounce: 0)
    /// Finger up: springs back with a little life.
    static let release = Animation.spring(duration: 0.36, bounce: 0.28)
    /// Reduce Motion substitute for every spring above: a short cross-fade, nothing moves.
    static let crossfade = Animation.easeInOut(duration: Duration.quick)

    /// The same springs for `KeyframeAnimator` tracks (`SpringKeyframe(…, spring: Motion.Springs.bouncy)`).
    enum Springs {
        static let snappy = Spring(duration: 0.3, bounce: 0.12)
        static let smooth = Spring(duration: 0.42, bounce: 0)
        static let bouncy = Spring(duration: 0.5, bounce: 0.32)
        static let gentle = Spring(duration: 0.8, bounce: 0.06)
    }

    // MARK: Durations (seconds)

    enum Duration {
        /// Highlight flashes, symbol replace.
        static let instant: Double = 0.12
        /// Cross-fades, Reduce Motion substitutes, toasts fading.
        static let quick: Double = 0.22
        /// Default UI transition.
        static let standard: Double = 0.35
        /// Route/progress drawing, larger sheets of content.
        static let slow: Double = 0.6
        /// Hero count-in.
        static let countIn: Double = 1.1
        /// Upper bound for any celebration (break-even, milestone) before it is fully out of the way.
        static let celebration: Double = 1.4
    }

    // MARK: Stagger

    enum Stagger {
        /// Delay between neighbours in a reveal sequence.
        static let step: Double = 0.045
        /// Items after this index share the last delay – a long list never makes the user wait.
        static let maxSteps = 8
        /// Content that appears this long after its screen first appeared shows at once (refreshes, rows scrolled in).
        static let window: Double = 0.9

        static func delay(_ index: Int) -> Double { Double(min(max(index, 0), maxSteps)) * step }
    }

    // MARK: Distances

    enum Distance {
        /// Reveal: content rises this far into place.
        static let revealOffset: CGFloat = 14
        static let revealScale: CGFloat = 0.97
        /// Focus reveal (hero numbers, short headlines only – blur is expensive on large areas).
        static let focusBlur: CGFloat = 8
        static let focusScale: CGFloat = 0.92
        /// Pressed buttons / chips.
        static let pressScale: CGFloat = 0.95
        /// Pressed cards and rows (large surfaces move less).
        static let pressScaleCard: CGFloat = 0.98
    }

    /// `animation`, or the cross-fade when Reduce Motion is on.
    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? crossfade : animation
    }
}

extension View {
    /// Widgets and Live Activities: the digits roll when the next timeline entry / activity update arrives (the system
    /// animates the change; the app uses `numericValue(_:)`, which also follows Reduce Motion and screenshot mode).
    func rollingDigits(_ value: Double) -> some View {
        contentTransition(.numericText(value: value))
    }
}
