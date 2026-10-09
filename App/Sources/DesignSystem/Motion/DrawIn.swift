import SwiftUI

// MARK: dashboardTicket – charts and progress that draw once when they first scroll into view (docs/MOTION.md §15:
// "Charts zeichnen einmal"). Additive to the motion system; used by the Übersicht and the Ticket tab.

/// Hands its content `isDrawn`: false until the view first shows at least `threshold` of itself inside its scroll view,
/// then true for good (animated with `animation`). Bars grow, rings and rails fill when the user gets to them – not at
/// launch below the fold, and never again on refreshes or when scrolled back.
/// Reduce Motion and screenshot mode: drawn from the start (no movement).
///
///     DrawInReader { isDrawn in
///         ForEach(bars) { bar in Capsule().scaleEffect(y: isDrawn ? 1 : 0.02, anchor: .bottom) }
///     }
struct DrawInReader<Content: View>: View {
    var threshold: Double = 0.4
    var animation: Animation = Motion.gentle
    @ViewBuilder var content: (Bool) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrawn = MotionPolicy.isStatic

    init(threshold: Double = 0.4, animation: Animation = Motion.gentle, @ViewBuilder content: @escaping (Bool) -> Content) {
        self.threshold = threshold
        self.animation = animation
        self.content = content
    }

    var body: some View {
        content(isDrawn || reduceMotion)
            .onScrollVisibilityChange(threshold: threshold) { visible in
                guard visible, !isDrawn else { return }
                if reduceMotion {
                    isDrawn = true
                } else {
                    withMotion(animation) { isDrawn = true }
                }
            }
    }
}
