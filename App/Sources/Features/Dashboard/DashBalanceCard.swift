import SwiftUI
import KlimaCore

/// "Bilanz-Karte" (DESIGN.md §5.1 · 4, spec §8.3) – complements the hero instead of repeating its verdict:
/// Row A: when the summit is reached (forecast) and the buffer before the ticket expires,
/// Row B: three key figures (Fahrten · km · CO₂),
/// Row C: the car comparison, once (tap → "Öffis vs. Auto", which explains and configures it).
struct DashBalanceCard: View {
    var snapshot: AnalyticsSnapshot
    /// The same car comparison as Statistik › "Öffis vs. Auto" (`WorkCarCalc`: road km, the chosen car-cost mode,
    /// the own share of the ticket) – the Übersicht must not show a second, differently calculated car figure.
    var car: CarComparisonResult
    var now: Date = Date()

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var summary: SavingsSummary { snapshot.summary }
    private var isExpired: Bool { now > snapshot.ticket.end }
    private var showsCarRow: Bool { car.tripCount > 0 && car.carCost > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            forecastRow
                .padding(.top, 14)
                .padding(.bottom, 12)
            hairline
            DashMiniStatsRow(items: statItems)
                .padding(.vertical, 10)
            if showsCarRow {
                hairline
                    .padding(.horizontal, -Theme.Spacing.m)
                carRow
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.bottom, showsCarRow ? 0 : 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frostedCard(cornerRadius: Theme.Radius.card, tint: summary.isPaidOff ? Theme.positive : nil)
    }

    // MARK: Row A – forecast and buffer

    private enum Phase {
        case paidOff
        case onTrack(Date)
        case behind
        case expired
    }

    private var phase: Phase {
        if summary.isPaidOff { return .paidOff }
        if isExpired { return .expired }
        if let date = summary.forecastBreakEvenDate, summary.forecastReachesBreakEven { return .onTrack(date) }
        return .behind
    }

    @ViewBuilder
    private var forecastRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                primaryColumn
                hairline
                secondaryColumn
            }
        } else {
            HStack(alignment: .top, spacing: 0) {
                primaryColumn
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 128, alignment: .leading)
                    .padding(.trailing, 14)
                Rectangle()
                    .fill(Theme.separator)
                    .frame(width: 1)
                    .accessibilityHidden(true)
                secondaryColumn
                    .padding(.leading, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var primaryColumn: some View {
        switch phase {
        case .paidOff:
            column(label: "Gewinn bisher", detail: freeTripsText) {
                DashEuroNumeral(amount: summary.shownProfitEuro, sign: "+", color: Theme.positiveText)
            }
        case .onTrack(let date):
            column(label: "Break-even · Prognose",
                   detail: "\(weekday(date)) · \(DashStyle.inDays(DashStyle.dayCount(from: now, to: date)))") {
                bigText(Format.dayMonth(date))
            }
        case .behind:
            column(label: "Noch bis zum Gipfel", detail: tripsToGoText) {
                DashEuroNumeral(amount: summary.shownRemainingEuro)
            }
        case .expired:
            column(label: "Fehlte zum Gipfel", detail: "Ticket abgelaufen") {
                DashEuroNumeral(amount: summary.shownRemainingEuro)
            }
        }
    }

    @ViewBuilder
    private var secondaryColumn: some View {
        let end = snapshot.ticket.end
        switch phase {
        case .paidOff:
            if summary.daysRemaining > 0, summary.forecastEndValue > summary.totalValue + 1 {
                column(label: "Prognose Ticketende",
                       detail: "\(Format.dayMonth(end)) · \(DashStyle.inDays(summary.daysRemaining))") {
                    DashEuroNumeral(amount: max(0, (summary.forecastEndValue - summary.ticketPrice).rounded()),
                                    sign: "+", color: Theme.positiveText)
                }
            } else {
                column(label: "Rentiert seit", detail: "nach \(DashStyle.trips(tripsUntilPaidOff))") {
                    bigText(summary.paidOffDate.map { Format.dayMonth($0) } ?? "Heute")
                }
            }
        case .onTrack(let date):
            let lead = DashStyle.dayCount(from: date, to: end)
            column(label: "Vor Ablauf am \(Format.dayMonth(end))",
                   detail: lead > 0 ? "rentiert sich rechtzeitig" : "wird knapp",
                   tone: lead > 0 ? .positive : .warning) {
                daysValue(max(0, lead))
            }
        case .behind:
            column(label: "Fehlt bei Ablauf", detail: extraTripsText, tone: .warning) {
                DashEuroNumeral(amount: max(0, (summary.ticketPrice - summary.forecastEndValue).rounded()), sign: "≈")
            }
        case .expired:
            column(label: "Endstand", detail: "von \(SummitFigures.euro(summary.ticketPrice))") {
                DashEuroNumeral(amount: summary.shownTotalEuro)
            }
        }
    }

    private enum Tone { case plain, positive, warning }

    private func column<Value: View>(label: String, detail: String?, tone: Tone = .plain,
                                     @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            value()
            if let detail {
                detailLine(detail, tone: tone)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func detailLine(_ text: String, tone: Tone) -> some View {
        switch tone {
        case .plain:
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .positive:
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.positiveText)
        case .warning:
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.bold))
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.summitText)
        }
    }

    private func bigText(_ text: String) -> some View {
        Text(text)
            .font(DashStyle.bigNumber)
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// "69 Tage" – the figure in `statL`, the unit in `statUnit` at 70 %.
    private func daysValue(_ days: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(Format.number(Double(days)))
                .font(DashStyle.bigNumber)
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText(value: Double(days)))
            Text(days == 1 ? "Tag" : "Tage")
                .font(DashStyle.unitNumber)
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    // MARK: Row B – mini stats

    private var statItems: [DashMiniStat] {
        let co2 = summary.co2SavedKg
        let co2InTonnes = co2 >= 1000
        let co2Value = co2InTonnes ? Format.number(co2 / 1000, decimals: 1) : Format.number(co2)
        return [
            DashMiniStat(id: "trips", value: Format.number(Double(summary.tripCount)), unit: nil, label: "Fahrten",
                         symbol: TransportMode.train.symbolName, color: Theme.accent,
                         accessibilityText: DashStyle.trips(summary.tripCount)),
            DashMiniStat(id: "km", value: Format.number(summary.distanceKm), unit: "km", label: "Kilometer",
                         symbol: "point.topleft.down.to.point.bottomright.curvepath", color: Theme.dusk,
                         accessibilityText: Format.km(summary.distanceKm)),
            DashMiniStat(id: "co2", value: co2Value, unit: co2InTonnes ? "t" : "kg", label: "CO₂ gespart",
                         symbol: "leaf.fill", color: Theme.eco,
                         accessibilityText: "\(Format.kg(co2)) CO₂ gespart"),
        ]
    }

    // MARK: Row C – car comparison

    private var carRow: some View {
        NavigationLink {
            WorkCarView(period: snapshot.ticket)
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.xs) {
                    carLead
                    Spacer(minLength: Theme.Spacing.xs)
                    carVerdict
                }
                VStack(alignment: .leading, spacing: 4) {
                    carLead
                    carVerdict
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(DashPressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Öffnet den ausführlichen Auto-Vergleich")
    }

    private var carLead: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "car.fill")
                .font(.subheadline)
                .foregroundStyle(Theme.summitText)
                .accessibilityHidden(true)
            Text("Mit dem Auto")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
            Text(SummitFigures.euro(car.carCost))
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private var carVerdict: some View {
        if car.isCheaperThanCar, let since = car.breakEvenDate {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                Text("Günstiger seit \(Format.dayMonth(since))")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.positiveText)
            .lineLimit(1)
        } else if !car.isCheaperThanCar {
            Text("noch \(SummitFigures.euro(car.remainingToBreakEven)) bis gleichauf")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }

    // MARK: Derived values

    /// "Mo" for the forecast day.
    private func weekday(_ date: Date) -> String {
        let weekday = Calendar.vienna.component(.weekday, from: date)   // 1 = Sunday
        return DashStyle.weekdays[(weekday + 5) % 7]
    }

    /// Trips up to and including the one that crossed the ticket price.
    private var tripsUntilPaidOff: Int {
        guard let date = summary.paidOffDate else { return summary.tripCount }
        return snapshot.trips.filter { $0.date <= date }.count
    }

    /// "≈ 6 Gratisfahrten" – the profit expressed in average trips.
    private var freeTripsText: String {
        guard summary.averageValuePerTrip > 0 else { return "Ab jetzt fährst du gratis" }
        let n = Int((summary.net / summary.averageValuePerTrip).rounded(.down))
        if n < 1 { return "Ab jetzt fährst du gratis" }
        return n == 1 ? "≈ 1 Gratisfahrt" : "≈ \(Format.number(Double(n))) Gratisfahrten"
    }

    private var tripsToGoText: String? {
        guard let n = snapshot.tripsToBreakEven, n > 0 else { return nil }
        return "≈ \(DashStyle.trips(n))"
    }

    private var extraTripsText: String {
        let gap = max(0, summary.ticketPrice - summary.forecastEndValue)
        let average = summary.averageValuePerTrip > 0 ? summary.averageValuePerTrip : 15
        let n = max(1, Int((gap / average).rounded(.up)))
        return "≈ \(DashStyle.trips(n)) mehr nötig"
    }
}

// MARK: - Mini stats row

struct DashMiniStat: Identifiable {
    let id: String
    let value: String
    let unit: String?
    let label: String
    let symbol: String
    let color: Color
    let accessibilityText: String
}

/// Three figures in equal columns (spec §8.3 Row B); a vertical "label …… value" list at accessibility sizes.
struct DashMiniStatsRow: View {
    var items: [DashMiniStat]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(items) { item in
                    DashMiniStatListRow(item: item)
                }
            }
        } else {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                ForEach(items) { item in
                    DashMiniStatView(item: item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct DashMiniStatView: View {
    let item: DashMiniStat

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(item.value)
                    .font(DashStyle.statNumber)
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                if let unit = item.unit {
                    Text(unit)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .lineLimit(1)
            HStack(spacing: 4) {
                Image(systemName: item.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item.color)
                Text(item.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityText)
    }
}

private struct DashMiniStatListRow: View {
    let item: DashMiniStat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Image(systemName: item.symbol)
                .foregroundStyle(item.color)
            Text(item.label)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Spacing.xs)
            Text(item.unit.map { item.value + " " + $0 } ?? item.value)
                .font(DashStyle.statNumber)
                .foregroundStyle(Theme.textPrimary)
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityText)
    }
}
