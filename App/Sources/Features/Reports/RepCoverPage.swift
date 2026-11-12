import SwiftUI
import UIKit
import KlimaCore

// Page 1 of "Dein KlimaTicket-Jahr": the cover (split from RepReportPages.swift; print primitives stay there).

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
