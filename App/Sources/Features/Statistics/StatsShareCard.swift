import SwiftUI
import UIKit
import CoreTransferable
import UniformTypeIdentifiers
import KlimaCore

/// "Bilanz als Bild teilen": the share card, rendered only when the share sheet actually exports it (like the
/// ticket's `TktSharePass`) – not on every appearance of the Statistik tab.
struct StatsSharePayload: Transferable {
    let snapshot: AnalyticsSnapshot
    let ticketName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { payload in
            try await payload.renderPNG()
        }
        .suggestedFileName("KlimaBilanz-Bilanz.png")
    }

    @MainActor
    func renderPNG() throws -> Data {
        guard let data = StatsShareCard.render(snapshot: snapshot, ticketName: ticketName)?.pngData() else {
            throw TktShareError.renderFailed
        }
        return data
    }
}

/// "Bilanz teilen": a 4:5 social card (rendered at 3× → 1080 × 1350 px) with brand, % amortised,
/// value, trips, km, CO₂ and a static summit mini chart. Always rendered in the dark "Blaue Stunde" look.
struct StatsShareCard: View {
    let snapshot: AnalyticsSnapshot
    let ticketName: String

    static let size = CGSize(width: 360, height: 450)

    private var summary: SavingsSummary { snapshot.summary }

