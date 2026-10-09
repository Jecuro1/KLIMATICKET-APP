import SwiftUI
import KlimaCore

/// "Bilanz-Karte" (DESIGN.md §5.1 · 4): one card that answers the question – what is left to the summit and when
/// you will get there – plus the four key figures (Fahrten · km · CO₂ · Auto), the pace pill and the car comparison.
struct DashBalanceCard: View {
    var snapshot: AnalyticsSnapshot
    /// Amtliches Kilometergeld (EUR/km) – same basis as `summary.carCostEquivalent`.
    var kilometergeld: Double
    var now: Date = Date()

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var summary: SavingsSummary { snapshot.summary }
    private var isExpired: Bool { now > snapshot.ticket.end }

    var body: some View {
        GlassCard(padding: Theme.Spacing.l, tint: summary.isPaidOff ? Theme.positive : nil) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                verdict
                hairline
                DashMiniStatsRow(items: statItems)
                footer
            }
        }
    }

    // MARK: Verdict

    @ViewBuilder
    private var verdict: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                leadingColumn
                hairline
                trailingColumn
            }
        } else {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                leadingColumn
                    .fixedSize(horizontal: true, vertical: false)
                Rectangle()
                    .fill(Theme.separator)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                trailingColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var leadingColumn: some View {
        if summary.isPaidOff {
            column(kicker: "Rentiert seit") {
                bigText(summary.paidOffDate.map { Format.dayMonth($0) } ?? "Heute")
            } detail: {
                detailText("nach \(DashStyle.trips(tripsUntilPaidOff))")
            }
        } else {
            // An expired ticket can't be paid off any more – no "≈ n Fahrten" still to go.
            column(kicker: isExpired ? "Fehlte zum Gipfel" : "Bis zum Gipfel") {
                DashEuroNumeral(amount: summary.remainingToBreakEven)
            } detail: {
                if !isExpired, let n = snapshot.tripsToBreakEven, n > 0 {
                    detailText("≈ \(DashStyle.trips(n))")
                }
            }
        }
    }

    @ViewBuilder
    private var trailingColumn: some View {
        if summary.isPaidOff {
            column(kicker: "Gewinn") {
                DashEuroNumeral(amount: summary.net, sign: "+", color: Theme.positive, symbolColor: Theme.positive)
            } detail: {
                if summary.daysRemaining > 0, summary.forecastEndValue > summary.totalValue + 1 {
                    detailText("Prognose bis Ablauf \(DashStyle.signedEuro(summary.forecastEndValue - summary.ticketPrice))")
                } else {
                    detailText("Jede Fahrt ist jetzt Gewinn")
                }
            }
        } else if let date = summary.forecastBreakEvenDate, summary.forecastReachesBreakEven {
            column(kicker: "Break-even") {
                bigText(Format.dayMonth(date))
            } detail: {
                detailText("Prognose · \(DashStyle.inDays(DashStyle.dayCount(from: now, to: date)))")
                let lead = DashStyle.dayCount(from: date, to: snapshot.ticket.end)
                if lead > 0 {
                    Label("\(Format.days(lead)) vor Ablauf", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.positiveText)
                }
            }
        } else if summary.daysRemaining > 0 {
            column(kicker: "Prognose bis Ablauf") {
                DashEuroNumeral(amount: summary.forecastEndValue)
            } detail: {
                detailText("bei deinem Tempo")
                Label(extraTripsText, systemImage: "exclamationmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.summitText)
            }
        } else {
            column(kicker: "Endstand") {
                DashEuroNumeral(amount: summary.totalValue)
            } detail: {
                detailText("Ticket abgelaufen")
            }
        }
    }

    private func column<Value: View, Detail: View>(kicker: String,
                                                   @ViewBuilder value: () -> Value,
                                                   @ViewBuilder detail: () -> Detail) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Kicker(text: kicker)
            value()
            detail()
        }
        .accessibilityElement(children: .combine)
    }

    private func bigText(_ text: String) -> some View {
        Text(text)
            .font(DashStyle.bigNumber)
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private func detailText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    // MARK: Footer (pace + car)

    @ViewBuilder
    private var footer: some View {
        let pills = footerPills
        if !pills.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(pills) { pill($0) }
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(pills) { pill($0) }
                }
            }
        }
    }

    private func pill(_ model: PillModel) -> some View {
        DashPill(symbol: model.symbol, text: model.text, foreground: model.foreground, tint: model.tint)
    }

    private struct PillModel: Identifiable {
        let id: String
        let symbol: String
        let text: String
        let foreground: Color
        let tint: Color
    }

    private var footerPills: [PillModel] {
        var pills: [PillModel] = []
        if let delta = paceDelta {
            if delta >= 0, summary.forecastReachesBreakEven {
                pills.append(PillModel(id: "pace", symbol: "hare.fill",
                                       text: "Schneller als nötig · \(DashStyle.signedEuro(delta)) vor Plan",
                                       foreground: Theme.positiveText, tint: Theme.positive))
            } else if delta >= 0 {
                // Still ahead of the linear plan, but the recent pace no longer reaches the summit in time –
                // "Schneller als nötig" would contradict the card's warning above.
                pills.append(PillModel(id: "pace", symbol: "arrow.down.right",
                                       text: "Noch vor Plan · \(DashStyle.signedEuro(delta)) · Tempo sinkt",
                                       foreground: Theme.summitText, tint: Theme.summit))
            } else if summary.forecastReachesBreakEven {
                // Behind the linear plan, but the recent pace already gets you to the summit in time.
                pills.append(PillModel(id: "pace", symbol: "arrow.up.right",
                                       text: "Du holst auf · \(DashStyle.signedEuro(delta)) zum Plan",
                                       foreground: Theme.accentText, tint: Theme.accent))
            } else {
                pills.append(PillModel(id: "pace", symbol: "tortoise.fill",
                                       text: "Etwas hinter Plan · \(DashStyle.signedEuro(delta))",
                                       foreground: Theme.summitText, tint: Theme.summit))
            }
        }
        if let since = carCheaperSince {
            pills.append(PillModel(id: "car", symbol: "car.fill",
                                   text: "Günstiger als Auto seit \(Format.dayMonth(since))",
                                   foreground: Theme.positiveText, tint: Theme.positive))
        }
        return pills
    }

    // MARK: Mini stats

    private var statItems: [DashMiniStat] {
        let co2 = summary.co2SavedKg
        let co2InTonnes = co2 >= 1000
        let co2Value = co2InTonnes ? Format.number(co2 / 1000, decimals: 1) : Format.number(co2)
        let co2Unit = co2InTonnes ? "t" : "kg"
        let car = Format.euro(summary.carCostEquivalent, decimals: 0)
        return [
            DashMiniStat(id: "trips", value: Format.number(Double(summary.tripCount)), unit: nil, label: "Fahrten",
                         symbol: TransportMode.train.symbolName, color: Theme.accent,
                         accessibilityText: DashStyle.trips(summary.tripCount)),
            DashMiniStat(id: "km", value: Format.number(summary.distanceKm), unit: "km", label: "Kilometer",
                         symbol: "point.topleft.down.to.point.bottomright.curvepath", color: Theme.dusk,
                         accessibilityText: Format.km(summary.distanceKm)),
            DashMiniStat(id: "co2", value: co2Value, unit: co2Unit, label: "CO₂ gespart",
                         symbol: "leaf.fill", color: Theme.eco,
                         accessibilityText: "\(Format.kg(co2)) CO₂ gespart"),
            DashMiniStat(id: "car", value: car, unit: nil, label: "per Auto",
                         symbol: "car.fill", color: Theme.dawn,
                         accessibilityText: "Mit dem Auto hätten die Strecken \(car) gekostet"),
        ]
    }

    // MARK: Derived values

    /// Trips up to and including the one that crossed the ticket price.
    private var tripsUntilPaidOff: Int {
        guard let date = summary.paidOffDate else { return summary.tripCount }
        return snapshot.trips.filter { $0.date <= date }.count
    }

    /// Value ahead (+) or behind (–) a linear plan (ticket price spread evenly over the validity).
    private var paceDelta: Double? {
        guard !summary.isPaidOff, summary.daysRemaining > 0, summary.tripCount > 0, summary.daysTotal > 0 else { return nil }
        let expected = summary.ticketPrice * Double(summary.daysElapsed) / Double(summary.daysTotal)
        let delta = summary.totalValue - expected
        return abs(delta) < 1 ? nil : delta
    }

    /// Day from which the same km by car (Kilometergeld) would have cost more than the ticket.
    private var carCheaperSince: Date? {
        guard kilometergeld > 0, summary.carCostEquivalent >= summary.ticketPrice else { return nil }
        var running = 0.0
        for trip in snapshot.trips.sorted(by: { $0.date < $1.date }) {
            running += trip.totalDistanceKm * kilometergeld
            if running >= summary.ticketPrice { return trip.date }
        }
        return nil
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

/// Four figures in one row (uneven widths like the mockup; figures scale down slightly on narrow phones);
/// a 2×2 grid from xxLarge Dynamic Type on (DESIGN.md §5.1 · 4).
struct DashMiniStatsRow: View {
    var items: [DashMiniStat]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize >= .xxLarge {
            grid
        } else {
            row
        }
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(items) { item in
                if item.id != items.first?.id {
                    Spacer(minLength: Theme.Spacing.xs)
                }
                DashMiniStatView(item: item)
            }
        }
    }

    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.m, verticalSpacing: Theme.Spacing.s) {
            ForEach(rows.indices, id: \.self) { index in
                GridRow {
                    ForEach(rows[index]) { item in
                        DashMiniStatView(item: item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var rows: [[DashMiniStat]] {
        stride(from: 0, to: items.count, by: 2).map { start in
            Array(items[start..<min(start + 2, items.count)])
        }
    }
}

private struct DashMiniStatView: View {
    let item: DashMiniStat

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(item.value)
                    .font(DashStyle.statNumber)
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                if let unit = item.unit {
                    Text(unit)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            HStack(spacing: 4) {
                Image(systemName: item.symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(item.color)
                Text(item.label)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityText)
    }
}
