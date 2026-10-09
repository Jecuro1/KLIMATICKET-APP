import SwiftUI
import KlimaCore

/// Signature visual „Gipfelkurs“ (DESIGN_FINAL_SYNTHESIS §2 / §8.1, mockups `01-dashboard-*`): the value climbs a decorative
/// Alpine ridge towards the summit flag (= ticket price, break-even).
///
/// x = money: the climber's x is exactly proportional to the amortisation and the walked route is monotonic; the y axis is
/// decorative altitude. After the break-even the summit moves left and the route continues on the pine „Höhenweg“.
/// Layers: far + mid ridge, frosted front ridge with topo lines and a dawn rim, dotted trail to the summit, gradient route,
/// milestone dots (25 / 50 / 75 %), climber, flag, the summit tag and the „Heute · € 1.044“ glass pill.
struct SummitChart: View {
    var series: [CumulativePoint]
    var forecast: [CumulativePoint]
    var start: Date
    var end: Date
    var price: Double
    var breakEvenDate: Date?
    var isPaidOff: Bool
    var showsLabels: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// Animated amortisation the climber is drawn at (0 → progress on first appearance).
    @State private var climbed: Double = 0
    @State private var tagSize: CGSize = .zero

    private var value: Double { series.last?.value ?? 0 }
    private var progress: Double { price > 0 ? max(0, value / price) : 0 }

    /// End of the Höhenweg: the forecast at expiry (+ 2 %), at least 120 % so the climber never sits on the edge.
    private var pEnd: Double {
        let projected = price > 0 ? (forecast.last?.value ?? value) / price : 0
        return max(1.2, max(projected, progress) + 0.02)
    }

    /// The forecast does not reach the summit before the ticket expires → the trail turns dawn (spec §2 "behind").
    private var isBehind: Bool {
        guard !isPaidOff, value > 0 else { return false }
        guard let breakEvenDate else { return true }
        return breakEvenDate > end
    }

    private var crossingDate: Date? { series.first(where: { $0.value >= price })?.date }

    private var palette: SummitPalette {
        SummitPalette(dark: colorScheme == .dark, profit: isPaidOff, behind: isBehind, increasedContrast: contrast == .increased)
    }

