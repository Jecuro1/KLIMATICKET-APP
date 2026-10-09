import SwiftUI

// Continuous motion (docs/MOTION.md §12): calm, looping effects – a breathing "live" symbol, a halo around the current
// position – run only while someone can see them: on screen (also inside scroll views), scene active, no app sheet
// over them (`ambientSkyPaused`), Reduce Motion off, never in screenshots. Everything else stops, so an idle screen
// renders nothing.

extension View {
    /// The SF Symbol breathes while it is visible (live ride, trip detection on, "neu"). Static otherwise.
    func breathing() -> some View {
        ContinuousMotionReader { isRunning in
            self.symbolEffect(.breathe, isActive: isRunning)
        }
    }

    /// A soft halo pulses out of the view while it is visible ("du bist hier", the climber on the summit route,
    /// a live departure). Drawn behind the view; nothing is drawn when it does not run.
    func pulsingHalo(_ color: Color = Theme.accent, scale: CGFloat = 1.9, period: Double = 2.4) -> some View {
        background {
            ContinuousMotionReader { isRunning in
                if isRunning {
                    PhaseAnimator([false, true]) { expanded in
                        Circle()
                            .fill(color.opacity(expanded ? 0 : 0.32))
                            .scaleEffect(expanded ? scale : 1)
                    } animation: { expanded in
                        expanded ? .easeOut(duration: period) : nil
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Tells its content whether a continuous effect may run right now (see the file comment). Use it for custom loops:
///
///     ContinuousMotionReader { isRunning in
///         Image(systemName: "dot.radiowaves.left.and.right").symbolEffect(.variableColor, isActive: isRunning)
///     }
struct ContinuousMotionReader<Content: View>: View {
    @ViewBuilder var content: (Bool) -> Content

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.ambientSkyPaused) private var coveredBySheet
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOnScreen = false
    @State private var isScrolledIntoView = true

    init(@ViewBuilder content: @escaping (Bool) -> Content) {
        self.content = content
    }

    private var isRunning: Bool {
        isOnScreen && isScrolledIntoView && scenePhase == .active && !coveredBySheet && !reduceMotion
            && !MotionPolicy.isStatic && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        content(isRunning)
            .onAppear { isOnScreen = true }
            .onDisappear { isOnScreen = false }
            // Plain (non-lazy) scroll views never call onDisappear for content scrolled out of view.
            .onScrollVisibilityChange(threshold: 0.05) { visible in
                if isScrolledIntoView != visible { isScrolledIntoView = visible }
            }
    }
}
