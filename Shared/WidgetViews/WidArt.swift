import SwiftUI
import WidgetKit
import KlimaCore

// MARK: - Sky background (container background)

/// The widgets' brand background: "Morgendämmerung" (light) or "Blaue Stunde" (dark) with the summit glow.
/// The extension installs it via `widgetBrandBackground(_:)`; the in-app gallery draws it directly.
struct WidSkyBackground: View {
    var family: WidgetFamily

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            LinearGradient(colors: baseColors(dark: dark), startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.dusk.opacity(dark ? 0.30 : 0.20), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: glowRadius * 1.1)
            RadialGradient(colors: [(dark ? Theme.alpenglow : Theme.dawn2).opacity(dark ? 0.34 : 0.78), .clear],
                           center: UnitPoint(x: 0.78, y: glowY),
                           startRadius: 0, endRadius: glowRadius)
            if dark {
                WidStarsShape(count: family == .systemSmall ? 16 : 30, seed: 7)
                    .fill(Color.white.opacity(0.55))
            }
        }
    }

    private func baseColors(dark: Bool) -> [Color] {
        if dark {
            return [Theme.background, Theme.dusk.mix(with: Theme.background, by: 0.7)]
        }
        return [Theme.glacier2.mix(with: .white, by: 0.38), Theme.background.mix(with: Theme.dawn2, by: 0.28)]
    }

    /// Vertical position of the summit glow (behind the flag of each layout).
    private var glowY: CGFloat {
        switch family {
        case .systemSmall: 0.64
        case .systemLarge: 0.46
        default: 0.56
        }
    }

    private var glowRadius: CGFloat {
        switch family {
        case .systemSmall: 120
        case .systemLarge: 230
        default: 180
        }
    }
}

extension View {
    /// Installs the brand sky as the widget's container background (clear for lock-screen families).
    func widgetBrandBackground(_ family: WidgetFamily) -> some View {
        containerBackground(for: .widget) {
            if family.widIsAccessory {
                Color.clear
            } else {
                WidSkyBackground(family: family)
            }
        }
    }
}

// MARK: - Summit artwork

