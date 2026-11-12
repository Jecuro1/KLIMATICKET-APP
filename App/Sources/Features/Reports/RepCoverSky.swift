import SwiftUI
import UIKit
import KlimaCore

// The cover's alpine sky (backdrop, summit geometry) – split from RepReportPages.swift.

/// The cover's alpine sky: dawn gradient, sun glow, two far ridges, the summit mountain whose peak is the ticket price,
/// the value route climbing it (forecast dotted) and the flag at break-even.
struct RepCoverSky: View {
    let data: RepReportData
    /// Pre-rendered backdrop (PDF only): PDF shadings drop the alpha fall-off of the glow gradients,
    /// so the soft sky is embedded as a 3× bitmap while route, labels and text stay vector.
    var backdropImage: UIImage? = nil

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let geometry = RepSummitGeometry(data: data, size: size)
            ZStack(alignment: .topLeading) {
                if let backdropImage {
                    Image(uiImage: backdropImage)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                } else {
                    RepCoverSkyBackdrop(data: data)
                }
                priceLine(geometry)
                route(geometry)
                markers(geometry)
            }
        }
        .accessibilityHidden(true)
    }

    private func priceLine(_ g: RepSummitGeometry) -> some View {
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: RepPrint.margin, y: g.summit.y))
                p.addLine(to: CGPoint(x: g.size.width - RepPrint.margin, y: g.summit.y))
            }
            .stroke(Theme.dawn.opacity(0.55), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
            Text("Gipfel = \(data.employerContribution > 0 ? "Eigenanteil" : "Ticketpreis") \(Format.euro(data.ownShare))")
                .font(RepPrint.font(7.5, .semibold))
                .foregroundStyle(Theme.summitText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.85), in: .capsule)
                .position(x: g.labelX, y: g.summit.y + 11)
        }
    }

    @ViewBuilder
    private func route(_ g: RepSummitGeometry) -> some View {
        if let last = g.points.last, !data.summary.isPaidOff, data.isRunning {
            Path { p in
                p.move(to: last)
                p.addLine(to: g.summit)
            }
            .stroke(Theme.textSecondary, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [1.5, 4]))
        }
        if g.points.count > 1 {
            SmoothPath(points: g.points)
                .stroke(Theme.routeGradient, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                .opacity(0.22)
            SmoothPath(points: g.points)
                .stroke(Theme.routeGradient, style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
        }
    }

    private func markers(_ g: RepSummitGeometry) -> some View {
        ZStack(alignment: .topLeading) {
            FlagShape()
                .fill(data.summary.isPaidOff ? Theme.gold : Theme.dawn)
                .frame(width: 15, height: 22)
                .position(x: g.summit.x + 7, y: g.summit.y - 11)
            Circle()
                .fill(Theme.dawn)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                .position(g.summit)
            if let flagText {
                Text(flagText)
                    .font(RepPrint.font(7.5, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Color.white, in: .capsule)
                    .overlay(Capsule().strokeBorder(RepPrint.panelStroke, lineWidth: 0.5))
                    .fixedSize()
                    .position(x: min(g.size.width - RepPrint.margin - 44, g.summit.x + 58), y: g.summit.y + 17)
            }
            if let last = g.points.last {
                Circle()
                    .fill(Color.white)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Theme.dusk, lineWidth: 2.5))
                    .position(last)
            }
        }
    }

    private var flagText: String? {
        let s = data.summary
        if s.isPaidOff, let date = s.paidOffDate { return "⚑ Break-even \(Format.dayMonth(date))" }
        if data.isRunning, s.forecastReachesBreakEven, let date = s.forecastBreakEvenDate { return "⚑ Prognose \(Format.dayMonth(date))" }
        return nil
    }
}

/// Soft sky of the cover: dawn gradient, sun glow, far ridges and the white summit mountain.
struct RepCoverSkyBackdrop: View {
    let data: RepReportData

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let geometry = RepSummitGeometry(data: data, size: size)
            ZStack(alignment: .topLeading) {
                LinearGradient(stops: [.init(color: Color(hex: "#D4E6F8"), location: 0),
                                       .init(color: Color(hex: "#E4E2F7"), location: 0.42),
                                       .init(color: Color(hex: "#FBE2D2"), location: 0.72),
                                       .init(color: .white, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Theme.dawn2.opacity(0.75), Theme.dawn2.opacity(0)],
                               center: UnitPoint(x: min(0.92, geometry.summit.x / size.width + 0.06), y: 0.56),
                               startRadius: 0, endRadius: 230)
                RidgeShape(peakX: 0.2, peakY: 0.6, seed: 3, roughness: 0.7)
                    .fill(Theme.dusk.opacity(0.12))
                RidgeShape(peakX: 0.9, peakY: 0.62, seed: 11, roughness: 0.6)
                    .fill(Theme.glacier.opacity(0.12))
                RidgeShape(peakX: geometry.summit.x / size.width, peakY: geometry.summit.y / size.height, seed: 7, roughness: 0.42)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.95), .white], startPoint: .top, endPoint: .bottom))
                RidgeShape(peakX: geometry.summit.x / size.width, peakY: geometry.summit.y / size.height, seed: 7, roughness: 0.42)
                    .stroke(Theme.dusk.opacity(0.22), lineWidth: 0.8)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Maps the cumulative value series onto the cover sky (x = ticket year, y = value with the ticket price at the summit).
struct RepSummitGeometry {
    let size: CGSize
    let summit: CGPoint
    let points: [CGPoint]
    let labelX: CGFloat

    init(data: RepReportData, size: CGSize) {
        self.size = size
        let period = data.period
        let price = max(data.ownShare, 1)
        let maxValue = max(price, data.snapshot.series.map(\.value).max() ?? 0)
        let left = RepPrint.margin * 0.6, right = size.width - RepPrint.margin * 0.6
        let base = size.height * 0.97
        // The route never climbs above 52 % of the sky (title area); beyond break-even the scale compresses.
        let topY = size.height * 0.53
        let priceY = base - (base - topY) * CGFloat(price / maxValue) * (maxValue > price ? 1 : 0.86)
        let total = max(period.end.timeIntervalSince(period.start), 1)
        func x(_ date: Date) -> CGFloat {
            let f = min(max(date.timeIntervalSince(period.start) / total, 0), 1)
            return left + CGFloat(f) * (right - left)
        }
        func y(_ value: Double) -> CGFloat {
            base - (base - priceY) * CGFloat(min(max(value / price, 0), maxValue / price))
        }
        let summitDate: Date = {
            if data.summary.isPaidOff, let crossing = data.snapshot.series.first(where: { $0.value >= price })?.date { return crossing }
            if let date = data.summary.forecastBreakEvenDate, date <= period.end { return date }
            return period.end
        }()
        summit = CGPoint(x: min(right - 8, max(left + 60, x(summitDate))), y: priceY)
        var pts = [CGPoint(x: left, y: base)]
        pts += data.snapshot.series.map { CGPoint(x: x($0.date), y: y($0.value)) }
        points = pts
        labelX = summit.x > size.width * 0.55 ? RepPrint.margin + 70 : size.width - RepPrint.margin - 70
    }
}
