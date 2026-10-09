import SwiftUI

/// The living alpine sky behind every screen: a 3×6 MeshGradient – "Morgendämmerung" (light) and
/// "Blaue Stunde" (dark, with stars) – plus a sun-glow behind the summit. Interior points drift slowly
/// (±0.035 on 18 s / 23 s sine periods); static with Reduce Motion, opaque with Reduce Transparency.
struct AmbientBackground: View {
    enum Style { case standard, onboarding }

    var style: Style = .standard
    /// 0…1 – the summit glow brightens as break-even approaches.
    var glow: Double = 0.7
    var intensity: Double = 1

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                Theme.background
            } else if reduceMotion || LaunchMode.isScreenshot {
                sky(t: 4)
            } else {
                TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { context in
                    sky(t: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var isDark: Bool { colorScheme == .dark || style == .onboarding }

    private func sky(t: Double) -> some View {
        ZStack {
            MeshGradient(width: 3, height: 6, points: points(t: t), colors: palette, smoothsColors: true, colorSpace: .perceptual)
            sunGlow
            if isDark { StarField(seed: 7, count: style == .onboarding ? 90 : 55, t: reduceMotion ? 0 : t) }
        }
    }

    private func points(t: Double) -> [SIMD2<Float>] {
        let a = Float(sin(t * 2 * .pi / 18) * 0.035 * intensity)
        let b = Float(cos(t * 2 * .pi / 23) * 0.035 * intensity)
        var pts: [SIMD2<Float>] = []
        for row in 0..<6 {
            for col in 0..<3 {
                var x = Float(col) / 2
                var y = Float(row) / 5
                if col == 1 && row > 0 && row < 5 {
                    x += (row % 2 == 0 ? a : b)
                    y += (row % 2 == 0 ? b : -a) * 0.6
                }
                pts.append([x, y])
            }
        }
        return pts
    }

    private var palette: [Color] {
        let hex: [String]
        switch (style, colorScheme == .dark) {
        case (.onboarding, _):
            hex = ["#050B19", "#070F22", "#0A142B", "#0B1B3A", "#13234C", "#1A2452", "#14295A", "#2C2F6A", "#59406E",
                   "#0F2246", "#18295A", "#26305C", "#0A1733", "#0C1A3A", "#0D1A38", "#060F24", "#07112A", "#060E22"]
        case (.standard, true):
            hex = ["#060D1C", "#081124", "#0B162E", "#0E2245", "#1E2B5C", "#2B2C5E", "#18315E", "#3A3B74", "#7A4C6E",
                   "#0E2244", "#142A50", "#1A2C52", "#0A1832", "#0B1A36", "#0B1832", "#07122A", "#081329", "#070F24"]
        case (.standard, false):
            hex = ["#93BCE4", "#A6C8EA", "#B8CDEE", "#BCD3EE", "#CDD7F0", "#DCD6EE", "#DCE2F2", "#F1D9D2", "#F8CDB6",
                   "#E2E8F2", "#EBE6EE", "#EFE4E6", "#E4EAF2", "#E7ECF3", "#E5EAF2", "#DEE6EF", "#E2E8F0", "#DCE4EE"]
        }
        return hex.map(Color.init(hex:))
    }

    private var sunGlow: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Ellipse()
                    .fill(RadialGradient(colors: [isDark ? Color(hex: "#FF9682").opacity(0.42 * glow) : Color(hex: "#FFC4A0").opacity(0.75 * glow), .clear],
                                         center: .center, startRadius: 0, endRadius: w * 0.42))
                    .frame(width: w * 0.62, height: w * 0.46)
                    .position(x: w * 0.67, y: h * 0.41)
                if isDark {
                    Ellipse()
                        .fill(RadialGradient(colors: [Color(hex: "#966EC8").opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: w * 0.6))
                        .frame(width: w * 1.05, height: w * 0.65)
                        .position(x: w * 0.75, y: h * 0.46)
                }
            }
            .blur(radius: 20)
        }
        .allowsHitTesting(false)
    }
}

/// Sparse twinkling star field (dark skies), fading towards the horizon.
struct StarField: View {
    var seed: UInt64
    var count: Int
    var t: Double

    var body: some View {
        Canvas { ctx, size in
            var rng = SeededGenerator(seed: seed)
            for i in 0..<count {
                let x = Double.random(in: 0...1, using: &rng) * size.width
                let yUnit = pow(Double.random(in: 0...1, using: &rng), 1.6) * 0.55
                let r = Double.random(in: 0.55...1.1, using: &rng)
                let base = Double.random(in: 0.25...0.85, using: &rng)
                let phase = Double.random(in: 3...6, using: &rng)
                let twinkle = t == 0 ? 1 : 0.8 + 0.2 * sin(t * 2 * .pi / phase + Double(i))
                let fade = 1 - yUnit / 0.55 * 0.6
                ctx.opacity = base * twinkle * fade
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: yUnit * size.height, width: r * 2, height: r * 2)), with: .color(.white))
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Places the ambient alpine sky behind a scrollable screen.
    func ambientBackground(_ style: AmbientBackground.Style = .standard, glow: Double = 0.7) -> some View {
        background { AmbientBackground(style: style, glow: glow) }
    }
}