/// "Dein Weg zum Gipfel" in miniature: layered ridges, the value route climbing towards the summit
/// (= ticket price), a dotted forecast and the break-even flag. Drawn as content (not background) so that
/// it survives the accented / clear home-screen styles, where the route turns into the accent colour.
struct WidSummitArt: View {
    var model: WidSummitModel
    /// Vertical band of the artwork in unit coordinates (0 = top edge, 1 = bottom edge).
    var top: CGFloat
    var bottom: CGFloat
    /// Scales strokes and markers (small widget ≈ 0.85, large ≈ 1.1).
    var scale: CGFloat = 1
    var showsRoute: Bool = true
    var ridgeOpacity: Double = 1
    /// Summit flag + dot (hidden where buttons sit on top of the ridge).
    var showsFlag: Bool = true
    /// Large layouts: "Heute" pill above the climber …
    var todayLabel: String? = nil
    /// … and the ticket price beside the summit flag ("€ 1.400").
    var summitLabel: String? = nil
    /// Valley mist: the ridges fade out from `mistFrom` (unit height) down to `mistOpacity` at the bottom edge.
    var mistFrom: CGFloat = 0.72
    var mistOpacity: Double = 0.35

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            let frame = WidArtFrame(size: geo.size, top: top, bottom: bottom)
            ZStack(alignment: .topLeading) {
                ridges(frame)
                    .opacity(ridgeOpacity)
                if showsRoute, !model.route.isEmpty {
                    forecast(frame)
                    route(frame)
                }
                if showsFlag || showsRoute {
                    markers(frame)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var isFullColor: Bool { renderingMode == .fullColor }
    private var isDark: Bool { colorScheme == .dark }

    // MARK: Ridges

    private func ridges(_ f: WidArtFrame) -> some View {
        let summit = f.unitPoint(CGPoint(x: model.summitX, y: model.priceLevel))
        let left = CGPoint(x: max(0.12, summit.x - 0.42), y: min(0.97, summit.y + (1 - summit.y) * 0.34))
        let right = CGPoint(x: min(0.98, summit.x + 0.2), y: min(0.97, summit.y + (1 - summit.y) * 0.22))
        let front = WidRidgeShape(peak: summit, seed: 7, drop: 0.86, roughness: 1)
        return ZStack {
            WidRidgeShape(peak: right, seed: 3, drop: 0.7, roughness: 1.2)
                .fill(backRidgeColor(primary: false))
            WidRidgeShape(peak: left, seed: 11, drop: 0.8, roughness: 1.1)
                .fill(backRidgeColor(primary: true))
            front.fill(frontFill)
            front.stroke(frontRim, lineWidth: 1.1 * scale)
        }
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: mistFrom),
                                   .init(color: .black.opacity(mistOpacity), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private func backRidgeColor(primary: Bool) -> Color {
        guard isFullColor else { return Color.white.opacity(primary ? 0.10 : 0.07) }
        if primary { return Theme.dusk.opacity(isDark ? 0.30 : 0.20) }
        return Theme.glacier.opacity(isDark ? 0.18 : 0.16)
    }

    private var frontFill: LinearGradient {
        let colors: [Color]
        if !isFullColor {
            colors = [Color.white.opacity(0.18), Color.white.opacity(0.02)]
        } else if isDark {
            colors = [Theme.glacier2.opacity(0.26), Theme.glacier2.opacity(0.03)]
        } else {
            colors = [Color.white.opacity(0.9), Color.white.opacity(0.22)]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private var frontRim: LinearGradient {
        let colors: [Color]
        if !isFullColor {
            colors = [Color.white.opacity(0.35), Color.white.opacity(0.5)]
        } else if isDark {
            colors = [Theme.glacier2.opacity(0.28), Theme.dawn2.opacity(0.8)]
        } else {
            colors = [Color.white.opacity(0.75), Color.white]
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    // MARK: Route

    private func route(_ f: WidArtFrame) -> some View {
        let points = model.route.map { f.point($0) }
        let priceY = f.point(CGPoint(x: 0, y: model.priceLevel)).y
        return ZStack(alignment: .topLeading) {
            if isFullColor {
                WidRoutePath(points: points)
                    .stroke(Theme.routeGradient, style: StrokeStyle(lineWidth: 7 * scale, lineCap: .round, lineJoin: .round))
                    .blur(radius: 5 * scale)
                    .opacity(isDark ? 0.55 : 0.4)
            }
            WidRoutePath(points: points)
                .stroke(Theme.routeGradient, style: StrokeStyle(lineWidth: 3.2 * scale, lineCap: .round, lineJoin: .round))
                .widgetAccentable()
            // Above the summit line the route turns pine-green: every further trip is profit.
            if model.isPaidOff {
                WidRoutePath(points: points)
                    .stroke(Theme.positive, style: StrokeStyle(lineWidth: 3.4 * scale, lineCap: .round, lineJoin: .round))
                    .mask(alignment: .top) {
                        Rectangle().frame(height: max(priceY, 0))
                    }
                    .widgetAccentable()
            }
        }
    }

    private func forecast(_ f: WidArtFrame) -> some View {
        Group {
            if !model.isPaidOff, let today = model.today {
                Path { p in
                    p.move(to: f.point(today))
                    p.addLine(to: f.point(CGPoint(x: model.summitX, y: model.priceLevel)))
                }
                .stroke(Theme.textSecondary.opacity(0.85),
                        style: StrokeStyle(lineWidth: 1.6 * scale, lineCap: .round, dash: [1.5 * scale, 4.5 * scale]))
            }
        }
    }

    // MARK: Markers

    private func markers(_ f: WidArtFrame) -> some View {
        let summit = f.point(CGPoint(x: model.summitX, y: model.priceLevel))
        let flagSize = CGSize(width: 13 * scale, height: 20 * scale)
        let flagColor = model.isPaidOff ? Theme.gold : Theme.dawn
        return ZStack(alignment: .topLeading) {
            if showsFlag {
                WidFlagShape()
                    .fill(flagColor)
                    .frame(width: flagSize.width, height: flagSize.height)
                    .position(x: summit.x + flagSize.width / 2 - 1.2 * scale, y: summit.y - flagSize.height / 2)
                    .widgetAccentable()
                Circle()
                    .fill(flagColor)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.6 * scale))
                    .frame(width: 7.5 * scale, height: 7.5 * scale)
                    .position(summit)
            }
            if showsRoute, let today = model.today {
                todayMarker
                    .position(f.point(today))
            }
            if showsFlag, let summitLabel {
                summitLabelView(summitLabel, summit: summit, flagSize: flagSize, width: f.size.width)
            }
            if showsRoute, let todayLabel, let today = model.today,
               let center = pillCenter(for: f.point(today), summit: summit, flagSize: flagSize, frame: f) {
                todayPill(todayLabel)
                    .position(center)
            }
        }
    }

    private static let summitLabelWidth: CGFloat = 70

    private func summitLabelFitsRight(summit: CGPoint, flagSize: CGSize, width: CGFloat) -> Bool {
        summit.x + flagSize.width + 4 + Self.summitLabelWidth < width - 10
    }

    /// Area taken by the flag (and its price label) – the "Heute" pill keeps clear of it.
    private func summitBlock(summit: CGPoint, flagSize: CGSize, width: CGFloat) -> CGRect {
        let flag = CGRect(x: summit.x - 4, y: summit.y - flagSize.height - 2, width: flagSize.width + 8, height: flagSize.height + 8)
        guard summitLabel != nil else { return flag }
        let fitsRight = summitLabelFitsRight(summit: summit, flagSize: flagSize, width: width)
        let labelX = fitsRight ? summit.x + flagSize.width + 4 : summit.x - 6 - Self.summitLabelWidth
        let label = CGRect(x: labelX, y: summit.y - flagSize.height * 0.77 - 10, width: Self.summitLabelWidth, height: 20)
        return flag.union(label)
    }

    /// Above the climber, else upper-left, else below – nil when every spot collides with the summit block.
    private func pillCenter(for point: CGPoint, summit: CGPoint, flagSize: CGSize, frame f: WidArtFrame) -> CGPoint? {
        let blocked = summitBlock(summit: summit, flagSize: flagSize, width: f.size.width)
        let candidates = [CGPoint(x: point.x, y: point.y - 22 * scale),
                          CGPoint(x: point.x - 48, y: point.y - 15 * scale),
                          CGPoint(x: point.x, y: point.y + 22 * scale)]
        for candidate in candidates {
            let x = min(max(candidate.x, 34), f.size.width - 34)
            let rect = CGRect(x: x - 30, y: candidate.y - 11, width: 60, height: 22)
            if !rect.intersects(blocked) && rect.minY >= f.rect.minY - 14 && rect.maxY <= f.size.height {
                return CGPoint(x: x, y: candidate.y)
            }
        }
        return nil
    }

    private func summitLabelView(_ text: String, summit: CGPoint, flagSize: CGSize, width: CGFloat) -> some View {
        let labelWidth = Self.summitLabelWidth
        let fitsRight = summitLabelFitsRight(summit: summit, flagSize: flagSize, width: width)
        let centerX = fitsRight ? summit.x + flagSize.width + 4 + labelWidth / 2 : summit.x - 6 - labelWidth / 2
        return Text(text)
            .font(.system(size: 12.5 * scale, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: labelWidth, alignment: fitsRight ? .leading : .trailing)
            .position(x: centerX, y: summit.y - flagSize.height * 0.77)
    }

    private func todayPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(pillFill))
            .overlay(Capsule().strokeBorder(pillRim, lineWidth: 0.6))
            .fixedSize()
    }

    private var pillFill: Color {
        guard isFullColor else { return Color.white.opacity(0.14) }
        return isDark ? Color.white.opacity(0.12) : Color.white.opacity(0.7)
    }

    private var pillRim: Color {
        guard isFullColor else { return Color.white.opacity(0.25) }
        return isDark ? Color.white.opacity(0.2) : Color.white
    }

    private var todayMarker: some View {
        ZStack {
            Circle()
                .fill(Theme.accentSecondary.opacity(isFullColor ? 0.28 : 0.2))
                .frame(width: 18 * scale, height: 18 * scale)
            Circle()
                .fill(Color.white)
                .frame(width: 9 * scale, height: 9 * scale)
                .overlay(Circle().stroke(Theme.accentSecondary, lineWidth: 2.6 * scale))
                .widgetAccentable()
        }
    }
}

/// Maps normalised artwork coordinates into the widget's coordinate space.
private struct WidArtFrame {
    let size: CGSize
    let rect: CGRect

    init(size: CGSize, top: CGFloat, bottom: CGFloat) {
        self.size = size
        let minY = size.height * top
        let maxY = size.height * max(bottom, top + 0.05)
        rect = CGRect(x: 0, y: minY, width: size.width, height: maxY - minY)
    }

    func point(_ p: CGPoint) -> CGPoint {
        CGPoint(x: rect.minX + p.x * rect.width, y: rect.maxY - p.y * rect.height)
    }

    /// The same point in unit coordinates of the whole widget (for the ridge shapes).
    func unitPoint(_ p: CGPoint) -> CGPoint {
        let absolute = point(p)
        return CGPoint(x: absolute.x / max(size.width, 1), y: absolute.y / max(size.height, 1))
    }
}

// MARK: - Shapes

/// Deterministic jagged ridge with its main peak at `peak` (unit coordinates of the drawing rect).
struct WidRidgeShape: Shape {
    var peak: CGPoint
    var seed: UInt64
    /// How far the flanks fall towards the edges (share of the height below the peak).
    var drop: CGFloat = 0.85
    var roughness: CGFloat = 1

    func path(in rect: CGRect) -> Path {
        let steps = 24
        var state: UInt64 = seed &* 0x9E37_79B9_7F4A_7C15 | 1
        func noise() -> CGFloat {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return CGFloat(state % 1000) / 1000 - 0.5
        }
        let peakX = min(max(peak.x, 0), 1)
        let peakY = min(max(peak.y, 0), 1)
        let leftSpan = max(peakX, 0.08)
        let rightSpan = max(1 - peakX, 0.08)
        let depth = 1 - peakY

        func absolute(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + u * rect.width, y: rect.minY + v * rect.height)
        }

        var path = Path()
        path.move(to: absolute(0, 1))
        var placedPeak = false
        for i in 0...steps {
            let u = CGFloat(i) / CGFloat(steps)
            let jitter = noise()
            if !placedPeak && u >= peakX {
                path.addLine(to: absolute(peakX, peakY))
                placedPeak = true
            }
            let distance = u < peakX ? (peakX - u) / leftSpan : (u - peakX) / rightSpan
            let flank = CGFloat(pow(Double(min(distance, 1)), 0.85))
            let base: CGFloat = peakY + depth * drop * flank
            let jag: CGFloat = jitter * 0.09 * roughness * depth * min(distance * 3, 1)
            let v = min(max(base + jag, peakY + depth * 0.04), 1)
            path.addLine(to: absolute(u, v))
        }
        if !placedPeak { path.addLine(to: absolute(peakX, peakY)) }
        path.addLine(to: absolute(1, 1))
        path.closeSubpath()
        return path
    }
}

/// Catmull-Rom smoothed polyline through absolute points.
struct WidRoutePath: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            for point in points.dropFirst() { path.addLine(to: point) }
            return path
        }
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = points[min(i + 2, points.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }
}

/// Pennant on a pole (pole bottom-left = summit).
struct WidFlagShape: Shape {
    func path(in rect: CGRect) -> Path {
        let pole = max(rect.width * 0.17, 1.6)
        var path = Path()
        path.addRoundedRect(in: CGRect(x: rect.minX, y: rect.minY, width: pole, height: rect.height),
                            cornerSize: CGSize(width: pole / 2, height: pole / 2))
        path.move(to: CGPoint(x: rect.minX + pole, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.23))
        path.addLine(to: CGPoint(x: rect.minX + pole, y: rect.minY + rect.height * 0.46))
        path.closeSubpath()
        return path
    }
}

/// Sparse deterministic star field in the upper half (dark skies).
struct WidStarsShape: Shape {
    var count: Int
    var seed: UInt64

    func path(in rect: CGRect) -> Path {
        var state: UInt64 = seed &* 0x2545_F491_4F6C_DD1D | 1
        func next() -> CGFloat {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return CGFloat(state % 10_000) / 10_000
        }
        var path = Path()
        for _ in 0..<max(count, 0) {
            let x = next() * rect.width
            let y = next() * next() * rect.height * 0.55
            let r = 0.45 + next() * 0.7
            path.addEllipse(in: CGRect(x: rect.minX + x, y: rect.minY + y, width: r * 2, height: r * 2))
        }
        return path
    }
}
