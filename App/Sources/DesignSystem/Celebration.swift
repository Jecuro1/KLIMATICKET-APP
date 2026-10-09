import SwiftUI

/// Lightweight confetti burst (Canvas + TimelineView), no assets. Disabled with Reduce Motion.
/// Removes its timeline once the last piece has landed – a display-rate TimelineView would otherwise keep redrawing an
/// empty full-screen canvas (and the material/glass above it) for as long as the view stays up.
struct ConfettiView: View {
    var colors: [Color]
    var count: Int = 90
    var duration: Double = 2.6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private struct Piece {
        let x: Double, delay: Double, speed: Double, drift: Double, spin: Double, size: Double, color: Int, shape: Int
    }

    @State private var pieces: [Piece] = []
    @State private var finished = false

    /// Pieces start up to 0.5 s late (see `onAppear`).
    private static let maxDelay = 0.5

    var body: some View {
        if reduceMotion || finished {
            Color.clear
        } else {
            TimelineView(.animation) { timeline in
                Canvas { ctx, size in
                    let t = timeline.date.timeIntervalSince(start)
                    for p in pieces {
                        let local = t - p.delay
                        guard local > 0, local < duration else { continue }
                        let progress = local / duration
                        let y = -20 + (size.height + 40) * (local * p.speed / duration) + 120 * progress * progress
                        let x = p.x * size.width + sin(local * 2.4 + p.drift * 6) * 28 * p.drift
                        let opacity = progress > 0.75 ? (1 - progress) / 0.25 : 1
                        var c = ctx
                        c.opacity = opacity
                        c.translateBy(x: x, y: y)
                        c.rotate(by: .radians(local * p.spin))
                        let rect = CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.shape == 0 ? p.size / 2 : p.size)
                        let path = p.shape == 2 ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.5)
                        c.fill(path, with: .color(colors[p.color % max(colors.count, 1)]))
                    }
                }
            }
            .allowsHitTesting(false)
            .task {
                // Cancelled with the view (an overlay dismissed early); the margin covers the last frame.
                try? await Task.sleep(for: .seconds(duration + Self.maxDelay + 0.1))
                if !Task.isCancelled { finished = true }
            }
            .onAppear {
                start = Date()
                var g = SystemRandomNumberGenerator()
                pieces = (0..<count).map { _ in
                    Piece(x: .random(in: 0...1, using: &g), delay: .random(in: 0...Self.maxDelay, using: &g),
                          speed: .random(in: 0.7...1.25, using: &g), drift: .random(in: 0.3...1, using: &g),
                          spin: .random(in: -7...7, using: &g), size: .random(in: 6...11, using: &g),
                          color: .random(in: 0..<max(colors.count, 1), using: &g), shape: .random(in: 0...2, using: &g))
                }
            }
        }
    }
}

/// Full-screen "Rentiert!" moment shown once per ticket when it pays off (and after a trip crosses break-even).
/// Motion (docs/MOTION.md §11): the card springs in, the seal pops with a ring and a burst, the profit counts up –
/// all within ~1 s; tapping anywhere skips it. Reduce Motion: cross-fade, no confetti, no ring or burst.
struct BreakEvenCelebration: View {
    var ticketName: String
    var profit: Double
    var onDismiss: () -> Void

    @State private var appear = MotionPolicy.isStatic
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                .onTapGesture { onDismiss() }
            ConfettiView(colors: Theme.celebrationColors)
                .ignoresSafeArea()
            VStack(spacing: Theme.Spacing.m) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 76, weight: .semibold))
                    // White check (palette): the glow behind would otherwise tint the see-through checkmark.
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Theme.positive.gradient)
                    .background {
                        // Static glow (no animation cost): the seal sits in light.
                        Circle()
                            .fill(RadialGradient(colors: [Theme.positive.opacity(0.32), Theme.positive.opacity(0)],
                                                 center: .center, startRadius: 6, endRadius: 96))
                            .frame(width: 192, height: 192)
                            .accessibilityHidden(true)
                    }
                    .celebrate(trigger: appear, haptic: nil)
                    .celebrationRing(trigger: appear, color: Theme.positive)
                    .celebrationBurst(trigger: appear)
                Text("Rentiert!")
                    .font(Theme.Typography.heroTitle)
                    .reveal(.focus, delay: 0.12)
                Text("Dein \(ticketName) hat sich bezahlt gemacht. Ab jetzt ist jede Fahrt reiner Gewinn.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .reveal(order: 1, delay: 0.12)
                if profit > 0 {
                    CountUpText(value: profit, delay: 0.3) { "+ " + Format.euro($0) }
                        .font(Theme.Typography.numberLarge)
                        .foregroundStyle(Theme.positiveText)
                        .reveal(order: 2, delay: 0.12)
                }
                Button("Weiter so") { onDismiss() }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.prominentTint)
                    .controlSize(.large)
                    .padding(.top, Theme.Spacing.s)
                    .reveal(order: 3, delay: 0.12)
            }
            .padding(Theme.Spacing.xl)
            .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.sheet))
            .padding(Theme.Spacing.l)
            .scaleEffect(appear || reduceMotion ? 1 : 0.85)
            .opacity(appear ? 1 : 0)
        }
        .haptic(.success, trigger: appear, when: { old, new in !old && new })
        .onAppear {
            guard !appear else { return }
            withMotion(Motion.bouncy) { appear = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { onDismiss() }
    }
}