    var body: some View {
        ZStack {
            background
            VStack(alignment: .leading, spacing: 0) {
                brandRow
                Spacer(minLength: Theme.Spacing.s)
                Kicker(text: "\(ticketName) · \(StatsCalc.ticketYearLabel(snapshot.ticket))", color: Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                numeral
                Text(valueLine)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(verdictLine)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(summary.isPaidOff ? Theme.positiveText : Theme.summitText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 3)
                StatsShareSummit(snapshot: snapshot)
                    .frame(height: 84)
                    .padding(.top, Theme.Spacing.s)
                    .padding(.horizontal, -24)
                statsRow
                    .padding(.top, Theme.Spacing.s)
                Text("Hat sich dein Ticket schon rentiert?")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, Theme.Spacing.s)
            }
            .padding(24)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
    }

    // MARK: Pieces

    private var background: some View {
        ZStack {
            Theme.background
            LinearGradient(colors: [Theme.background, Theme.dusk.opacity(0.32), Theme.dawn.opacity(0.30)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.alpenglow.opacity(0.35), Theme.alpenglow.opacity(0)],
                           center: UnitPoint(x: 0.78, y: 0.62), startRadius: 0, endRadius: 220)
            RadialGradient(colors: [Theme.glacier.opacity(0.22), Theme.glacier.opacity(0)],
                           center: UnitPoint(x: 0.1, y: 0.05), startRadius: 0, endRadius: 260)
        }
    }

    private var brandRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 28, height: 28)
                .background(Theme.ctaGradient, in: .rect(cornerRadius: 8, style: .continuous))
            Text("KlimaBilanz")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
            Text(Format.date(Date(), .abbreviated))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var numeral: some View {
        HStack(alignment: .top, spacing: 2) {
            // Spec §4.3 like the hero: never "100" before the break-even.
            Text(Format.number(SummitFigures.percent(summary.amortizedFraction)))
                .font(.system(size: 84, weight: .thin, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("%")
                .font(.system(size: 32, weight: .light, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 12)
            Spacer(minLength: 0)
        }
    }

    private var valueLine: String {
        "amortisiert · \(SummitFigures.euro(summary.shownTotalEuro)) von \(SummitFigures.euro(summary.ticketPrice))"
    }

    private var verdictLine: String {
        if summary.isPaidOff {
            if let date = summary.paidOffDate {
                return "✓ Rentiert seit \(Format.dayMonth(date)) · + \(SummitFigures.euro(summary.shownProfitEuro))"
            }
            return "✓ Rentiert · + \(SummitFigures.euro(summary.shownProfitEuro))"
        }
        if let date = summary.forecastBreakEvenDate, summary.forecastReachesBreakEven {
            return "⚑ Break-even voraussichtlich \(Format.dayMonth(date))"
        }
        return "Noch \(SummitFigures.euro(summary.shownRemainingEuro)) bis zum Gipfel"
    }

    private var statsRow: some View {
        let co2 = StatsCalc.co2Parts(summary.co2SavedKg)
        return HStack(spacing: 0) {
            stat(value: "\(summary.tripCount)", unit: nil, label: "Fahrten")
            divider
            stat(value: Format.number(summary.distanceKm), unit: "km", label: "unterwegs")
            divider
            stat(value: co2.value, unit: co2.unit, label: "CO₂ gespart")
        }
        .padding(.vertical, 12)
        .background(Theme.surface, in: .rect(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(width: 1, height: 30)
    }

    private func stat(value: String, unit: String?, label: String) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                if let unit {
                    Text(unit)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Rendering

    /// Renders the card at 3× (1080 × 1350 px). Called on export only (`StatsSharePayload`).
    @MainActor
    static func render(snapshot: AnalyticsSnapshot, ticketName: String) -> UIImage? {
        let card = StatsShareCard(snapshot: snapshot, ticketName: ticketName)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

/// Static summit mini chart for the share card (no animation or materials, so ImageRenderer captures it
/// fully): ridge with the summit at break-even, the value route in the route gradient, forecast, flag.
struct StatsShareSummit: View {
    let snapshot: AnalyticsSnapshot

    private var price: Double { snapshot.ticket.price }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let maxY = max(price * 1.15, (snapshot.series.map(\.value).max() ?? 0) * 1.05, 1)
            let summitDate = summitDay
            let summit = CGPoint(x: x(summitDate, width: size.width), y: y(price, maxY: maxY, height: size.height))
            let points = snapshot.series.map { CGPoint(x: x($0.date, width: size.width), y: y($0.value, maxY: maxY, height: size.height)) }
            ZStack(alignment: .topLeading) {
                RidgeShape(peakX: min(0.92, summit.x / max(size.width, 1) * 0.5 + 0.42), peakY: 0.42, seed: 3, roughness: 0.6)
                    .fill(Theme.dusk.opacity(0.22))
                RidgeShape(peakX: summit.x / max(size.width, 1), peakY: summit.y / max(size.height, 1), seed: 7, roughness: 0.42)
                    .fill(LinearGradient(colors: [Theme.onAccent.opacity(0.22), Theme.onAccent.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))
                RidgeShape(peakX: summit.x / max(size.width, 1), peakY: summit.y / max(size.height, 1), seed: 7, roughness: 0.42)
                    .stroke(Theme.onAccent.opacity(0.35), lineWidth: 1)
                if !snapshot.summary.isPaidOff, let last = points.last {
                    Path { path in
                        path.move(to: last)
                        path.addLine(to: summit)
                    }
                    .stroke(Theme.textSecondary, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 5]))
                }
                SmoothPath(points: points)
                    .stroke(Theme.routeGradient, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                    .blur(radius: 6)
                    .opacity(0.5)
                SmoothPath(points: points)
                    .stroke(Theme.routeGradient, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                FlagShape()
                    .fill(Theme.summit)
                    .frame(width: 16, height: 24)
                    .position(x: summit.x + 7, y: summit.y - 12)
                Circle()
                    .fill(Theme.summit)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Theme.onAccent, lineWidth: 1.5))
                    .position(summit)
                if let last = points.last {
                    Circle()
                        .fill(Theme.onAccent)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Theme.dusk, lineWidth: 3))
                        .position(last)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var summitDay: Date {
        if snapshot.summary.isPaidOff, let crossing = snapshot.series.first(where: { $0.value >= price })?.date { return crossing }
        if let date = snapshot.summary.forecastBreakEvenDate, date <= snapshot.ticket.end { return date }
        return snapshot.ticket.end
    }

    private func x(_ date: Date, width: CGFloat) -> CGFloat {
        let total = max(snapshot.ticket.end.timeIntervalSince(snapshot.ticket.start), 1)
        let fraction = min(max(date.timeIntervalSince(snapshot.ticket.start) / total, 0), 1)
        return CGFloat(fraction) * width
    }

    private func y(_ value: Double, maxY: Double, height: CGFloat) -> CGFloat {
        height - CGFloat(min(max(value / maxY, 0), 1)) * height * 0.9
    }
}
