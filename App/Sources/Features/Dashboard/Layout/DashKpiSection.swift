import SwiftUI
import SwiftData
import KlimaCore

// MARK: uebersicht – „Kennzahlen“: up to four own figures in a 2 × 2 grid (one column at accessibility sizes). The values are KlimaCore
// `KpiCatalog` readings of the Übersicht's own snapshot – the numbers Statistik shows – formatted only through Format.* and the hero's
// own rounding (SummitFigures), so „Wert deiner Fahrten“ says the same euros as „€ … von € …“ under the summit.

/// The figures the Übersicht reads, from one snapshot.
enum DashKpiInput {
    /// `kinds`: the tiles that will be read (nil: all, for the picker) – the car comparison is worked out only when its tile is asked for.
    @MainActor
    static func make(snapshot: AnalyticsSnapshot, tripsNewestFirst trips: [TripEntity], catalog: TariffCatalog,
                     kinds: [KpiKind]? = nil) -> KpiInput {
        // MARK: review-uebersicht – „Auto-Vergleich“ is the comparison of Statistik › „Öffis vs. Auto“ and of the Bilanz card's car row
        // on the same screen (WorkCarCalc: road km, the car costs chosen in Einstellungen), not rail km × Kilometergeld (an eighth lower).
        let car = (kinds?.contains(.carComparison) ?? true)
            ? WorkCarCalc.result(period: snapshot.ticket, records: snapshot.trips, catalog: catalog) : nil
        return KpiInput(summary: snapshot.summary,
                        longestStreakDays: snapshot.records.longestStreakDays,
                        topRoute: snapshot.topRoutes.first,
                        tripsThisWeek: DashWeekStats.make(fromNewestFirst: trips).trips,
                        ticketYear: StatsCalc.ticketYearLabel(snapshot.ticket),
                        carCost: car.flatMap { $0.tripCount > 0 && $0.carCost > 0 ? $0.carCost : nil })
    }
}

/// A reading as the tile shows it.
struct KpiDisplay: Equatable {
    enum Tone: Equatable { case plain, positive, open }

    /// The big part („€ 1.044“, „87“, „Innsbruck Hbf ↔ Wörgl Hbf“).
    var value: String
    /// The small part after it („Fahrten“, „km“, „noch offen“).
    var unit: String?
    /// What the digits roll with.
    var rolling: Double
    var tone: Tone = .plain
    var isText = false
    /// VoiceOver: the value in words.
    var spoken: String

    static func make(_ reading: KpiReading, summary: SavingsSummary) -> KpiDisplay {
        if let text = reading.text {
            let count = reading.count.map(GoalText.trips)
            return KpiDisplay(value: text, unit: count, rolling: Double(reading.count ?? 0), isText: true,
                              spoken: [text.replacingOccurrences(of: " ↔ ", with: " und "), count].compactMap { $0 }.joined(separator: ", "))
        }
        guard let v = reading.value else { return KpiDisplay(value: "–", unit: nil, rolling: 0, spoken: "noch keine Angabe") }
        switch reading.kind {
        case .totalValue:
            let shown = summary.shownTotalEuro
            return KpiDisplay(value: SummitFigures.euro(shown), unit: nil, rolling: shown, spoken: SummitFigures.euro(shown))
        case .net:
            if summary.isPaidOff {
                let profit = summary.shownProfitEuro
                return KpiDisplay(value: "+ " + SummitFigures.euro(profit), unit: nil, rolling: profit, tone: .positive,
                                  spoken: "plus " + SummitFigures.euro(profit))
            }
            let open = summary.shownRemainingEuro
            return KpiDisplay(value: SummitFigures.euro(open), unit: "noch offen", rolling: open, tone: .open,
                              spoken: "noch \(SummitFigures.euro(open)) offen")
        case .tripCount, .tripsThisWeek:
            // The title already says „Fahrten“ – the number stands alone.
            let n = Int(v.rounded())
            return KpiDisplay(value: Format.number(Double(n)), unit: nil, rolling: Double(n), spoken: GoalText.trips(n))
        case .travelDays, .longestStreak, .daysRemaining:
            let n = Int(v.rounded())
            return KpiDisplay(value: Format.number(Double(n)), unit: n == 1 ? "Tag" : "Tage", rolling: Double(n), spoken: Format.days(n))
        case .distance:
            // One decimal under 10 km, like Format.km in Statistik.
            let number = Format.number(v, decimals: v < 10 ? 1 : 0)
            return KpiDisplay(value: number, unit: "km", rolling: v.rounded(), spoken: number + " Kilometer")
        case .co2:
            let parts = AppearanceRuntime.format.co2Parts(kg: v)   // the Bilanz card's rule (Look & Feel › Zahlen › CO₂)
            let number = Format.number(parts.value, decimals: parts.decimals)
            return KpiDisplay(value: number, unit: parts.unit, rolling: v.rounded(),
                              spoken: number + (parts.unit == "t" ? " Tonnen" : " Kilogramm"))
        case .averageValue, .costPerDay, .valuePerDay, .pricePerKm:
            return KpiDisplay(value: Format.euroPrecise(v), unit: nil, rolling: v, spoken: Format.euroPrecise(v))
        case .carComparison, .forecastEndValue:
            return KpiDisplay(value: Format.euro(v, decimals: 0), unit: nil, rolling: v.rounded(), spoken: Format.euro(v, decimals: 0))
        case .favoriteRoute:
            return KpiDisplay(value: "–", unit: nil, rolling: 0, spoken: "noch keine Angabe")
        }
    }
}

