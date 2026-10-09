import SwiftUI

// Scroll-driven motion (docs/MOTION.md §9). Everything here is a render-time transform (scale, offset, opacity) –
// no layout, no blur, no state change per frame – so scrolling stays at 120 Hz.

extension View {
    /// Cards settle in as they scroll into view from the bottom edge (95 % → 100 %, a touch of opacity) and stay put
    /// everywhere else. Put it on each card of a vertical scroll view. Reduce Motion: opacity only.
    func scrollCardTransition() -> some View {
        modifier(ScrollCardTransitionModifier())
    }

    /// On a horizontal `ScrollView` of cards or chips: snaps to items, keeps the screen gutter, lets shadows overflow.
    /// The stack inside needs `.scrollTargetLayout()`.
    ///
    ///     ScrollView(.horizontal) {
    ///         LazyHStack(spacing: 10) { ForEach(favorites) { FavoriteChip($0).carouselItem() } }
    ///             .scrollTargetLayout()
    ///     }
    ///     .carouselScrolling()
    func carouselScrolling(margin: CGFloat = Theme.Spacing.cardGutter) -> some View {
        scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, margin, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
    }

    /// On each carousel item: items leaving the visible area recede slightly (scale + opacity).
    func carouselItem() -> some View {
        modifier(CarouselItemModifier())
    }

    /// On a vertical `ScrollView`: publishes how far the user scrolled past `distance` points as 0 … 1 into
    /// `progress` (quantised, clamped – no updates once condensed), for a hero/header that condenses and for a compact
    /// title that fades in. Only views that read `progress.value` re-render while scrolling.
    func tracksScrollCondense(_ progress: ScrollCondense, distance: CGFloat = 180) -> some View {
        onScrollGeometryChange(for: CGFloat.self) { geometry in
            let offset = geometry.contentOffset.y + geometry.contentInsets.top
            return ScrollCondense.quantise(offset / max(distance, 1))
        } action: { _, new in
            if progress.value != new { progress.value = new }
        }
    }

    /// The hero condenses with the scroll: shrinks towards `minScale` (anchored at the top), fades a little and lags
    /// behind (gentle parallax). Pair with `tracksScrollCondense` on the scroll view. Reduce Motion: fade only.
    func heroCondense(_ progress: ScrollCondense, minScale: CGFloat = 0.82, fadeTo: Double = 0.35) -> some View {
        modifier(HeroCondenseModifier(progress: progress, minScale: minScale, fadeTo: fadeTo))
    }
}

/// Scroll progress of a condensing hero/header, 0 (at rest) … 1 (condensed). Hold it in `@State` of the screen and
/// pass it down; reading `value` in a small subview keeps the screen's own body out of the scroll updates.
@Observable
@MainActor
final class ScrollCondense {
    fileprivate(set) var value: CGFloat = 0

    /// Fully condensed (show the compact title, hide the big numeral from VoiceOver order, …).
    var isCondensed: Bool { value >= 0.98 }

    nonisolated static func quantise(_ raw: CGFloat) -> CGFloat {
        let clamped = min(max(raw, 0), 1)
        return (clamped * 48).rounded() / 48
    }
}

private struct ScrollCardTransitionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.scrollTransition(topLeading: .identity, bottomTrailing: .interactive.threshold(.visible(0.35))) { [reduceMotion] effect, phase in
            // 0 = in place … 1 = just below the bottom edge (only the bottom edge transitions).
            let t = max(phase.value, 0)
            return effect
                .opacity(1 - 0.45 * t)
                .scaleEffect(reduceMotion ? 1 : 1 - 0.05 * t, anchor: .top)
                .offset(y: reduceMotion ? 0 : 12 * t)
        }
    }
}

private struct CarouselItemModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.scrollTransition(.interactive.threshold(.visible(0.6)), axis: .horizontal) { [reduceMotion] effect, phase in
            let t = abs(phase.value)
            return effect
                .opacity(1 - 0.4 * t)
                .scaleEffect(reduceMotion ? 1 : 1 - 0.06 * t)
        }
    }
}

private struct HeroCondenseModifier: ViewModifier {
    let progress: ScrollCondense
    let minScale: CGFloat
    let fadeTo: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let p = progress.value
        content
            .scaleEffect(reduceMotion ? 1 : 1 - (1 - minScale) * p, anchor: .top)
            .offset(y: reduceMotion ? 0 : 40 * p)
            .opacity(1 - (1 - fadeTo) * Double(p))
    }
}
