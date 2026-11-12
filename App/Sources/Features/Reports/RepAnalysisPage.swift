import SwiftUI
import Charts
import KlimaCore

// Page 2 of "Dein KlimaTicket-Jahr": the analysis (split from RepReportPages.swift).

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
