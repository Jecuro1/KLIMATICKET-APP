import SwiftUI

extension EnvironmentValues {
    /// True while a sheet covers the screen (set by RootView): every sky underneath – and the one inside the sheet,
    /// which inherits the value – stops drifting, so only the visible content composites (DESIGN.md §2: sheets „ruhig“).
    @Entry var ambientSkyPaused: Bool = false
}

/// The living alpine sky behind every screen: a 3×6 MeshGradient – "Morgendämmerung" (light) and
/// "Blaue Stunde" (dark, with stars) – plus a sun-glow behind the summit. Interior points drift slowly
/// (±0.035 on 18 s / 23 s sine periods); static with Reduce Motion, opaque with Reduce Transparency.
///
/// Cost: the drift is below 1 pt per 0.2 s, so the sky redraws at 5 Hz (not at display rate) and pauses while the
/// scene is not active or a sheet covers it (`ambientSkyPaused`). Every material and glass layer above samples this
/// backdrop, so an idle screen with a paused sky composites nothing at all.
struct AmbientBackground: View {
    enum Style { case standard, onboarding }

    var style: Style = .standard
    /// 0…1 – the summit glow brightens as break-even approaches.
    var glow: Double = 0.7
    var intensity: Double = 1
    /// false = a calm, static sky (e.g. a backdrop inside a sheet).
    var animated: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.ambientSkyPaused) private var externallyPaused
    @State private var clock = SkyClock()

    /// Interval between two drift steps (5 Hz): visually identical to display rate for this slow, soft motion.
    private static let tick: Double = 1.0 / 5.0

    var body: some View {
        Group {
            if reduceTransparency {
                Theme.background
            } else if reduceMotion || LaunchMode.isScreenshot || !animated {
                sky(t: 4)
            } else {
                animatedSky
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onChange(of: isPaused, initial: true) { _, paused in clock.setPaused(paused) }
    }

    private var isPaused: Bool { scenePhase != .active || externallyPaused }

    private var isDark: Bool { colorScheme == .dark || style == .onboarding }

    /// One timeline drives mesh and stars together (one composite per step). `paused:` freezes the schedule in place
    /// (no jump to the static pose), and `SkyClock` resumes the drift where it stopped, not at the wall-clock position.
    private var animatedSky: some View {
        TimelineView(.animation(minimumInterval: Self.tick, paused: isPaused)) { context in
            sky(t: clock.time(at: context.date))
        }
    }

    private func sky(t: Double) -> some View {
        ZStack {
            MeshGradient(width: 3, height: 6, points: points(t: t), colors: palette, smoothsColors: true, colorSpace: .perceptual)
            // Its own view with plain inputs: SwiftUI skips it on every drift step.
            SunGlow(glow: glow, isDark: isDark)
            if isDark { StarField(seed: 7, count: starCount, t: reduceMotion ? 0 : t) }
        }
    }

    private var starCount: Int { style == .onboarding ? 90 : 55 }

    private func points(t: Double) -> [SIMD2<Float>] {
        let a = Float(sin(t * 2 * .pi / 18) * 0.035 * intensity)
        let b = Float(cos(t * 2 * .pi / 23) * 0.035 * intensity)
        var pts: [SIMD2<Float>] = []
        pts.reserveCapacity(18)
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
        switch (style, colorScheme == .dark) {
        case (.onboarding, _): Self.onboardingPalette
        case (.standard, true): Self.darkPalette
        case (.standard, false): Self.lightPalette
        }
    }

    // Parsed once (not on every drift step).
    private static let onboardingPalette: [Color] = [
        "#050B19", "#070F22", "#0A142B", "#0B1B3A", "#13234C", "#1A2452", "#14295A", "#2C2F6A", "#59406E",
        "#0F2246", "#18295A", "#26305C", "#0A1733", "#0C1A3A", "#0D1A38", "#060F24", "#07112A", "#060E22",
    ].map(Color.init(hex:))
    private static let darkPalette: [Color] = [
        "#060D1C", "#081124", "#0B162E", "#0E2245", "#1E2B5C", "#2B2C5E", "#18315E", "#3A3B74", "#7A4C6E",
        "#0E2244", "#142A50", "#1A2C52", "#0A1832", "#0B1A36", "#0B1832", "#07122A", "#081329", "#070F24",
    ].map(Color.init(hex:))
    private static let lightPalette: [Color] = [
        "#93BCE4", "#A6C8EA", "#B8CDEE", "#BCD3EE", "#CDD7F0", "#DCD6EE", "#DCE2F2", "#F1D9D2", "#F8CDB6",
        "#E2E8F2", "#EBE6EE", "#EFE4E6", "#E4EAF2", "#E7ECF3", "#E5EAF2", "#DEE6EF", "#E2E8F0", "#DCE4EE",
    ].map(Color.init(hex:))
}

/// The blurred sun glow behind the summit (static; brightens with `glow`).
private struct SunGlow: View {
    var glow: Double
    var isDark: Bool

    private static let warmDark = Color(hex: "#FF9682")
    private static let warmLight = Color(hex: "#FFC4A0")
    private static let violet = Color(hex: "#966EC8")

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Ellipse()
                    .fill(RadialGradient(colors: [isDark ? Self.warmDark.opacity(0.42 * glow) : Self.warmLight.opacity(0.75 * glow), .clear],
                                         center: .center, startRadius: 0, endRadius: w * 0.42))
                    .frame(width: w * 0.62, height: w * 0.46)
                    .position(x: w * 0.67, y: h * 0.41)
                if isDark {
                    Ellipse()
                        .fill(RadialGradient(colors: [Self.violet.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: w * 0.6))
                        .frame(width: w * 1.05, height: w * 0.65)
                        .position(x: w * 0.75, y: h * 0.46)
                }
            }
            .blur(radius: 20)
        }
        .allowsHitTesting(false)
    }
}

/// Animation time of one sky that stands still while it is paused: resuming continues the drift from the paused
/// pose instead of jumping (up to ~25 pt) to the wall-clock position. Main-thread only (view body / onChange).
private final class SkyClock {
    private var offset: TimeInterval = 0
    private var pausedAt: TimeInterval?

    func time(at date: Date) -> Double {
        (pausedAt ?? date.timeIntervalSinceReferenceDate) - offset
    }

    func setPaused(_ paused: Bool, now: Date = Date()) {
        let t = now.timeIntervalSinceReferenceDate
        if paused {
            if pausedAt == nil { pausedAt = t }
        } else if let p = pausedAt {
            offset += t - p
            pausedAt = nil
        }
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
