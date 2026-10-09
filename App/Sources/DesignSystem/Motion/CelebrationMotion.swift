import SwiftUI

// Celebrations (docs/MOTION.md §11): short (≤ 0.8 s for these, ≤ Motion.Duration.celebration for full-screen moments),
// never blocking, triggered by a value change, Reduce-Motion aware. Full-screen: `BreakEvenCelebration`.

extension View {
    /// Pops, wiggles and lifts once whenever `trigger` changes – a milestone reached, an achievement unlocked, a
    /// favourite logged. Plays `haptic` with it (nil: none). Reduce Motion: a soft brightness flash, nothing moves.
    ///
    ///     MedalView(achievement).celebrate(trigger: achievement.isUnlocked)
    func celebrate<T: Equatable>(trigger: T, haptic: Haptic? = .milestone) -> some View {
        modifier(CelebrateModifier(trigger: trigger, haptic: haptic))
    }

    /// A ring that expands and fades from the view's bounds when `trigger` changes (medallions, round buttons).
    func celebrationRing<T: Equatable>(trigger: T, color: Color = Theme.gold) -> some View {
        overlay { CelebrationRing(trigger: trigger, color: color) }
    }

    /// A burst of small confetti dots from the view's centre when `trigger` changes (favourite starred, trip logged).
    func celebrationBurst<T: Equatable>(trigger: T, colors: [Color] = Theme.celebrationColors) -> some View {
        overlay { CelebrationBurst(trigger: trigger, colors: colors) }
    }
}

private struct PopValues {
    var scale: CGFloat = 1
    var angle: Double = 0
    var lift: CGFloat = 0
    var flash: Double = 0
}

private struct CelebrateModifier<T: Equatable>: ViewModifier {
    let trigger: T
    let haptic: Haptic?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: PopValues(), trigger: trigger) { [reduceMotion] view, value in
                view
                    .scaleEffect(reduceMotion ? 1 : value.scale)
                    .rotationEffect(.degrees(reduceMotion ? 0 : value.angle))
                    .offset(y: reduceMotion ? 0 : value.lift)
                    .brightness(value.flash)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    SpringKeyframe(1.18, duration: 0.16, spring: Motion.Springs.snappy)
                    SpringKeyframe(1, duration: 0.5, spring: Motion.Springs.bouncy)
                }
                KeyframeTrack(\.angle) {
                    CubicKeyframe(-7, duration: 0.09)
                    CubicKeyframe(6, duration: 0.11)
                    CubicKeyframe(-3, duration: 0.1)
                    CubicKeyframe(0, duration: 0.12)
                }
                KeyframeTrack(\.lift) {
                    CubicKeyframe(-10, duration: 0.16)
                    SpringKeyframe(0, duration: 0.45, spring: Motion.Springs.bouncy)
                }
                KeyframeTrack(\.flash) {
                    LinearKeyframe(0.16, duration: 0.1)
                    LinearKeyframe(0, duration: 0.45)
                }
            }
            .if(haptic != nil) { $0.haptic(haptic ?? .milestone, trigger: trigger) }
    }
}

private struct RingValues {
    var scale: CGFloat = 1
    var opacity: Double = 0
}

private struct CelebrationRing<T: Equatable>: View {
    let trigger: T
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !reduceMotion && !MotionPolicy.isStatic {
            Circle()
                .strokeBorder(color, lineWidth: 3)
                .keyframeAnimator(initialValue: RingValues(), trigger: trigger) { ring, value in
                    ring.scaleEffect(value.scale).opacity(value.opacity)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        LinearKeyframe(0.8, duration: 0.01)
                        CubicKeyframe(1.75, duration: 0.65)
                    }
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(0.9, duration: 0.01)
                        CubicKeyframe(0, duration: 0.65)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct BurstValues {
    var progress: Double = 0
    var opacity: Double = 0
}

private struct CelebrationBurst<T: Equatable>: View {
    let trigger: T
    let colors: [Color]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Fixed directions and sizes (no randomness per frame, nothing allocated while animating).
    private static var dots: [(angle: Double, distance: Double, size: Double)] {
        (0..<12).map { i in
            (angle: Double(i) / 12 * 2 * .pi + (i.isMultiple(of: 2) ? 0 : 0.18),
             distance: i.isMultiple(of: 2) ? 1 : 0.72,
             size: i.isMultiple(of: 3) ? 6 : 4.5)
        }
    }

    var body: some View {
        if !reduceMotion && !MotionPolicy.isStatic {
            let dots = Self.dots
            let colors = colors
            let overflow: CGFloat = 36
            Color.clear
                .keyframeAnimator(initialValue: BurstValues(), trigger: trigger) { view, value in
                    view.overlay {
                        Canvas { context, size in
                            guard value.opacity > 0 else { return }
                            let center = CGPoint(x: size.width / 2, y: size.height / 2)
                            // The canvas reaches `overflow` beyond the view on every side (dots fly past its edge).
                            let reach = max(size.width, size.height) * 0.5 - overflow + 20
                            for (index, dot) in dots.enumerated() {
                                let r = reach * dot.distance * value.progress
                                let point = CGPoint(x: center.x + cos(dot.angle) * r, y: center.y + sin(dot.angle) * r)
                                let d = dot.size * (1 - 0.4 * value.progress)
                                context.opacity = value.opacity
                                context.fill(Path(ellipseIn: CGRect(x: point.x - d / 2, y: point.y - d / 2, width: d, height: d)),
                                             with: .color(colors.isEmpty ? .accentColor : colors[index % colors.count]))
                            }
                        }
                        .padding(-overflow)
                    }
                } keyframes: { _ in
                    KeyframeTrack(\.progress) {
                        LinearKeyframe(0.15, duration: 0.01)
                        CubicKeyframe(1, duration: 0.55)
                    }
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(1, duration: 0.01)
                        LinearKeyframe(1, duration: 0.3)
                        CubicKeyframe(0, duration: 0.3)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
