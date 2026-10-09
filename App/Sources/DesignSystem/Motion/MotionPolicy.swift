import SwiftUI
import UIKit

/// When and how the app animates (docs/MOTION.md §3). Every animation goes through one of these wrappers so that
/// Reduce Motion (cross-fades instead of movement) and the CI screenshot mode (end state at once) hold everywhere.
enum MotionPolicy {
    /// CI screenshots (`-KBScreenshot`): every animation starts in its end state (DESIGN.md §6).
    static let isStatic: Bool = LaunchMode.isScreenshot

    /// Reduce Motion, read where no view environment is at hand (actions, view models). Views use
    /// `@Environment(\.accessibilityReduceMotion)` – it also updates the view when the setting changes.
    @MainActor static var prefersReducedMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    /// The animation to run for `animation`: nil in screenshot mode, a cross-fade under Reduce Motion.
    @MainActor static func animation(_ animation: Animation) -> Animation? {
        if isStatic { return nil }
        return Motion.resolved(animation, reduceMotion: prefersReducedMotion)
    }
}

/// `withAnimation` that follows the motion policy: `withMotion(.bouncy) { isFavorite.toggle() }`.
/// Screenshot mode: no animation. Reduce Motion: a short cross-fade instead of the spring.
@MainActor
@discardableResult
func withMotion<Result>(_ animation: Animation = Motion.snappy, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(MotionPolicy.animation(animation), body)
}

/// `withMotion` with a completion (called right away in screenshot mode).
@MainActor
func withMotion(_ animation: Animation = Motion.snappy, _ body: () -> Void, completion: @escaping () -> Void) {
    guard let resolved = MotionPolicy.animation(animation) else {
        body()
        completion()
        return
    }
    withAnimation(resolved, body, completion: completion)
}

// MARK: - View modifiers

extension View {
    /// `.animation(_:value:)` that follows the motion policy (cross-fade under Reduce Motion, none in screenshots).
    func motionAnimation<V: Equatable>(_ animation: Animation = Motion.snappy, value: V) -> some View {
        modifier(MotionAnimationModifier(animation: animation, value: value))
    }

    /// `.transition(_:)` that becomes a plain cross-fade under Reduce Motion.
    func motionTransition(_ transition: AnyTransition) -> some View {
        modifier(MotionTransitionModifier(transition: transition))
    }

    /// The SF Symbol bounces once whenever `trigger` changes (tap feedback, "it worked"). Off under Reduce Motion.
    func symbolBounce<V: Equatable>(on trigger: V) -> some View {
        modifier(SymbolBounceModifier(trigger: trigger))
    }

    /// A symbol that changes (`star` → `star.fill`, `play` → `pause`) morphs with the system replace effect.
    func symbolReplaceTransition() -> some View {
        contentTransition(.symbolEffect(.replace))
    }
}

private struct MotionAnimationModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(MotionPolicy.isStatic ? nil : Motion.resolved(animation, reduceMotion: reduceMotion), value: value)
    }
}

private struct MotionTransitionModifier: ViewModifier {
    let transition: AnyTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : transition)
    }
}

private struct SymbolBounceModifier<V: Equatable>: ViewModifier {
    let trigger: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .symbolEffect(.bounce, value: trigger)
            .symbolEffectsRemoved(reduceMotion || MotionPolicy.isStatic)
    }
}

// MARK: - Transitions

extension AnyTransition {
    /// Rises a few points into place while fading in (new rows, cards, inline sections).
    static var rise: AnyTransition {
        .opacity.combined(with: .offset(y: Motion.Distance.revealOffset)).combined(with: .scale(scale: Motion.Distance.revealScale, anchor: .top))
    }

    /// Pops in from a smaller size (badges, chips, a checkmark that confirms).
    static var pop: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.6))
    }

    /// Slides in from the bottom edge and fades (toasts, bottom bars, inline banners).
    static var lift: AnyTransition {
        .opacity.combined(with: .move(edge: .bottom))
    }

    /// Slides in from the top edge and fades (top banners, the global toast).
    static var drop: AnyTransition {
        .opacity.combined(with: .move(edge: .top))
    }
}
