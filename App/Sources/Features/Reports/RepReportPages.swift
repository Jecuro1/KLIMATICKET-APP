import SwiftUI
import UIKit
import Charts
import KlimaCore

// The printed pages of "Dein KlimaTicket-Jahr" (A4 portrait, 595 × 842 pt, always the light theme).
// Only plain SwiftUI drawing (shapes, gradients, text, Swift Charts) – no materials or glass, so ImageRenderer
// produces crisp vector PDF pages.

enum RepPrint {
    static let pageSize = CGSize(width: 595.28, height: 841.89)
    static let margin: CGFloat = 44
    static let top: CGFloat = 40
    static let bottom: CGFloat = 26
    static let footerHeight: CGFloat = 24

    /// Soft panel fill on white paper.
    static let panel = Color(hex: "#F2F5F9")
    static let panelStroke = Color(hex: "#E2E8F0")
    static let zebra = Color(hex: "#F8FAFC")

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular, rounded: Bool = false) -> Font {
        .system(size: size, weight: weight, design: rounded ? .rounded : .default)
    }
}

/// Uppercase print eyebrow.
struct RepPrintKicker: View {
    var text: String
    var color: Color = Theme.textSecondary

    var body: some View {
        Text(text.uppercased(with: Format.locale))
            .font(RepPrint.font(7.5, .semibold))
            .tracking(1.1)
            .foregroundStyle(color)
    }
}

/// White A4 page with margins and the footer "Erstellt mit KlimaBilanz · keine offizielle Auswertung · Seite x von y".
struct RepPrintPage<Content: View, Backdrop: View>: View {
    var number: Int
    var count: Int
    @ViewBuilder var backdrop: Backdrop
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            RepPrintFooter(number: number, count: count)
                .frame(height: RepPrint.footerHeight)
        }
        .padding(.horizontal, RepPrint.margin)
        .padding(.top, RepPrint.top)
        .padding(.bottom, RepPrint.bottom)
        .frame(width: RepPrint.pageSize.width, height: RepPrint.pageSize.height)
        .background(alignment: .top) { backdrop }
        .background(Color.white)
        .clipped()
        .environment(\.colorScheme, .light)
        .environment(\.locale, Format.locale)
        .environment(\.dynamicTypeSize, .large)
    }
}

extension RepPrintPage where Backdrop == EmptyView {
    init(number: Int, count: Int, @ViewBuilder content: () -> Content) {
        self.number = number
        self.count = count
        self.backdrop = EmptyView()
        self.content = content()
    }
}

struct RepPrintFooter: View {
    var number: Int
    var count: Int

