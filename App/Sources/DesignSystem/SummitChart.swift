import SwiftUI
import KlimaCore

/// Signature visual: the cumulative value climbs across an Alpine ridge towards the summit (= break-even, ticket price).
/// x = time across the ticket period, y = cumulative value. The highest peak sits at the (forecast) break-even day.
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
    @State private var reveal: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let layout = Layout(size: size, start: start, end: end, maxY: maxY)
            ZStack(alignment: .topLeading) {
                gainZone(layout: layout)
                ridges(layout: layout)
                valueLine(layout: layout)
                forecastLine(layout: layout)
                milestones(layout: layout)
                if showsLabels { markers(layout: layout) }
            }
        }
        .onAppear {
            if reduceMotion || LaunchMode.isScreenshot { reveal = 1 } else {
                withAnimation(.easeOut(duration: 1.1).delay(0.15)) { reveal = 1 }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Amortisationsverlauf")
        .accessibilityValue(accessibilityText)
    }

    // MARK: Geometry

    private var maxValue: Double { max(series.map(\.value).max() ?? 0, forecast.map(\.value).max() ?? 0) }
    private var maxY: Double { max(price * 1.18, maxValue * 1.05, 1) }

    /// Day where the summit stands: actual paid-off day, forecast, or the period end.
    private var summitDate: Date {
        if isPaidOff, let crossing = series.first(where: { $0.value >= price })?.date { return crossing }
        if let breakEvenDate, breakEvenDate <= end { return breakEvenDate }
        return end
    }

    private struct Layout {
        let size: CGSize
        let start: Date
        let end: Date
        let maxY: Double

        func x(_ date: Date) -> CGFloat {
            let total = max(end.timeIntervalSince(start), 1)
            return CGFloat(min(max(date.timeIntervalSince(start) / total, 0), 1)) * size.width
        }

        func y(_ value: Double) -> CGFloat {
            size.height - CGFloat(min(max(value / maxY, 0), 1)) * size.height * 0.92
        }
    }

    // MARK: Layers

    private func ridges(layout: Layout) -> some View {
        let summitX = layout.x(summitDate)
        let summitY = layout.y(price)
        let h = layout.size.height
        let w = layout.size.width
        return ZStack {
            // Far ridge
            RidgeShape(peakX: summitX / max(w, 1) * 0.6 + 0.3, peakY: (summitY + h * 0.18) / max(h, 1), seed: 3, roughness: 0.55)
                .fill(LinearGradient(colors: [ridgeColor(0).opacity(0.55), ridgeColor(0).opacity(0.05)], startPoint: .top, endPoint: .bottom))
            // Middle ridge with the summit
            RidgeShape(peakX: summitX / max(w, 1), peakY: summitY / max(h, 1), seed: 7, roughness: 0.42)
                .fill(LinearGradient(colors: [ridgeColor(1).opacity(0.9), ridgeColor(1).opacity(0.15)], startPoint: .top, endPoint: .bottom))
            // Near ridge
            RidgeShape(peakX: 0.18, peakY: 0.72, seed: 11, roughness: 0.3)
                .fill(LinearGradient(colors: [ridgeColor(2).opacity(0.85), ridgeColor(2).opacity(0.25)], startPoint: .top, endPoint: .bottom))
        }
    }

    private func ridgeColor(_ layer: Int) -> Color {
        let light = [Color(hex: "#A9B6E0"), Color(hex: "#C9D0EE"), Color(hex: "#E9ECF8")]
        let dark = [Color(hex: "#2A3466"), Color(hex: "#3A3F78"), Color(hex: "#1B2040")]
        return (colorScheme == .dark ? dark : light)[layer]
    }

    private func valueLine(layout: Layout) -> some View {
        let points = series.map { CGPoint(x: layout.x($0.date), y: layout.y($0.value)) }
        let priceY = layout.y(price)
        return ZStack {
            SmoothPath(points: points)
                .trim(from: 0, to: reveal)
                .stroke(Theme.progressGradient, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                .blur(radius: 10)
                .opacity(0.45)
            SmoothPath(points: points)
                .trim(from: 0, to: reveal)
                .stroke(Theme.progressGradient, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            // Above the summit line the route turns pine-green: every further trip is profit.
            if isPaidOff {
                SmoothPath(points: points)
                    .trim(from: 0, to: reveal)
                    .stroke(Theme.positive, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
                    .mask(alignment: .top) {
                        Rectangle().frame(height: max(priceY, 0))
                    }
            }
        }
    }

    /// Hatched band above the ticket price: the profit zone.
    private func gainZone(layout: Layout) -> some View {
        let priceY = layout.y(price)
        return ZStack(alignment: .topTrailing) {
            HatchShape(spacing: 7)
                .stroke(Theme.positive.opacity(colorScheme == .dark ? 0.16 : 0.12), lineWidth: 1)
                .background(Theme.positive.opacity(colorScheme == .dark ? 0.05 : 0.04))
                .frame(height: max(priceY, 0))
                .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
            if showsLabels {
                Text("GEWINNZONE")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(Theme.positive)
                    .padding(.trailing, 12)
                    .padding(.top, max(priceY - 18, 2))
                    .opacity(isPaidOff ? 1 : 0.7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(reveal)
        .accessibilityHidden(true)
    }

    /// Base camp (25 %), hut (50 %) and summit ridge (75 %) on the route – solid when reached, ghosted ahead.
    private func milestones(layout: Layout) -> some View {
        let marks = [Milestone(fraction: 0.25, symbol: "tent.fill"), Milestone(fraction: 0.5, symbol: "house.fill"),
                     Milestone(fraction: 0.75, symbol: "mountain.2.fill")]
        return ZStack(alignment: .topLeading) {
            ForEach(marks) { mark in
                let target = price * mark.fraction
                let reached = series.first { $0.value >= target }
                let point = milestonePoint(target: target, reached: reached, layout: layout)
                Image(systemName: mark.symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(reached != nil ? Color.white : Theme.textSecondary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(reached != nil ? AnyShapeStyle(Theme.accentSecondary) : AnyShapeStyle(.ultraThinMaterial)))
                    .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
                    .position(point)
                    .opacity(reached != nil ? reveal : reveal * 0.8)
            }
        }
        .accessibilityHidden(true)
    }

    private struct Milestone: Identifiable {
        let fraction: Double
        let symbol: String
        var id: Double { fraction }
    }

    private func milestonePoint(target: Double, reached: CumulativePoint?, layout: Layout) -> CGPoint {
        if let reached { return CGPoint(x: layout.x(reached.date), y: layout.y(reached.value)) }
        // Ahead: interpolate along the forecast segment towards the summit.
        guard let last = series.last, price > last.value else {
            return CGPoint(x: layout.x(summitDate), y: layout.y(target))
        }
        let t = (target - last.value) / (price - last.value)
        let x0 = layout.x(last.date), x1 = layout.x(summitDate)
        return CGPoint(x: x0 + (x1 - x0) * CGFloat(t), y: layout.y(target))
    }

    private func forecastLine(layout: Layout) -> some View {
        Group {
            if !isPaidOff, let last = series.last {
                Path { p in
                    p.move(to: CGPoint(x: layout.x(last.date), y: layout.y(last.value)))
                    p.addLine(to: CGPoint(x: layout.x(summitDate), y: layout.y(price)))
                }
                .trim(from: 0, to: reveal)
                .stroke(Theme.textSecondary.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 6]))
            }
        }
    }

    private func markers(layout: Layout) -> some View {
        let todayPoint = series.last.map { CGPoint(x: layout.x($0.date), y: layout.y($0.value)) } ?? .zero
        let summit = CGPoint(x: layout.x(summitDate), y: layout.y(price))
        return ZStack(alignment: .topLeading) {
            // Summit flag
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 6) {
                    FlagShape()
                        .fill(Theme.summit)
                        .frame(width: 22, height: 32)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(isPaidOff ? "RENTIERT" : "BREAK-EVEN")
                            .font(.caption2.weight(.bold))
                            .tracking(1)
                            .foregroundStyle(Theme.summit)
                        Text(Format.euro(price))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .offset(y: -4)
                }
            }
            .position(x: min(max(summit.x + 46, 60), layout.size.width - 56), y: max(summit.y - 22, 20))
            .opacity(reveal)

            Circle()
                .fill(Theme.summit)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .position(summit)

            // Today marker
            if !series.isEmpty {
                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Theme.accentSecondary, lineWidth: 4))
                    .background(Circle().fill(Theme.accentSecondary.opacity(0.3)).frame(width: 34, height: 34))
                    .position(todayPoint)
                    .opacity(reveal)
                let nearSummit = abs(todayPoint.x - summit.x) < 120 && abs(todayPoint.y - summit.y) < 70
                Text("Heute")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular, in: .capsule)
                    .position(x: min(max(todayPoint.x - (nearSummit ? 40 : 0), 40), layout.size.width - 40),
                              y: nearSummit ? min(todayPoint.y + 38, layout.size.height - 14) : max(todayPoint.y - 36, 14))
                    .opacity(reveal)
            }
        }
    }

    private var accessibilityText: String {
        let value = series.last?.value ?? 0
        var text = "\(Format.euro(value)) von \(Format.euro(price))"
        if isPaidOff { text += ", rentiert" } else if let d = breakEvenDate { text += ", Break-even voraussichtlich \(Format.dayMonth(d))" }
        return text
    }
}

// MARK: - Shapes

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
