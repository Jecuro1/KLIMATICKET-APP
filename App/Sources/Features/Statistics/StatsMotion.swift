import SwiftUI

// Motion helpers of the statistics area (Statistik, Gipfelbuch, Arbeit & Steuer, Öffis vs. Auto) on top of the motion
// system (docs/MOTION.md): charts that grow once when they come into view, the condensing screen header and the zoom
// IDs of the cards that open a detail.

/// Charts and rails of a card grow from zero once – when the card first comes into view, so cards further down still
/// grow when the user scrolls to them (and not unseen at launch). `Motion.gentle`; the first cards wait for their reveal
/// (`delay`), anything that arrives after the screen's entrance grows at once. Reduce Motion / screenshots: full values.
///
///     StatsGrowOnView(delay: Motion.Stagger.delay(2)) { grow in StatsMonthlyCard(snapshot: snapshot, grow: grow) }
struct StatsGrowOnView<Content: View>: View {
    var delay: Double = 0
    @ViewBuilder var content: (Double) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.revealScope) private var revealScope
    @State private var grow: Double = MotionPolicy.isStatic ? 1 : 0

    init(delay: Double = 0, @ViewBuilder content: @escaping (Double) -> Content) {
        self.delay = delay
        self.content = content
    }

    var body: some View {
        content(reduceMotion ? 1 : grow)
            // A Bool that flips once per scroll pass in or out – the transform runs per frame, the action does not.
            .onGeometryChange(for: Bool.self) { proxy in
                StatsVisibility.isInView(proxy)
            } action: { isInView in
                guard isInView, grow < 1 else { return }
                if reduceMotion {
                    grow = 1
                } else {
                    let wait = revealScope?.isSettled == true ? 0 : delay
                    withAnimation(Motion.gentle.delay(wait)) { grow = 1 }
                }
            }
    }
}

enum StatsVisibility {
    /// At least a third of the view (or 140 pt of a tall one) inside the nearest scroll view; outside one: visible.
    nonisolated static func isInView(_ proxy: GeometryProxy) -> Bool {
        guard let viewport = proxy.bounds(of: .scrollView) else { return true }
        let visible = CGRect(origin: .zero, size: proxy.size).intersection(viewport)
        guard !visible.isNull else { return false }
        return visible.height >= min(proxy.size.height / 3, 140)
    }
}

extension View {
    /// The large screen title condenses as the screen scrolls: it shrinks a little towards its leading edge and fades
    /// out while the inline toolbar title fades in (`StatsInlineTitle`). Reads `condense` – keep it on a small view.
    /// Reduce Motion: fade only.
    func statsHeaderCondense(_ condense: ScrollCondense) -> some View {
        modifier(StatsHeaderCondenseModifier(condense: condense))
    }
}

private struct StatsHeaderCondenseModifier: ViewModifier {
    let condense: ScrollCondense
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let p = condense.value
        content
            .scaleEffect(reduceMotion ? 1 : 1 - 0.06 * p, anchor: .bottomLeading)
            .opacity(1 - Double(p))
    }
}

/// The inline navigation title: fades in as the large header condenses (scroll-driven, no state per frame in the
/// screen itself – only this view reads the progress).
struct StatsInlineTitle: View {
    let title: String
    let condense: ScrollCondense

    var body: some View {
        let p = condense.value
        Text(title)
            .font(.headline)
            .foregroundStyle(Theme.textPrimary)
            .opacity(Double(max(0, p - 0.4) / 0.6))
            .accessibilityHidden(p < 0.5)
    }
}

/// Zoom-transition IDs of the statistics cards that open a screen or sheet (docs/MOTION.md §9).
enum StatsZoomID {
    static let summitBook = "stats.gipfelbuch"
    static let atlas = "stats.atlas"
    static let car = "stats.car"
}