    var body: some View {
        VStack(spacing: 6) {
            Rectangle().fill(RepPrint.panelStroke).frame(height: 0.5)
            HStack(spacing: 6) {
                RepPrintLogo(size: 11)
                Text("Erstellt mit KlimaBilanz · keine offizielle Auswertung")
                    .font(RepPrint.font(7))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 8)
                Text("Seite \(number) von \(count)")
                    .font(RepPrint.font(7, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

/// Brand tile (gradient square with the mountain glyph).
struct RepPrintLogo: View {
    var size: CGFloat

    var body: some View {
        Image(systemName: "mountain.2.fill")
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.ctaGradient, in: .rect(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// Section title on a print page.
struct RepPrintSectionTitle: View {
    var kicker: String
    var title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            RepPrintKicker(text: kicker, color: Theme.accentText)
            Text(title)
                .font(RepPrint.font(21, .bold, rounded: true))
                .foregroundStyle(Theme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(RepPrint.font(9.5))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Rounded light panel with an eyebrow.
struct RepPrintPanel<Content: View>: View {
    var title: String?
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { RepPrintKicker(text: title) }
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RepPrint.panel, in: .rect(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Page 1: cover

struct RepCoverPage: View {
    let data: RepReportData
    var number: Int
    var count: Int
    var skyImage: UIImage? = nil

    static let skyHeight: CGFloat = 392

    private var summary: SavingsSummary { data.summary }

    var body: some View {
        RepPrintPage(number: number, count: count) {
            RepCoverSky(data: data, backdropImage: skyImage)
                .frame(width: RepPrint.pageSize.width, height: RepCoverPage.skyHeight)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    brandRow
                    titleBlock
                        .padding(.top, 28)
                }
                .frame(height: RepCoverPage.skyHeight - RepPrint.top - 6, alignment: .top)
                payoffBlock
                RepPrintProgress(fraction: summary.amortizedFraction)
                    .frame(height: 9)
                    .padding(.top, 14)
                kpis
                    .padding(.top, 22)
                highlights
                    .padding(.top, 20)
                Spacer(minLength: 12)
                ticketStrip
            }
        }
    }

    private var brandRow: some View {
        HStack(spacing: 8) {
            RepPrintLogo(size: 24)
            Text("KlimaBilanz")
                .font(RepPrint.font(14, .bold, rounded: true))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                RepPrintKicker(text: "Jahresbericht")
                Text("Stand \(RepText.longDate(data.generatedAt))")
                    .font(RepPrint.font(7.5))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            RepPrintKicker(text: "Dein KlimaTicket-Jahr", color: Theme.accentText)
            Text(data.yearLabel)
                .font(RepPrint.font(56, .bold, rounded: true))
                .foregroundStyle(Theme.textPrimary)
                .padding(.vertical, -4)
            Text([data.ticketName, data.holderName].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(RepPrint.font(12, .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.82))
            Text(data.validityText)
                .font(RepPrint.font(9.5))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var payoffBlock: some View {
        HStack(alignment: .center, spacing: 16) {
            HStack(alignment: .top, spacing: 2) {
                // Spec §4.3 like the app's hero: never "100" before the break-even.
                Text(Format.number(SummitFigures.percent(summary.amortizedFraction)))
                    .font(.system(size: 104, weight: .ultraLight, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("%")
                    .font(.system(size: 38, weight: .light, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 16)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("amortisiert")
                    .font(RepPrint.font(15, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(data.verdict)
                    .font(RepPrint.font(10.5, .semibold))
                    .foregroundStyle(summary.isPaidOff ? Theme.positiveText : Theme.summitText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(SummitFigures.euro(summary.shownTotalEuro)) Fahrtenwert von \(SummitFigures.euro(data.ownShare)) \(data.employerContribution > 0 ? "Eigenanteil" : "Ticketpreis")")
                    .font(RepPrint.font(9.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var kpis: some View {
        let co2 = StatsCalc.co2Parts(summary.co2SavedKg)
        return HStack(spacing: 10) {
            if summary.isPaidOff {
                RepPrintKPI(value: "+ \(SummitFigures.euro(summary.shownProfitEuro))", unit: nil, label: "gespart", symbol: "eurosign", tint: Theme.pine)
            } else {
                RepPrintKPI(value: SummitFigures.euro(summary.shownRemainingEuro), unit: nil, label: "noch bis zum Gipfel",
                            symbol: "flag.fill", tint: Theme.dawn)
            }
            RepPrintKPI(value: Format.number(Double(summary.tripCount)), unit: nil, label: summary.tripCount == 1 ? "Fahrt" : "Fahrten",
                        symbol: "tram.fill", tint: Theme.glacier)
            RepPrintKPI(value: Format.number(summary.distanceKm), unit: "km", label: "unterwegs", symbol: "point.topleft.down.to.point.bottomright.curvepath",
                        tint: Theme.dusk)
            RepPrintKPI(value: co2.value, unit: co2.unit, label: "CO₂ gespart", symbol: "leaf.fill", tint: Theme.pine)
        }
    }

    /// Four quiet facts under the KPI tiles (no panel – hairline dividers only).
    private var highlights: some View {
        let records = data.snapshot.records
        var facts: [(String, String)] = []
        if let best = records.bestMonth { facts.append(("Bester Monat", "\(StatsNames.wideMonth(best.month)) · \(Format.euro(best.value, decimals: 0))")) }
        if let longest = records.longestTrip { facts.append(("Längste Fahrt", Format.km(longest.distanceKm))) }
        facts.append(("Reisetage", "\(summary.travelDays)"))
        facts.append(("Ø pro Fahrt", Format.euroPrecise(summary.averageValuePerTrip)))
        return HStack(alignment: .top, spacing: 0) {
            ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                if index > 0 {
                    Rectangle().fill(RepPrint.panelStroke).frame(width: 0.6, height: 30)
                        .padding(.horizontal, 12)
                }
                VStack(alignment: .leading, spacing: 3) {
                    RepPrintKicker(text: fact.0)
                    Text(fact.1)
                        .font(RepPrint.font(11, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 2)
    }

    private var ticketStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 0) {
                stripCell("Ticket", data.ticketName)
                stripCell("Gültig", "\(Format.date(data.period.start, .numeric)) – \(Format.date(data.period.end, .numeric))")
                stripCell(data.employerContribution > 0 || data.addOnPrice > 0 ? "Eigenanteil" : "Ticketpreis", priceText)
                stripCell("Zahlung", data.isMonthlyPayment ? "12 Monatsraten" : "Einmalzahlung")
            }
            if !extraLines.isEmpty {
                Rectangle().fill(RepPrint.panelStroke).frame(height: 0.5)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(extraLines, id: \.self) { line in
                        Text(line)
                            .font(RepPrint.font(8.5))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RepPrint.panel, in: .rect(cornerRadius: 14, style: .continuous))
    }

    private var priceText: String {
        Format.euro(data.ownShare, decimals: data.ownShare == data.ownShare.rounded() ? 0 : 2)
    }

    private var extraLines: [String] {
        var lines: [String] = []
        if data.employerContribution > 0 || data.addOnPrice > 0 {
            var parts = ["Ticketpreis \(Format.euro(data.listPrice))"]
            if data.addOnPrice > 0 { parts.append("+ Zusatzpakete \(Format.euro(data.addOnPrice))") }
            if data.employerContribution > 0 { parts.append("– Arbeitgeber-Zuschuss \(Format.euro(data.employerContribution))") }
            lines.append(parts.joined(separator: " ") + " = Eigenanteil \(Format.euro(data.ownShare)). Die Amortisation zählt gegen deinen Eigenanteil.")
        }
        if data.benefitsValue > 0 {
            lines.append("Dazu \(Format.euroPrecise(data.benefitsValue)) Zusatz-Ersparnis durch \(data.benefitsCount == 1 ? "1 genutzten Vorteil" : "\(data.benefitsCount) genutzte Vorteile") – getrennt von der Amortisation.")
        }
        if data.inducedTrips > 0 {
            lines.append("\(RepText.trips(data.inducedTrips)) (\(Format.euro(data.inducedValue, decimals: 0))) hättest du ohne Ticket nicht gemacht – Mehrwert, aber kein gespartes Geld.")
        }
        return lines
    }

    private func stripCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            RepPrintKicker(text: title)
            Text(value)
                .font(RepPrint.font(9.5, .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 8)
    }
}

/// KPI tile on paper.
struct RepPrintKPI: View {
    var value: String
    var unit: String?
    var label: String
    var symbol: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .background(tint.opacity(0.14), in: .circle)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(RepPrint.font(19, .bold, rounded: true))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                if let unit {
                    Text(unit)
                        .font(RepPrint.font(9.5, .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(label)
                .font(RepPrint.font(8.5))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RepPrint.panel, in: .rect(cornerRadius: 12, style: .continuous))
    }
}

/// Amortisation bar: route gradient up to 100 %, pine "Gewinnzone" beyond, summit tick at the ticket price.
struct RepPrintProgress: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let scale = max(1, fraction)
            let summitX = w / scale
            ZStack(alignment: .leading) {
                Capsule().fill(RepPrint.panel)
                Capsule().fill(Theme.routeGradient)
                    .frame(width: max(geo.size.height, min(fraction, 1) / scale * w))
                if fraction > 1 {
                    Capsule().fill(Theme.pine)
                        .frame(width: max(geo.size.height, w - summitX + geo.size.height / 2))
                        .offset(x: summitX - geo.size.height / 2)
                }
                Rectangle()
                    .fill(Theme.dawn)
                    .frame(width: 2, height: geo.size.height + 8)
                    .offset(x: min(summitX, w) - 1)
            }
        }
    }
}

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

// MARK: - Page 2: analysis

struct RepAnalysisPage: View {
    let data: RepReportData
    var number: Int
    var count: Int

    private var summary: SavingsSummary { data.summary }

    var body: some View {
        RepPrintPage(number: number, count: count) {
            VStack(alignment: .leading, spacing: 14) {
                RepPrintSectionTitle(kicker: "Auswertung · \(data.yearLabel)", title: "Monat für Monat",
                                     subtitle: "So hat sich dein Ticket über das Jahr gefüllt – und was es dir gebracht hat.")
                RepPrintPanel(title: "Fahrtenwert pro Monat") {
                    RepMonthlyChart(data: data)
                        .frame(height: 158)
                }
                HStack(alignment: .top, spacing: 12) {
                    RepPrintPanel(title: "Verkehrsmittel") {
                        VStack(alignment: .leading, spacing: 10) {
                            RepModeBars(data: data)
                            Spacer(minLength: 0)
                            // With up to four modes the panel has room under the bars (the records panel sets the height).
                            if (1...4).contains(data.modes.count) {
                                RepModeDonutRow(data: data)
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(maxHeight: .infinity)
                    RepPrintPanel(title: "Rekorde") {
                        RepRecordsList(data: data)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(maxHeight: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
                costs
                HStack(alignment: .top, spacing: 12) {
                    RepPrintPanel(title: "Top-Strecken") {
                        RepTopRoutes(data: data, limit: data.categories.isEmpty ? 5 : 4)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(maxHeight: .infinity)
                    if !data.categories.isEmpty {
                        RepPrintPanel(title: "Wofür du gefahren bist") {
                            RepCategoryList(data: data)
                                .frame(maxHeight: .infinity, alignment: .top)
                        }
                        .frame(width: 190)
                        .frame(maxHeight: .infinity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                methodology
            }
        }
    }

    private var costs: some View {
        HStack(spacing: 10) {
            RepPrintCost(value: data.costPerTrip.map(Format.euroPrecise) ?? "–", label: "pro Fahrt")
            RepPrintCost(value: summary.effectivePricePerKm.map { Format.euroPrecise($0) } ?? "–", label: "pro Kilometer")
            RepPrintCost(value: Format.euroPrecise(summary.costPerDay), label: "pro Tag")
            RepPrintCost(value: Format.euro(data.car.carCost, decimals: 0), label: "mit dem Auto*")
        }
    }

    private var methodology: some View {
        Text("So rechnet KlimaBilanz: Wert einer Fahrt = Normalpreis ohne KlimaTicket (ÖBB-Standardticket 2. Klasse nach offizieller Relationspreis-Tabelle bzw. Bahnkilometern, in Städten der Einzelfahrschein der Kernzone) – geschätzt oder von dir angepasst. Ticketpreis = Preis laut Gültigkeitsbeginn inkl. Zusatzpaketen, abzüglich Arbeitgeber-Zuschuss. CO₂ im Vergleich zur selben Strecke allein im Pkw (Umweltbundesamt). *Auto: wie in „Öffis vs. Auto“ – \(WorkCarCalc.modeSummary(data.car)) auf Straßenkilometern. Alle Angaben ohne Gewähr.")
            .font(RepPrint.font(7))
            .foregroundStyle(Theme.textSecondary)
            .lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct RepPrintCost: View {
    var value: String
    var label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(RepPrint.font(14, .bold, rounded: true))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(RepPrint.font(8))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RepPrint.panel, in: .rect(cornerRadius: 12, style: .continuous))
    }
}

/// Monthly value bars with the monthly target ("Soll") and value labels.
struct RepMonthlyChart: View {
    let data: RepReportData

    private var domainMax: Double { max(max(data.months.map(\.value).max() ?? 0, data.monthlyTarget) * 1.22, 1) }

    var body: some View {
        Chart {
            RepMonthBars(months: data.months)
            RepTargetRule(target: data.monthlyTarget)
        }
        .chartYScale(domain: 0...domainMax)
        .chartXAxis { xAxis }
        .chartYAxis { yAxis }
    }

    private var xAxis: some AxisContent {
        AxisMarks { value in
            AxisValueLabel {
                if let id = value.as(String.self), let month = data.months.first(where: { $0.id == id }) {
                    Text(month.label)
                        .font(RepPrint.font(7, month.isBest ? .bold : .regular))
                        .foregroundStyle(month.isFuture ? Theme.textTertiary : Theme.textSecondary)
                }
            }
        }
    }

    private var yAxis: some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4))
                .foregroundStyle(RepPrint.panelStroke)
            AxisValueLabel {
                if let v = value.as(Double.self) {
                    Text(Format.euro(v, decimals: 0))
                        .font(RepPrint.font(6.5))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }
}

struct RepMonthBars: ChartContent {
    let months: [RepReportData.MonthLine]

    var body: some ChartContent {
        ForEach(months) { month in
            BarMark(x: .value("Monat", month.id), y: .value("Wert", month.value), width: .ratio(0.62))
                .foregroundStyle(RepMonthBars.style(month))
                .cornerRadius(3)
                .annotation(position: .top, spacing: 2) {
                    if month.value > 0 {
                        Text(Format.euro(month.value, decimals: 0))
                            .font(RepPrint.font(6.5, .semibold))
                            .foregroundStyle(month.isBest ? Theme.summitText : Theme.textSecondary)
                    }
                }
        }
    }

    static func style(_ month: RepReportData.MonthLine) -> LinearGradient {
        month.isBest
            ? LinearGradient(colors: [Theme.dawn, Theme.dusk], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Theme.glacier2, Theme.glacier], startPoint: .top, endPoint: .bottom)
    }
}

struct RepTargetRule: ChartContent {
    let target: Double

    var body: some ChartContent {
        RuleMark(y: .value("Soll", target))
            .foregroundStyle(Theme.dawn)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .annotation(position: .top, alignment: .trailing, spacing: 1) {
                Text("Soll \(Format.euro(target, decimals: 0)) / Monat")
                    .font(RepPrint.font(6.5, .semibold))
                    .foregroundStyle(Theme.summitText)
            }
    }
}

/// Direct-labelled horizontal bars per transport mode ("Zug · 59 Fahrten · 68 %").
struct RepModeBars: View {
    let data: RepReportData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if data.modes.isEmpty {
                Text("Noch keine Fahrten")
                    .font(RepPrint.font(8.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(data.modes.prefix(6)) { line in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        ModeIcon(mode: line.mode, size: 14)
                        Text(line.mode.displayName)
                            .font(RepPrint.font(8.5, .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(line.trips == 1 ? "1 Fahrt" : "\(line.trips) Fahrten")
                            .font(RepPrint.font(7.5))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer(minLength: 4)
                        Text("\(Format.euro(line.value, decimals: 0)) · \(Format.percent(line.share))")
                            .font(RepPrint.font(7.5, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white)
                            Capsule().fill(Theme.modeColor(line.mode))
                                .frame(width: max(4, geo.size.width * min(max(line.share, 0), 1)))
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
    }
}

/// Mode split at a glance: a small donut (share of the trip value) with the trip count inside, plus a one-line summary.
struct RepModeDonutRow: View {
    let data: RepReportData

    var body: some View {
        HStack(spacing: 12) {
            Chart(data.modes) { line in
                SectorMark(angle: .value("Wert", line.value), innerRadius: .ratio(0.64), angularInset: 1.2)
                    .cornerRadius(2)
                    .foregroundStyle(Theme.modeColor(line.mode))
            }
            .chartLegend(.hidden)
            .frame(width: 50, height: 50)
            .overlay {
                VStack(spacing: -1) {
                    Text("\(data.summary.tripCount)")
                        .font(RepPrint.font(12, .bold, rounded: true))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    Text("Fahrten")
                        .font(RepPrint.font(5.5, .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 30)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let top = data.modes.first {
                    Text("\(top.mode.displayName) bringt \(Format.percent(top.share)) des Werts")
                        .font(RepPrint.font(8.5, .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Text(data.modes.count == 1 ? "1 Verkehrsmittel genutzt" : "\(data.modes.count) Verkehrsmittel genutzt")
                    .font(RepPrint.font(7.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

struct RepRecordsList: View {
    let data: RepReportData

    var body: some View {
        let records = data.snapshot.records
        let summary = data.summary
        VStack(alignment: .leading, spacing: 6) {
            if let t = records.longestTrip {
                row("Längste Fahrt", "\(Format.km(t.distanceKm)) · \(TripRow.short(t.fromName)) → \(TripRow.short(t.toName))")
            }
            if let t = records.mostValuableTrip {
                row("Wertvollste Fahrt", "\(Format.euroPrecise(t.totalValue)) · \(TripRow.short(t.fromName)) → \(TripRow.short(t.toName))")
            }
            if let m = records.bestMonth {
                row("Bester Monat", "\(StatsNames.wideMonth(m.month)) · \(Format.euro(m.value, decimals: 0))")
            }
            row("Reisetage", "\(Format.days(summary.travelDays)) · längste Serie \(Format.days(records.longestStreakDays))")
            row("Bundesländer", records.statesVisited.isEmpty ? "–" : "\(records.statesVisited.filter { $0 != FederalState.foreign.rawValue }.count) von 9")
            row("Ø pro Fahrt", Format.euroPrecise(summary.averageValuePerTrip))
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(RepPrint.font(7.5))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(RepPrint.font(8.5, .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

struct RepTopRoutes: View {
    let data: RepReportData
    var limit: Int

    var body: some View {
        VStack(spacing: 0) {
            if data.snapshot.topRoutes.isEmpty {
                Text("Noch keine Strecken")
                    .font(RepPrint.font(8.5))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(data.snapshot.topRoutes.prefix(limit).enumerated()), id: \.element.id) { index, route in
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(RepPrint.font(8, .bold, rounded: true))
                        .foregroundStyle(Theme.accentText)
                        .frame(width: 12, alignment: .leading)
                    Text("\(TripRow.short(route.fromName)) ↔ \(TripRow.short(route.toName))")
                        .font(RepPrint.font(8.5, .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(route.trips == 1 ? "1 Fahrt" : "\(route.trips) Fahrten")
                        .font(RepPrint.font(7.5))
                        .foregroundStyle(Theme.textSecondary)
                    Text(Format.euro(route.value, decimals: 0))
                        .font(RepPrint.font(8.5, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 46, alignment: .trailing)
                }
                .padding(.vertical, 4)
                if index < min(limit, data.snapshot.topRoutes.count) - 1 {
                    Rectangle().fill(RepPrint.panelStroke).frame(height: 0.5)
                }
            }
        }
    }
}

struct RepCategoryList: View {
    let data: RepReportData

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(data.categories.prefix(5)) { line in
                HStack(spacing: 6) {
                    Image(systemName: line.category.symbolName)
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(Theme.gold)
                        .frame(width: 12)
                    Text(line.category.displayName)
                        .font(RepPrint.font(8.5, .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 4)
                    Text("\(line.trips) · \(Format.euro(line.value, decimals: 0))")
                        .font(RepPrint.font(7.5))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

// MARK: - Pages 3+: trip table

struct RepTablePage: View {
    let data: RepReportData
    let lines: [ReportPagination.Line]
    var isFirst: Bool
    var isLast: Bool
    var number: Int
    var count: Int

    static let monthHeight: Double = 25
    static let tripHeight: Double = 15.5
    static let columnHeaderHeight: Double = 20
    static let firstHeaderHeight: Double = 64
    static let totalHeight: Double = 30
    static let kmColumn: CGFloat = 36
    static let valueColumn: CGFloat = 60

    /// Usable table height (below the column header) on the first and the following table pages.
    static var firstCapacity: Double { bodyHeight - firstHeaderHeight - columnHeaderHeight }
    static var pageCapacity: Double { bodyHeight - columnHeaderHeight }
    static var bodyHeight: Double {
        Double(RepPrint.pageSize.height - RepPrint.top - RepPrint.bottom - RepPrint.footerHeight) - 8
    }

    private var summary: SavingsSummary { data.summary }

    var body: some View {
        RepPrintPage(number: number, count: count) {
            VStack(alignment: .leading, spacing: 0) {
                if isFirst {
                    RepPrintSectionTitle(kicker: "Fahrtenbuch · \(data.yearLabel)", title: "Alle Fahrten",
                                         subtitle: "\(RepText.trips(summary.tripCount)) · \(Format.km(summary.distanceKm)) · \(Format.euroPrecise(summary.totalValue)) Fahrtenwert")
                        .frame(height: Self.firstHeaderHeight, alignment: .topLeading)
                }
                columnHeader
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    switch line {
                    case .month(let start, let trips, let value, let km, let continued):
                        monthRow(start: start, trips: trips, value: value, km: km, continued: continued)
                    case .trip(let trip):
                        tripRow(trip, zebra: index % 2 == 0)
                    }
                }
                if isLast {
                    totalRow
                }
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Text("Datum").frame(width: 38, alignment: .leading)
            Text("Strecke").frame(maxWidth: .infinity, alignment: .leading)
            Text("Verkehrsmittel").frame(width: 78, alignment: .leading)
            Text("km").frame(width: Self.kmColumn, alignment: .trailing)
            Text("Wert").frame(width: Self.valueColumn, alignment: .trailing)
        }
        .font(RepPrint.font(6.5, .semibold))
        .tracking(0.4)
        .lineLimit(1)
        .textCase(.uppercase)
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 8)
        .frame(height: Self.columnHeaderHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.textPrimary.opacity(0.5)).frame(height: 0.6) }
    }

    private func monthRow(start: Date, trips: Int, value: Double, km: Double, continued: Bool) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: "\(StatsNames.wideMonth(start)) \(String(Calendar.vienna.component(.year, from: start)))\(continued ? " (Fortsetzung)" : "")")
                .font(RepPrint.font(9, .bold))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            if !continued {
                Text("\(RepText.trips(trips)) · \(Format.km(km)) · \(Format.euroPrecise(value))")
                    .font(RepPrint.font(7.5, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 19)
        .background(Theme.glacier.opacity(0.09), in: .rect(cornerRadius: 5, style: .continuous))
        .frame(height: Self.monthHeight, alignment: .bottom)
        .padding(.bottom, 0)
    }

    private func tripRow(_ trip: TripRecord, zebra: Bool) -> some View {
        HStack(spacing: 8) {
            Text(RepText.shortNumericDate(trip.date))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 38, alignment: .leading)
            HStack(spacing: 4) {
                Text("\(trip.fromName) → \(trip.toName)")
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let via = ViaText.subtitle(trip.via) {   // MARK: via – "über Feldkirch" after the route, first to shrink
                    Text(via)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(-1)
                }
                if trip.isRoundTrip {
                    Text("H+R")
                        .font(RepPrint.font(6, .bold))
                        .foregroundStyle(Theme.accentText)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Theme.glacier.opacity(0.12), in: .capsule)
                }
                if trip.isInduced {
                    Image(systemName: "sparkle")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(Theme.alpenglow)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                Circle().fill(Theme.modeColor(trip.mode)).frame(width: 5, height: 5)
                Text(trip.mode.displayName)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 78, alignment: .leading)
            Text(trip.totalDistanceKm > 0 ? Format.number(trip.totalDistanceKm, decimals: trip.totalDistanceKm < 10 ? 1 : 0) : "–")
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .frame(width: Self.kmColumn, alignment: .trailing)
            Text(Format.euroPrecise(trip.totalValue))
                .monospacedDigit()
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textPrimary)
                .frame(width: Self.valueColumn, alignment: .trailing)
        }
        .font(RepPrint.font(8))
        .padding(.horizontal, 8)
        .frame(height: Self.tripHeight)
        .background(zebra ? RepPrint.zebra : Color.white)
    }

    private var totalRow: some View {
        HStack(spacing: 8) {
            Text("Summe · \(RepText.trips(summary.tripCount))")
                .frame(maxWidth: .infinity, alignment: .leading)
            // Same column widths as the trip rows, so km and value line up with the columns above.
            Text(Format.number(summary.distanceKm))
                .frame(width: Self.kmColumn, alignment: .trailing)
            Text(Format.euroPrecise(summary.totalValue))
                .frame(width: Self.valueColumn, alignment: .trailing)
        }
        .font(RepPrint.font(9, .bold))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .monospacedDigit()
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .overlay(alignment: .top) { Rectangle().fill(Theme.textPrimary.opacity(0.5)).frame(height: 0.6) }
        .padding(.top, 8)
    }
}