    var body: some View {
        GeometryReader { proxy in
            let geometry = SummitGeometry(size: proxy.size, profit: isPaidOff, pEnd: pEnd)
            ZStack(alignment: .topLeading) {
                SummitRidges(geometry: geometry, palette: palette, reduceTransparency: reduceTransparency)
                SummitClimb(progress: climbed, target: progress, geometry: geometry, palette: palette,
                            showsPill: showsLabels, pillText: pillText)
                if showsLabels {
                    summitTag(geometry)
                }
            }
        }
        .onAppear {
            guard climbed != progress else { return }
            if reduceMotion || LaunchMode.isScreenshot {
                climbed = progress
            } else {
                withAnimation(.smooth(duration: 1.4).delay(0.15)) { climbed = progress }
            }
        }
        .onChange(of: progress) { _, newValue in
            if reduceMotion {
                climbed = newValue
            } else {
                withAnimation(.spring(duration: 0.6, bounce: 0.15)) { climbed = newValue }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gipfelkurs")
        .accessibilityValue(accessibilityText)
    }

    // MARK: Summit tag

    /// "BREAK-EVEN / € 1.400" right of the flag; mirrored (text left of the pole, right-aligned) when it would cross
    /// `width − 8` (spec §8.1.12). Profit: "GIPFEL ✓ / 14. Dez." always left of the flag.
    private func summitTag(_ g: SummitGeometry) -> some View {
        let fitsRight = g.sx + 19 + tagSize.width <= g.size.width - 8
        let mirrored = isPaidOff || !fitsRight
        let x = mirrored ? g.sx - 12 - tagSize.width : g.sx + 19
        return VStack(alignment: mirrored ? .trailing : .leading, spacing: 0) {
            Text(isPaidOff ? "GIPFEL ✓" : "BREAK-EVEN")
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(isPaidOff ? palette.goldText : palette.summitText)
            Text(tagValue)
                .font(.system(.callout, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .multilineTextAlignment(mirrored ? .trailing : .leading)
        .fixedSize()
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            tagSize = newSize
        }
        .offset(x: max(4, x), y: g.sy - 29)
        .opacity(tagSize == .zero ? 0 : 1)
        .accessibilityHidden(true)
    }

    private var tagValue: String {
        if isPaidOff, let crossingDate { return Format.dayMonth(crossingDate) }
        return SummitFigures.euro(price)
    }

    private var pillText: String {
        if isPaidOff {
            return "Heute · + " + SummitFigures.euro(SummitFigures.shownProfit(value: value, price: price))
        }
        return "Heute · " + SummitFigures.euro(SummitFigures.shownTotal(value: value, price: price, isPaidOff: false))
    }

    // MARK: Accessibility

    private var accessibilityText: String {
        var parts = ["\(Format.percent(progress)) amortisiert"]
        if isPaidOff {
            parts.append(crossingDate.map { "Gipfel erreicht am \(Format.dayMonth($0))" } ?? "Gipfel erreicht")
            parts.append("\(SummitFigures.euro(SummitFigures.shownProfit(value: value, price: price))) im Plus")
        } else {
            let remaining = SummitFigures.shownRemaining(value: value, price: price, isPaidOff: false)
            parts.append("Noch \(SummitFigures.euro(remaining)) bis zum Break-even")
            if let breakEvenDate, breakEvenDate <= end {
                parts.append("Prognose \(Format.dayMonth(breakEvenDate))")
            }
            if let next = SummitGeometry.milestones.first(where: { $0.fraction > progress }) {
                parts.append("Nächster Meilenstein: \(next.name), \(Int(next.fraction * 100)) Prozent")
            }
        }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Geometry

/// Port of `summit()` from the reference mockups (spec §8.1, reference height 134 pt; vertical offsets scale with the height).
private struct SummitGeometry {
    struct Milestone {
        let fraction: Double
        let name: String
    }

    static let milestones = [Milestone(fraction: 0.25, name: "Basislager"), Milestone(fraction: 0.5, name: "Halbzeit"),
                             Milestone(fraction: 0.75, name: "Gipfelgrat")]

    let size: CGSize
    let profit: Bool
    let pEnd: Double
    /// Vertical scale against the 134 pt reference canvas.
    let k: CGFloat
    let x0: CGFloat
    let sx: CGFloat
    let sy: CGFloat
    let xEnd: CGFloat
    /// Walkable path: the ascent (+ the Höhenweg when paid off).
    let route: [CGPoint]
    /// Front ridge crest: ascent + the descent / Höhenweg to the right edge.
    let outline: [CGPoint]
    let farRidge: [CGPoint]
    let midRidge: [CGPoint]

    // Ascent: nine segments alternating steep / gentle, all slopes > 0 → strictly rising.
    private static let widths: [CGFloat] = [1.1, 0.85, 1.15, 0.8, 1.1, 0.85, 1.05, 0.9, 1.0]
    private static let slopes: [CGFloat] = [1.45, 0.42, 1.35, 0.48, 1.4, 0.4, 1.3, 0.55, 1.6]

    // Background ridges: (fraction of the width, offset below the summit) – and points relative to the summit x.
    private static let farFixed: [(CGFloat, CGFloat)] = [(0.07, 32), (0.13, 42), (0.21, 12), (0.28, 24), (0.34, 16), (0.41, 34),
                                                         (0.49, 8), (0.55, 22), (0.62, -4), (0.93, 22)]
    private static let farNearSummit: [(CGFloat, CGFloat)] = [(0.04, -14), (0.12, 10), (0.18, 2)]
    private static let midFixed: [(CGFloat, CGFloat)] = [(0.06, 64), (0.12, 69), (0.2, 46), (0.26, 54), (0.33, 36), (0.39, 44),
                                                         (0.46, 24), (0.53, 38), (0.6, 18), (0.65, 26), (0.96, 34)]
    private static let midNearSummit: [(CGFloat, CGFloat)] = [(0.02, 4), (0.1, 26), (0.17, 16)]

    init(size: CGSize, profit: Bool, pEnd: Double) {
        let w = max(size.width, 1)
        let h = max(size.height, 1)
        let k = h / 134
        let kx = w / 402
        let x0: CGFloat = 0
        let sx = (profit ? 0.532 : 0.716) * w
        let sy = (profit ? 54 : 44) * k
        // Valley start a few points above the bottom edge, so the route stays clear of the card that overlaps the chart.
        let base = h - 5 * k
        let xEnd = w - 30 * kx

        var ascent = [CGPoint(x: x0 - 6, y: base)]
        var x = x0 - 6
        var y = base
        let widthSum = Self.widths.reduce(0, +)
        var drop: CGFloat = 0
        for index in Self.widths.indices { drop += Self.widths[index] * Self.slopes[index] }
        for index in Self.widths.indices {
            x += Self.widths[index] / widthSum * (sx - x0 + 6)
            y -= (base - sy) * (Self.widths[index] * Self.slopes[index]) / drop
            ascent.append(CGPoint(x: x, y: y))
        }
        ascent[ascent.count - 1] = CGPoint(x: sx, y: sy)

        var ridge: [CGPoint] = []
        if profit {
            let span = xEnd - sx
            ridge.append(CGPoint(x: sx + span * 0.22, y: sy + 7 * k))
            ridge.append(CGPoint(x: sx + span * 0.45, y: sy + 3 * k))
            ridge.append(CGPoint(x: sx + span * 0.70, y: sy + 9 * k))
            ridge.append(CGPoint(x: xEnd, y: sy + 5 * k))
            ridge.append(CGPoint(x: xEnd + 14 * kx, y: sy + 22 * k))
            ridge.append(CGPoint(x: w + 6, y: sy + 40 * k))
        } else {
            ridge.append(CGPoint(x: sx + 26 * kx, y: sy + 24 * k))
            ridge.append(CGPoint(x: sx + 46 * kx, y: sy + 19 * k))
            ridge.append(CGPoint(x: sx + 74 * kx, y: sy + 48 * k))
            ridge.append(CGPoint(x: sx + 100 * kx, y: sy + 42 * k))
            ridge.append(CGPoint(x: w + 6, y: sy + 74 * k))
        }

        var far: [CGPoint] = Self.farFixed.map { CGPoint(x: w * $0.0, y: sy + $0.1 * k) }
        far += Self.farNearSummit.map { CGPoint(x: sx + w * $0.0, y: sy + $0.1 * k) }
        far.sort { $0.x < $1.x }
        var mid: [CGPoint] = Self.midFixed.map { CGPoint(x: w * $0.0, y: sy + $0.1 * k) }
        mid += Self.midNearSummit.map { CGPoint(x: sx + w * $0.0, y: sy + $0.1 * k) }
        mid.sort { $0.x < $1.x }

        self.size = CGSize(width: w, height: h)
        self.profit = profit
        self.pEnd = max(pEnd, 1.01)
        self.k = k
        self.x0 = x0
        self.sx = sx
        self.sy = sy
        self.xEnd = xEnd
        self.route = profit ? ascent + Array(ridge.prefix(4)) : ascent
        self.outline = ascent + ridge
        self.farRidge = [CGPoint(x: x0 - 6, y: sy + 50 * k)] + far + [CGPoint(x: w + 6, y: sy + 8 * k)]
        self.midRidge = [CGPoint(x: x0 - 6, y: sy + 78 * k)] + mid + [CGPoint(x: w + 6, y: sy + 28 * k)]
    }

    /// Money → x: linear up to the summit, then along the Höhenweg up to `pEnd`.
    func x(for fraction: Double) -> CGFloat {
        let f = CGFloat(max(0, fraction))
        if f <= 1 || !profit { return x0 + min(f, 1) * (sx - x0) }
        let t = (f - 1) / CGFloat(max(pEnd - 1, 0.01))
        return sx + min(t, 1) * (xEnd - sx)
    }

    /// Altitude on the walkable route (linear between its points).
    func y(at x: CGFloat) -> CGFloat {
        guard let first = route.first, let last = route.last else { return size.height }
        if x <= first.x { return first.y }
        for index in 0..<(route.count - 1) {
            let a = route[index]
            let b = route[index + 1]
            if x >= a.x && x <= b.x {
                let t = b.x > a.x ? (x - a.x) / (b.x - a.x) : 0
                return a.y + (b.y - a.y) * t
            }
        }
        return last.y
    }

    /// Route from the valley to the climber.
    func walked(to point: CGPoint) -> [CGPoint] {
        route.filter { $0.x < point.x } + [point]
    }

    /// Dotted trail from the climber to the summit (none once the summit is passed).
    func ahead(from point: CGPoint) -> [CGPoint] {
        guard point.x < sx else { return [] }
        return [point] + route.filter { $0.x > point.x && $0.x <= sx }
    }

    /// Vertical fade of the background ridges (opaque → 90 % at ~35 % of the height → 0 at the bottom).
    var ridgeFadeStop: CGFloat {
        min(0.9, max(0.1, (-60 * k + 0.55 * (size.height + 60 * k)) / size.height))
    }
}

// MARK: - Palette

/// Colours of the reference implementation (light „Morgendämmerung“ / dark „Blaue Stunde“).
private struct SummitPalette {
    let dark: Bool
    let profit: Bool
    let far: Color
    let mid: Color
    let frontTop: Color
    let frontBottom: Color
    let rimPeak: Color
    let rimEdge: Color
    let topo: Color
    let trail: Color
    let routeStart: Color
    let routeMid: Color
    let routeEnd: Color
    let pine: Color
    let climberFill: Color
    let climberRing: Color
    let halo: Color
    let flag: Color
    let pole: Color
    let hut: Color
    /// Small key text on the summit glow: ≥ 4.5 : 1 on the peach sky (light) / the dark sky.
    let summitText: Color
    let goldText: Color
    let pillDot: Color

    init(dark: Bool, profit: Bool, behind: Bool, increasedContrast: Bool) {
        self.dark = dark
        self.profit = profit
        let boost = increasedContrast ? 0.2 : 0
        if dark {
            far = Color(hex: "#40548C").opacity(0.42)
            mid = Color(hex: "#162246").opacity(0.9)
            frontTop = Color(hex: "#AFC8FF").opacity(0.26)
            frontBottom = Color(hex: "#A0BEFF").opacity(0.02)
            rimPeak = Color(hex: "#FFBEAA").opacity(0.8)
            rimEdge = Color(hex: "#AAC8FF").opacity(0.25)
            topo = Color(hex: "#AAC8FF").opacity(0.13)
            trail = behind ? Color(hex: "#FFAD85").opacity(0.6 + boost) : Color.white.opacity(0.6 + boost)
            routeStart = Color(hex: "#6CB6FF")
            routeMid = Color(hex: "#A99FFF")
            routeEnd = Color(hex: "#FFAD85")
            pine = Color(hex: "#6BD6A9")
            climberFill = Color(hex: "#0B1730")
            climberRing = profit ? Color(hex: "#6BD6A9") : Color(hex: "#C3B6FF")
            halo = profit ? Color(hex: "#6BD6A9") : Color(hex: "#C9B8FF")
            flag = profit ? Color(hex: "#F5C25B") : Color(hex: "#FFAD85")
            pole = Color(hex: "#F3F7FC")
            hut = Color(hex: "#F3F7FC").opacity(0.9)
            summitText = Color(hex: "#FFB894")
            goldText = Color(hex: "#F5C25B")
            pillDot = profit ? Color(hex: "#6BD6A9") : Color(hex: "#A99FFF")
        } else {
            // Slightly denser ridges than the web mock: on device the pale dawn sky otherwise swallows the mountain.
            far = Color(hex: "#96ACD6").opacity(0.5)
            mid = Color(hex: "#7692C4").opacity(0.44)
            frontTop = Color.white.opacity(0.9)
            frontBottom = Color.white.opacity(0.22)
            rimPeak = Color.white
            rimEdge = Color.white.opacity(0.7)
            topo = Color(hex: "#5A78AA").opacity(0.15)
            trail = behind ? Color(hex: "#C8622F").opacity(0.6 + boost) : Color(hex: "#1E3C6E").opacity(0.5 + boost)
            routeStart = Color(hex: "#3B8BE0")
            routeMid = Color(hex: "#7C79E6")
            routeEnd = Color(hex: "#F08A5B")
            pine = Color(hex: "#23876A")
            climberFill = Color.white
            climberRing = profit ? Color(hex: "#23876A") : Color(hex: "#6E68E0")
            halo = profit ? Color(hex: "#23876A") : Color(hex: "#8E86F0")
            flag = profit ? Color(hex: "#E2A93B") : Color(hex: "#F08A5B")
            pole = Color(hex: "#0C1A2B")
            hut = Color.white
            summitText = Color(hex: "#9A4316")
            goldText = Color(hex: "#7A4E05")
            pillDot = profit ? Color(hex: "#23876A") : Color(hex: "#7A6FE0")
        }
    }

    /// Fill of an upcoming milestone dot (card colour).
    var hutAhead: Color { dark ? Color(hex: "#0B1730") : .white }

    /// Route gradient in chart space: glacier → dusk → dawn up to the summit; + pine along the Höhenweg.
    func route(_ g: SummitGeometry) -> LinearGradient {
        let width = max(g.size.width, 1)
        if g.profit {
            let summitStop = min(0.95, max(0.05, (g.sx - g.x0) / max(g.xEnd - g.x0, 1)))
            return LinearGradient(stops: [.init(color: routeStart, location: 0),
                                          .init(color: routeMid, location: summitStop * 0.55),
                                          .init(color: routeEnd, location: summitStop),
                                          .init(color: pine, location: min(1, summitStop + 0.08)),
                                          .init(color: pine, location: 1)],
                                  startPoint: UnitPoint(x: g.x0 / width, y: 0.5),
                                  endPoint: UnitPoint(x: g.xEnd / width, y: 0.5))
        }
        return LinearGradient(stops: [.init(color: routeStart, location: 0),
                                      .init(color: routeMid, location: 0.55),
                                      .init(color: routeEnd, location: 1)],
                              startPoint: UnitPoint(x: g.x0 / width, y: 0.5),
                              endPoint: UnitPoint(x: g.sx / width, y: 0.5))
    }
}

// MARK: - Layers

/// Static mountain: far + mid ridge (faded), frosted front ridge, front gradient, topo lines and the rim light.
private struct SummitRidges: View {
    let geometry: SummitGeometry
    let palette: SummitPalette
    let reduceTransparency: Bool

    var body: some View {
        let g = geometry
        let h = g.size.height
        let front = SummitPolyline(points: g.outline, closingAt: h + 10)
        ZStack(alignment: .topLeading) {
            ZStack {
                SummitPolyline(points: g.farRidge, closingAt: h + 40).fill(palette.far)
                SummitPolyline(points: g.midRidge, closingAt: h + 40).fill(palette.mid)
            }
            .mask {
                LinearGradient(stops: [.init(color: .black, location: 0),
                                       .init(color: .black.opacity(0.9), location: g.ridgeFadeStop),
                                       .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }

            if !reduceTransparency {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .clipShape(front)
                    .mask {
                        LinearGradient(stops: [.init(color: .black, location: 0.45), .init(color: .clear, location: 0.96)],
                                       startPoint: .top, endPoint: .bottom)
                    }
            }

            // The gradient spans the front ridge's own bounds (summit → bottom), like the SVG reference.
            front.fill(LinearGradient(stops: [.init(color: palette.frontTop, location: 0),
                                              .init(color: palette.frontBottom, location: 0.62),
                                              .init(color: palette.frontBottom.opacity(0), location: 1)],
                                      startPoint: UnitPoint(x: 0.5, y: g.sy / h),
                                      endPoint: UnitPoint(x: 0.5, y: (h + 10) / h)))

            ForEach(0..<3, id: \.self) { index in
                SummitPolyline(points: g.outline.map { CGPoint(x: $0.x, y: $0.y + Self.topoOffsets[index] * g.k) })
                    .stroke(palette.topo, lineWidth: 1)
                    .opacity(1 - Double(index) * 0.25)
            }

            SummitPolyline(points: g.outline)
                .stroke(LinearGradient(stops: [.init(color: palette.rimEdge, location: 0),
                                               .init(color: palette.rimPeak, location: min(0.98, max(0.02, g.sx / g.size.width))),
                                               .init(color: palette.rimEdge, location: 1)],
                                       startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }

    private static let topoOffsets: [CGFloat] = [14, 34, 56]
}

/// Everything that moves with the amortisation: trail, route, milestone dots, climber, summit flag and the „Heute“ pill.
/// `Animatable`, so climber and route stay locked together while `progress` animates.
private struct SummitClimb: View, Animatable {
    var progress: Double
    /// Final amortisation (milestone dots too close to it are hidden, spec §8.1.9).
    let target: Double
    let geometry: SummitGeometry
    let palette: SummitPalette
    let showsPill: Bool
    let pillText: String

    @State private var pillSize: CGSize = .zero

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let g = geometry
        let p = min(max(progress, 0), g.pEnd)
        let cx = g.x(for: p)
        let climber = CGPoint(x: cx, y: g.y(at: cx))
        let done = g.walked(to: climber)
        let todo = g.ahead(from: climber)
        let summit = CGPoint(x: g.sx, y: g.sy)
        let routeStyle = palette.route(g)
        ZStack(alignment: .topLeading) {
            if todo.count > 1 {
                SummitPolyline(points: todo)
                    .stroke(palette.trail, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.1, 6], dashPhase: -7))
            }
            SummitPolyline(points: done)
                .stroke(routeStyle, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .blur(radius: 3.2)
                .opacity(0.6)
            SummitPolyline(points: done)
                .stroke(routeStyle, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

            ForEach(SummitGeometry.milestones, id: \.fraction) { mark in
                if !g.profit, abs(mark.fraction - target) >= 0.045 {
                    let mx = g.x(for: mark.fraction)
                    let passed = mark.fraction <= p
                    Circle()
                        .fill(passed ? palette.hut : palette.hutAhead)
                        .overlay {
                            if !passed { Circle().stroke(palette.trail, lineWidth: 1.4) }
                        }
                        .frame(width: 6.8, height: 6.8)
                        .opacity(passed ? 0.95 : 1)
                        .position(x: mx, y: g.y(at: mx))
                }
            }

            // Climber: halo, disc with ring, core.
            Circle()
                .fill(RadialGradient(colors: [palette.halo.opacity(0.55), palette.halo.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: 20))
                .frame(width: 40, height: 40)
                .position(climber)
            Circle()
                .fill(palette.climberFill)
                .overlay { Circle().stroke(palette.climberRing, lineWidth: 3) }
                .frame(width: 15, height: 15)
                .position(climber)
            Circle()
                .fill(palette.climberRing)
                .frame(width: 5.2, height: 5.2)
                .position(climber)

            // Summit: dot, pole and swallowtail pennant.
            Circle()
                .fill(palette.flag)
                .overlay { Circle().stroke(palette.climberFill, lineWidth: 2) }
                .frame(width: 9, height: 9)
                .position(summit)
            Path { path in
                path.move(to: CGPoint(x: summit.x, y: summit.y - 3))
                path.addLine(to: CGPoint(x: summit.x, y: summit.y - 27))
            }
            .stroke(palette.pole.opacity(0.85), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            Path { path in
                path.move(to: CGPoint(x: summit.x + 0.8, y: summit.y - 27))
                path.addLine(to: CGPoint(x: summit.x + 15.8, y: summit.y - 27))
                path.addLine(to: CGPoint(x: summit.x + 12.2, y: summit.y - 22))
                path.addLine(to: CGPoint(x: summit.x + 15.8, y: summit.y - 17))
                path.addLine(to: CGPoint(x: summit.x + 0.8, y: summit.y - 17))
                path.closeSubpath()
            }
            .fill(palette.flag)

            if showsPill {
                pill(at: climber)
            }
        }
    }

    /// „Heute · € 1.044“ glass pill centred under the climber (above it when the card would cover it).
    private func pill(at climber: CGPoint) -> some View {
        let g = geometry
        let height = max(pillSize.height, 24)
        let below = climber.y + 16 + height <= g.size.height - 12 * g.k
        let y = below ? climber.y + 16 + height / 2 : climber.y - 18 - height / 2
        let half = pillSize.width / 2
        let x = min(max(climber.x, half + 8), g.size.width - half - 8)
        return HStack(spacing: 5) {
            Circle()
                .fill(palette.pillDot)
                .frame(width: 6, height: 6)
            Text(pillText)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 9)
        .frame(minHeight: 24)
        .glassEffect(.regular, in: .capsule)
        .fixedSize()
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            pillSize = newSize
        }
        .position(x: x, y: y)
        .opacity(pillSize == .zero ? 0 : 1)
        .accessibilityHidden(true)
    }
}

/// Straight polyline through `points`; optionally closed down to `closingAt` (for filled ridges).
private struct SummitPolyline: Shape {
    var points: [CGPoint]
    var closingAt: CGFloat? = nil

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        if let bottom = closingAt {
            path.addLine(to: CGPoint(x: last.x, y: bottom))
            path.addLine(to: CGPoint(x: first.x, y: bottom))
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - Shared shapes (also used by onboarding, Statistik, Ticket, widgets gallery)

/// Deterministic mountain ridge with a main peak at (peakX, peakY) in unit coordinates.
struct RidgeShape: Shape {
    var peakX: CGFloat
    var peakY: CGFloat
    var seed: Int
    var roughness: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(peakX, peakY) }
        set { peakX = newValue.first; peakY = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let steps = 28
        var rng = UInt64(truncatingIfNeeded: seed &* 2_654_435_761 | 1)
        func noise() -> CGFloat {
            rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
            return CGFloat(rng % 1000) / 1000
        }
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for i in 0...steps {
            let u = CGFloat(i) / CGFloat(steps)
            let distance = abs(u - peakX)
            // Cone towards the peak + jagged noise.
            let base = peakY + distance * (1.25 - peakY) * 1.1
            let jag = (noise() - 0.5) * 0.12 * roughness * (1 + distance)
            let y = min(max(base + jag, peakY), 1)
            p.addLine(to: CGPoint(x: rect.minX + u * rect.width, y: rect.minY + y * rect.height))
            if abs(u - peakX) < 0.5 / CGFloat(steps) {
                p.addLine(to: CGPoint(x: rect.minX + peakX * rect.width, y: rect.minY + peakY * rect.height))
            }
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Catmull-Rom smoothed polyline.
struct SmoothPath: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        guard points.count > 2 else {
            points.dropFirst().forEach { p.addLine(to: $0) }
            return p
        }
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            p.addCurve(to: p2, control1: c1, control2: c2)
        }
        return p
    }
}

/// Diagonal hatch lines.
struct HatchShape: Shape {
    var spacing: CGFloat = 8
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return p
    }
}

/// Pennant flag on a pole.
struct FlagShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRect(CGRect(x: rect.minX, y: rect.minY, width: 2.5, height: rect.height))
        p.move(to: CGPoint(x: rect.minX + 2.5, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.22))
        p.addLine(to: CGPoint(x: rect.minX + 2.5, y: rect.minY + rect.height * 0.44))
        p.closeSubpath()
        return p
    }
}
