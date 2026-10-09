import SwiftUI

/// Lightweight confetti burst (Canvas + TimelineView), no assets. Disabled with Reduce Motion.
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

    var body: some View {
        if reduceMotion {
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
            .onAppear {
                start = Date()
                var g = SystemRandomNumberGenerator()
                pieces = (0..<count).map { _ in
                    Piece(x: .random(in: 0...1, using: &g), delay: .random(in: 0...0.5, using: &g),
                          speed: .random(in: 0.7...1.25, using: &g), drift: .random(in: 0.3...1, using: &g),
                          spin: .random(in: -7...7, using: &g), size: .random(in: 6...11, using: &g),
                          color: .random(in: 0..<max(colors.count, 1), using: &g), shape: .random(in: 0...2, using: &g))
                }
            }
        }
    }
}

/// Full-screen "Rentiert!" moment shown once per ticket when it pays off (and after a trip crosses break-even).
struct BreakEvenCelebration: View {
    var ticketName: String
    var profit: Double
    var onDismiss: () -> Void

    @State private var appear = false

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                .onTapGesture { onDismiss() }
            ConfettiView(colors: Theme.celebrationColors)
                .ignoresSafeArea()
            VStack(spacing: Theme.Spacing.m) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 76, weight: .semibold))
                    .foregroundStyle(Theme.positive.gradient)
                    .symbolEffect(.bounce, value: appear)
                Text("Rentiert!")
                    .font(Theme.Typography.heroTitle)
                Text("Dein \(ticketName) hat sich bezahlt gemacht. Ab jetzt ist jede Fahrt reiner Gewinn.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                if profit > 0 {
                    Text("+ \(Format.euro(profit))")
                        .font(Theme.Typography.numberLarge)
                        .foregroundStyle(Theme.positive)
                        .contentTransition(.numericText(value: profit))
                }
                Button("Weiter so") { onDismiss() }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .padding(.top, Theme.Spacing.s)
            }
            .padding(Theme.Spacing.xl)
            .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.sheet))
            .padding(Theme.Spacing.l)
            .scaleEffect(appear ? 1 : 0.85)
            .opacity(appear ? 1 : 0)
        }
        .sensoryFeedback(.success, trigger: appear)
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.35)) { appear = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}