extension KpiKind {
    /// The tile's symbol colour (a filled circle behind the symbol – an area, so the plain accent colours are fine).
    var tint: Color {
        switch self {
        case .totalValue, .net, .averageValue, .valuePerDay: Theme.accent
        case .tripCount, .tripsThisWeek, .travelDays: Theme.glacier
        case .co2: Theme.eco
        case .distance, .pricePerKm, .forecastEndValue: Theme.dusk
        case .costPerDay, .daysRemaining, .carComparison: Theme.summit
        case .longestStreak: Theme.gold
        case .favoriteRoute: Theme.alpenglow
        }
    }
}

/// The Übersicht's card.
struct DashKpiSection: View {
    let snapshot: AnalyticsSnapshot
    let trips: [TripEntity]

    @Environment(AppState.self) private var app
    private var store: DashLayoutStore { .shared }

    var body: some View {
        let kinds = store.kpis.kinds
        if !kinds.isEmpty {
            let input = DashKpiInput.make(snapshot: snapshot, tripsNewestFirst: trips, catalog: app.catalog, kinds: kinds)
            VStack(alignment: .leading, spacing: DashStyle.cardSpacing) {
                SectionHeader(title: "Kennzahlen", actionTitle: "Anpassen") { store.openEditor(at: .kpis) }
                    .padding(.horizontal, DashStyle.headerInset)
                DashKpiGrid(readings: KpiCatalog.readings(kinds, input: input), summary: snapshot.summary)
            }
            .motionTransition(.rise)
        }
    }
}

/// Two columns of tiles (one at accessibility sizes); also the editor's live preview.
struct DashKpiGrid: View {
    let readings: [KpiReading]
    let summary: SavingsSummary
    var compact = false

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // A Grid (not a lazy one): the two tiles of a row share its height. One column at accessibility sizes.
        let perRow = typeSize.isAccessibilitySize ? 1 : 2
        let rows = stride(from: 0, to: readings.count, by: perRow).map { Array(readings[$0..<min($0 + perRow, readings.count)]) }
        Grid(horizontalSpacing: DashStyle.cardSpacing, verticalSpacing: DashStyle.cardSpacing) {
            ForEach(rows, id: \.first?.kind) { row in
                GridRow {
                    ForEach(row) { reading in
                        DashKpiTile(reading: reading, display: KpiDisplay.make(reading, summary: summary), compact: compact)
                            .motionTransition(.pop)
                    }
                    if row.count < perRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            }
        }
        .motionAnimation(Motion.smooth, value: readings.map(\.kind))
    }
}

/// One figure: symbol, the value (its digits roll), the title and what it is about. One VoiceOver element.
struct DashKpiTile: View {
    let reading: KpiReading
    let display: KpiDisplay
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? Theme.Spacing.xxs : Theme.Spacing.xs) {
            Image(systemName: reading.kind.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(reading.kind.tint)
                .frame(width: 28, height: 28)
                .background(reading.kind.tint.opacity(0.15), in: .circle)
            valueLine
            Text(reading.kind.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(reading.subtitle)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
        }
        .padding(compact ? Theme.Spacing.s : Theme.Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frostedCard(cornerRadius: Theme.Radius.tile)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.kind.title)
        .accessibilityValue("\(display.spoken), \(reading.subtitle)")
    }

    @ViewBuilder
    private var valueLine: some View {
        if display.isText {
            VStack(alignment: .leading, spacing: 2) {
                Text(display.value)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let unit = display.unit {
                    Text(unit)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                        .numericValue(display.rolling)
                }
            }
        } else {
            // A number keeps its unit on the line; at the largest sizes the unit may wrap under it.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 4) { number; unit }
                VStack(alignment: .leading, spacing: 0) { number; unit }
            }
        }
    }

    private var number: some View {
        Text(display.value)
            .font(.system(compact ? .title3 : .title2, design: .rounded, weight: .bold).monospacedDigit())
            .foregroundStyle(display.tone == .positive ? Theme.positiveText : Theme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .numericValue(display.rolling)
    }

    @ViewBuilder
    private var unit: some View {
        if let unit = display.unit {
            Text(unit)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(display.tone == .open ? Theme.summitText : Theme.textSecondary)
                .lineLimit(1)
        }
    }
}
