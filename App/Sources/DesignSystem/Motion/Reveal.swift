import SwiftUI

/// How content enters on its first appearance (docs/MOTION.md §4).
enum RevealStyle {
    /// Fades in while rising a few points and growing from 97 % – cards, rows, sections (the default).
    case rise
    /// Fades in out of a soft blur while growing from 92 % – hero numbers and short headlines only (blur is costly
    /// on large areas).
    case focus
    /// Pops in from 60 % with a bouncy spring – badges, chips, small confirmations.
    case pop
    /// Opacity only – dense content, or where movement would distract.
    case fade

    fileprivate var animation: Animation {
        switch self {
        case .rise, .fade: Motion.reveal
        case .focus: Motion.gentle
        case .pop: Motion.bouncy
        }
    }
}

extension View {
    /// Enters with a short spring on its **first** appearance only (not on refreshes, tab switches or when scrolled back).
    /// `order` staggers neighbours (`Motion.Stagger`); `delay` adds a fixed wait in seconds.
    /// Reduce Motion: a plain fade. Screenshot mode: shown at once.
    ///
    ///     ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
    ///         CardView(card).reveal(order: index)
    ///     }
    func reveal(_ style: RevealStyle = .rise, order: Int = 0, delay: Double = 0) -> some View {
        modifier(RevealModifier(style: style, delay: Motion.Stagger.delay(order) + delay))
    }

    /// Marks a screen (put it on the scroll view or the screen's root): its `reveal`s play once as one entrance, and
    /// content that appears later than `Motion.Stagger.window` after the screen (rows scrolled in, refreshed data, a
    /// recycled list cell) shows at once instead of replaying the entrance.
    func revealScope() -> some View {
        modifier(RevealScopeModifier())
    }
}

/// The time a screen's entrance started (see `revealScope()`).
@MainActor
final class RevealScope {
    private var startedAt: Date?

    /// The first reveal (or the screen) to appear starts the clock.
    func begin() {
        if startedAt == nil { startedAt = Date() }
    }

    /// The entrance is over: whatever appears now is not part of it.
    var isSettled: Bool {
        guard let startedAt else { return false }
        return Date().timeIntervalSince(startedAt) > Motion.Stagger.window
    }
}

extension EnvironmentValues {
    @Entry var revealScope: RevealScope? = nil
}

private struct RevealScopeModifier: ViewModifier {
    @State private var scope = RevealScope()

    func body(content: Content) -> some View {
        content
            .environment(\.revealScope, scope)
            .onAppear { scope.begin() }
    }
}

private struct RevealModifier: ViewModifier {
    let style: RevealStyle
    let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.revealScope) private var scope
    /// Screenshots start revealed; everything else starts hidden until its first `onAppear`.
    @State private var isShown = MotionPolicy.isStatic

    func body(content: Content) -> some View {
        let hidden = !isShown
        let moves = hidden && !reduceMotion
        content
            .opacity(hidden ? 0 : 1)
            .scaleEffect(moves ? hiddenScale : 1, anchor: style == .rise ? .top : .center)
            .offset(y: moves && style == .rise ? Motion.Distance.revealOffset : 0)
            .modifier(RevealBlur(radius: moves && style == .focus ? Motion.Distance.focusBlur : 0, enabled: style == .focus))
            .onAppear(perform: appear)
    }

    private var hiddenScale: CGFloat {
        switch style {
        case .rise: Motion.Distance.revealScale
        case .focus: Motion.Distance.focusScale
        case .pop: 0.6
        case .fade: 1
        }
    }

    private func appear() {
        guard !isShown else { return }
        scope?.begin()
        if scope?.isSettled == true {
            isShown = true    // late content: no entrance of its own
            return
        }
        let animation = reduceMotion ? Motion.crossfade : style.animation
        withAnimation(animation.delay(delay)) { isShown = true }
    }
}

/// Blur only for the focus style – a `blur(radius: 0)` still costs an offscreen pass on some content.
private struct RevealBlur: ViewModifier {
    let radius: CGFloat
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.blur(radius: radius)
        } else {
            content
        }
    }
}
