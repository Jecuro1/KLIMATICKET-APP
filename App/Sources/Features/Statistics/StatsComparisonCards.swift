import SwiftUI
import KlimaCore

// MARK: - Welches Ticket lohnt sich?

/// "Was wäre wenn": total cost of each ticket option for the logged trips (ticket price + regular fares
/// of trips it would not cover). Current ticket marked, cheapest highlighted.
struct StatsTicketComparisonCard: View {
    let snapshot: AnalyticsSnapshot
    let products: [TicketProduct]
    let variant: TicketVariant
    let grow: Double

    var body: some View {
        let result = StatsCalc.ticketComparison(snapshot, products: products, variant: variant)
        GlassCard(padding: Theme.Spacing.m + 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                StatsCardHeader(kicker: "Welches Ticket lohnt sich?", title: verdict(result))
                VStack(spacing: Theme.Spacing.m) {
                    ForEach(result.options) { option in
                        row(option, result: result)
                    }
                }
                Text(caption(result))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func verdict(_ result: StatsTicketComparison) -> String {
        guard let cheapest = result.cheapest else { return "Noch keine Daten" }
        if cheapest.isCurrent { return "Dein Ticket ist die günstigste Wahl" }
        let difference = (result.current?.totalCost ?? cheapest.totalCost) - cheapest.totalCost
        if cheapest.id == "single" {
            return result.current != nil
                ? "Bisher wären Einzeltickets um \(Format.euro(difference, decimals: 0)) günstiger"
                : "Bisher wären Einzeltickets am günstigsten"
        }
        return result.current != nil
            ? "\(cheapest.name) wäre um \(Format.euro(difference, decimals: 0)) günstiger"
            : "Am günstigsten wäre \(cheapest.name)"
    }

    private func caption(_ result: StatsTicketComparison) -> String {
        let summary = snapshot.summary
        var text = "Gesamtkosten = Ticketpreis + Normalpreis der Fahrten, die ein Ticket nicht abdeckt. "
        if result.isAnnualized {
            text += "Weil dein Ticketjahr gerade erst begonnen hat, sind deine bisherigen Fahrten aufs ganze Jahr hochgerechnet (× \(Format.number(result.factor, decimals: 1)))."
        } else {
            text += "Grundlage sind deine bisherigen Fahrten (Tag \(summary.daysElapsed) von \(summary.daysTotal))."
        }
        if result.cheapest?.id == "single", summary.daysRemaining > 0 {
            text += " Mit jeder weiteren Fahrt holt dein Ticket auf."
        }
        return text
    }

    private func row(_ option: TicketOption, result: StatsTicketComparison) -> some View {
        let isCheapest = option.id == result.cheapest?.id
        let color = isCheapest ? Theme.positive : (option.isCurrent ? Theme.glacier : Theme.textTertiary)
        let detailText = detail(option, annualized: result.isAnnualized)
        var label = option.name
        if option.isCurrent { label += ", dein Ticket" }
        if isCheapest { label += ", am günstigsten" }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if isCheapest || option.isCurrent {
                        HStack(spacing: 6) {
                            if option.isCurrent {
                                StatsBadge(text: "Dein Ticket", symbol: "ticket.fill",
                                           foreground: Theme.accentText, fill: Theme.glacier.opacity(0.15))
                            }
                            if isCheapest {
                                StatsBadge(text: "Am günstigsten", symbol: "checkmark",
                                           foreground: Theme.positiveText, fill: Theme.positive.opacity(0.16))
                            }
                        }
                    }
                }
                Spacer(minLength: Theme.Spacing.xs)
                Text(Format.euro(option.totalCost, decimals: 0))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(isCheapest ? Theme.positiveText : Theme.textPrimary)
                    .lineLimit(1)
            }
            costBar(option, maxCost: result.maxCost, color: color)
            Text(detailText)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Format.euro(option.totalCost, decimals: 0)). \(detailText)")
    }

    private func costBar(_ option: TicketOption, maxCost: Double, color: Color) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let ticketWidth = width * CGFloat(option.ticketPrice / maxCost * grow)
            let extraWidth = width * CGFloat(option.uncoveredCost / maxCost * grow)
            HStack(spacing: 2) {
                if option.ticketPrice > 0 {
                    Capsule().fill(color).frame(width: max(ticketWidth, 6))
                }
                if option.uncoveredCost > 0 {
                    Capsule().fill(color.opacity(0.38)).frame(width: max(extraWidth, 6))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    /// Trip counts are the real ones, the € amounts are scaled by the annualisation factor – say so.
    private func detail(_ option: TicketOption, annualized: Bool) -> String {
        let suffix = annualized ? " (aufs Jahr hochgerechnet)" : ""
        if option.id == "single" {
            return "Normalpreis aller \(StatsNames.trips(snapshot.summary.tripCount))\(suffix)"
        }
        let uncovered = max(0, snapshot.trips.count - option.coveredTrips)
        if uncovered == 0 { return "\(Format.euro(option.ticketPrice, decimals: 0)) Ticket · deckt alle Fahrten ab" }
        return "\(Format.euro(option.ticketPrice, decimals: 0)) Ticket + \(Format.euro(option.uncoveredCost, decimals: 0)) für \(StatsNames.trips(uncovered)) außerhalb\(suffix)"
    }
}

// MARK: - Auto-Vergleich & CO₂

struct StatsCarCO2Section: View {
    let snapshot: AnalyticsSnapshot
    let kilometergeld: Double
    let grow: Double

    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 44

    private var summary: SavingsSummary { snapshot.summary }

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            carCard
            co2Card
        }
    }

    // MARK: Car

    private var carCard: some View {
        let car = summary.carCostEquivalent
        let price = summary.ticketPrice
        let maxValue = max(car, price, 1)
        return GlassCard(padding: Theme.Spacing.m + 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                StatsCardHeader(kicker: "Auto-Vergleich", title: nil) {
                    StatsInfoButton(title: "Auto-Vergleich", text: Copy.carExplanation)
                }
                carHeadline(car: car, price: price)
                VStack(spacing: Theme.Spacing.s) {
                    compareRow(label: "Mit dem Auto", symbol: "car.fill", value: car, maxValue: maxValue, color: Theme.remaining)
                    compareRow(label: "Dein KlimaTicket", symbol: "ticket.fill", value: price, maxValue: maxValue, color: Theme.glacier)
                }
                Text("\(Format.km(summary.distanceKm)) × \(Format.euroPrecise(kilometergeld)) amtliches Kilometergeld")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func carHeadline(car: Double, price: Double) -> some View {
        if car >= price {
            Text("\(Text(Format.euro(car - price, decimals: 0)).foregroundStyle(Theme.positiveText)) günstiger als mit dem Auto")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mit dem Auto bisher \(Format.euro(car, decimals: 0))")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Noch \(Format.euro(price - car, decimals: 0)) Autokosten, dann fährst du mit dem Ticket günstiger.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func compareRow(label: String, symbol: String, value: Double, maxValue: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 18)
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: Theme.Spacing.xs)
                Text(Format.euro(value, decimals: 0))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
            ProgressRail(progress: value / maxValue * grow, height: 8, fill: AnyShapeStyle(color))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Format.euro(value, decimals: 0))
    }

    // MARK: CO₂

    private var co2Card: some View {
        let kg = summary.co2SavedKg
        let parts = StatsCalc.co2Parts(kg)
        return GlassCard(padding: Theme.Spacing.m + 2, tint: Theme.eco) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                StatsCardHeader(kicker: "CO₂-Bilanz", title: nil) {
                    StatsInfoButton(title: "CO₂-Ersparnis", text: Copy.co2Explanation)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(parts.value)
                        .font(.system(size: numeralSize, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.positive)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(parts.unit)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.positiveText)
                    Text("CO₂ gespart")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.leading, 2)
                }
                .accessibilityElement(children: .combine)
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    equivalentRow(symbol: "airplane",
                                  title: "ca. \(StatsCalc.friendlyCount(kg / StatsCalc.kgPerFlight)) Flüge Wien–Paris",
                                  detail: "à rund 0,18 t CO₂ pro Person und Strecke")
                    equivalentRow(symbol: "tree.fill",
                                  title: "ca. \(StatsCalc.friendlyCount(kg / StatsCalc.kgPerTreeYear)) Bäume ein Jahr lang",
                                  detail: "ein Baum bindet rund 22 kg CO₂ pro Jahr")
                }
                Text("gegenüber denselben Kilometern allein im Auto")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func equivalentRow(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.positive)
                .frame(width: 34, height: 34)
                .background(Theme.positive.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Effektive Kosten

struct StatsEffectiveCostsSection: View {
    let snapshot: AnalyticsSnapshot

    @Environment(\.dynamicTypeSize) private var typeSize

    private var summary: SavingsSummary { snapshot.summary }

    private var columns: [GridItem] {
        let count = typeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.s, alignment: .top), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(title: "Effektive Kosten")
                .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.s) {
                StatTile(value: perTrip, label: "pro Fahrt bisher", symbol: "train.side.front.car", color: Theme.accent)
                StatTile(value: perKm, label: "pro Kilometer", symbol: "point.topleft.down.to.point.bottomright.curvepath",
                         color: Theme.dusk)
                StatTile(value: Format.euroPrecise(summary.costPerDay), label: "Ticketkosten pro Tag", symbol: "calendar",
                         color: Theme.summit)
                StatTile(value: Format.euroPrecise(summary.valuePerDay), label: "Wert pro Tag bisher",
                         symbol: "chart.line.uptrend.xyaxis", color: Theme.positive)
            }
            verdict
                .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
                .padding(.top, Theme.Spacing.xxs)
        }
    }

    private var perTrip: String {
        guard summary.tripCount > 0 else { return "–" }
        return Format.euroPrecise(summary.ticketPrice / Double(summary.tripCount))
    }

    private var perKm: String {
        guard let value = summary.effectivePricePerKm else { return "–" }
        return Format.euroPrecise(value)
    }

    private var verdict: some View {
        let difference = summary.valuePerDay - summary.costPerDay
        let ahead = difference >= 0
        return Label {
            Text(ahead
                 ? "Jeder Tag bringt dir im Schnitt \(Format.euroPrecise(difference)) mehr, als das Ticket kostet."
                 : "Pro Tag fehlen im Schnitt noch \(Format.euroPrecise(-difference)) bis zum Break-even-Tempo.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: ahead ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                .foregroundStyle(ahead ? Theme.positive : Theme.summit)
        }
        .font(.subheadline)
        .foregroundStyle(Theme.textSecondary)
    }
}
