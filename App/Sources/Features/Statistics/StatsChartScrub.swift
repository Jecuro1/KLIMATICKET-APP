import SwiftUI
import Charts

/// Scrubbing state of a time chart, kept out of the chart's own view state.
///
/// `.chartXSelection` writes a new date on every touch-move frame. Held in `@State` of the card, every frame re-ran the
/// card's body and rebuilt the whole Chart (hundreds of marks, the profit wedge, the callout material) – the marker
/// lagged behind the finger. Here Charts writes through `binding`, whose getter reads an untracked copy, and only the
/// small views that read `date` (`StatsScrubLayer`) or `isActive` (`StatsScrubFade`, flips at begin/end only) update.
@Observable
@MainActor
final class StatsChartScrub {
    /// The date under the finger – read it only in small overlay views.
    private(set) var date: Date?
    /// A scrub is in progress (annotations step aside for the callout).
    private(set) var isActive = false
    /// Same value without observation – what Charts reads back through the binding.
    @ObservationIgnored private var current: Date?

    /// Binding for `.chartXSelection(value:)`. Reading it never subscribes the chart to scrub updates.
    var binding: Binding<Date?> {
        Binding(get: { self.current }, set: { self.update($0) })
    }

    func update(_ value: Date?) {
        current = value
        if date != value { date = value }
        if isActive != (value != nil) {
            isActive = value != nil
            // The hidden gesture was found: the "Fahr mit dem Finger drüber" tip never shows again.
            if isActive, !Self.retiredTip {
                Self.retiredTip = true
                KBTips.used(KBTips.ChartScrub())
            }
        }
    }

    /// Once per launch is enough – invalidating a tip writes to the TipKit store.
    private static var retiredTip = false
}

/// Fades its content out while a scrub is in progress. Only this view re-renders when the scrub starts or ends –
/// not the chart that hosts it in an annotation.
struct StatsScrubFade<Content: View>: View {
    let scrub: StatsChartScrub
    var opacity: Double = 1
    @ViewBuilder var content: Content

    var body: some View {
        content
            .opacity(scrub.isActive ? 0 : opacity)
            .motionAnimation(Motion.snappy, value: scrub.isActive)
    }
}

/// Selection rule, marker and callout of a scrubbed time chart, drawn over the chart (`.chartOverlay`) from the
/// `ChartProxy`. The only view that re-renders per frame while the finger moves.
struct StatsScrubLayer<Callout: View>: View {
    let proxy: ChartProxy
    let scrub: StatsChartScrub
    /// Marker value (already scaled like the plotted series) at a date; nil hides the marker.
    let value: (Date) -> Double?
    let markerColor: Color
    let hapticsEnabled: Bool
    @ViewBuilder let callout: (Date, Double) -> Callout

    var body: some View {
        GeometryReader { geometry in
            if let date = scrub.date, let anchor = proxy.plotFrame,
               let marker = value(date), let x = proxy.position(forX: date), let y = proxy.position(forY: marker) {
                let plot = geometry[anchor]
                let px = plot.minX + x
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(LinearGradient(colors: [Theme.textSecondary.opacity(0.15), Theme.textSecondary.opacity(0.6)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 1, height: plot.height)
                        .position(x: px, y: plot.midY)
                    // Marker with a soft halo, so it reads as "the finger is here" on the line.
                    Circle()
                        .fill(markerColor)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(Theme.onAccent, lineWidth: 2))
                        .background(Circle().fill(markerColor.opacity(0.22)).frame(width: 26, height: 26))
                        .position(x: px, y: plot.minY + y)
                    StatsCalloutPlacement(x: px, top: plot.minY) {
                        callout(date, marker)
                    }
                }
                // Pops in where the finger lands and fades away on lift-off (begin/end only – never per frame).
                .transition(.scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
            }
        }
        .motionAnimation(Motion.snappy, value: scrub.isActive)
        .allowsHitTesting(false)
        // The chart itself carries the spoken summary; the callout only exists under a scrubbing finger.
        .accessibilityHidden(true)
        .sensoryFeedback(.selection, trigger: selectedDay) { _, new in new != nil && hapticsEnabled && !MotionPolicy.isStatic }
    }

    /// One tick per day crossed, not per frame.
    private var selectedDay: Date? {
        scrub.date.map { Calendar.vienna.startOfDay(for: $0) }
    }
}

/// Puts the callout above the plot, centred on the selection and kept inside the chart's width
/// (like an annotation with `.fit(to: .chart)`).
private struct StatsCalloutPlacement: Layout {
    var x: CGFloat
    var top: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let view = subviews.first else { return }
        let size = view.sizeThatFits(.unspecified)
        let half = size.width / 2
        let centre = min(max(x, half), max(half, bounds.width - half))
        view.place(at: CGPoint(x: bounds.minX + centre, y: bounds.minY + top), anchor: .bottom, proposal: ProposedViewSize(size))
    }
}

extension View {
    /// Opaque callout surface for scrubbing – no material or shadow, it is redrawn every frame.
    func statsCalloutSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return background(Theme.sheetBackground.opacity(0.96), in: shape)
            .overlay(shape.strokeBorder(Theme.separator, lineWidth: 1))
    }
}
