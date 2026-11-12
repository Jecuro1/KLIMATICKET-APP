import SwiftUI
import KlimaCore

// MARK: - Result (hero sentence, delta, chart)

/// The answer: one sentence ("Ab 7 Fahrten pro Monat lohnt sich das KlimaTicket Ö"), what it means per year, and the cost chart.
struct WhatIfResultCard: View {
    let result: WhatIfResult
    let usesHistory: Bool

    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 44
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GlassCard(padding: Theme.Spacing.m + 2, tint: tint) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .center, spacing: Theme.Spacing.xs) {
                    Kicker(text: "Ergebnis · pro Jahr")
                    Spacer(minLength: Theme.Spacing.xs)
                    StatsInfoButton(title: "So rechnen wir", text: WhatIfText.explanation)
                }
                hero
                deltaView
                Text(WhatIfText.volumeLine(result, usesHistory: usesHistory))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if result.state == .ready {
                    WhatIfChart(result: result)
                        .frame(height: typeSize.isAccessibilitySize ? 250 : 200)
                        .padding(.top, Theme.Spacing.xs)
                    legend
                    Text(WhatIfText.chartSummary(result))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var tint: Color? {
        guard result.state == .ready, result.bestTicket != nil else { return nil }
        return result.ticketIsCheaper ? Theme.positive : nil
    }

    // MARK: Hero

    private var hero: some View {
        heroText
            .font(.system(.title2, design: .rounded).weight(.bold))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .numericValue(Double(result.breakEvenTripsPerMonth ?? 0))
            .accessibilityLabel(WhatIfText.headline(result, usesHistory: usesHistory))
            .accessibilityAddTraits(.isHeader)
    }

    /// The break-even number is set in the accent colour; every other state is one plain sentence.
    private var heroText: Text {
        guard result.state == .ready, let best = result.bestTicket, !result.isTie, let breakEven = result.breakEvenTripsPerMonth else {
            return Text(WhatIfText.headline(result, usesHistory: usesHistory))
        }
        let number = Text(WhatIfText.trips(breakEven)).foregroundStyle(Theme.accentText)
        let name = WhatIfText.withArticle(best.name)
        if result.ticketIsCheaper {
            return Text("Ab \(number) pro Monat lohnt sich \(name)")
        }
        return Text("Einzeltickets sind günstiger – \(name) lohnt sich ab \(number) pro Monat")
    }

    // MARK: Delta

    @ViewBuilder
    private var deltaView: some View {
        if let delta = WhatIfText.delta(result) {
            VStack(alignment: .leading, spacing: 2) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) { deltaParts(delta) }
                    VStack(alignment: .leading, spacing: 2) { deltaParts(delta) }
                }
                Text(delta.caption)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(delta.sentence)
        }
    }

    @ViewBuilder
    private func deltaParts(_ delta: WhatIfText.Delta) -> some View {
        if !delta.prefix.isEmpty {
            Text(delta.prefix)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        if !delta.amount.isEmpty {
            Text(delta.amount)
                .font(.system(size: numeralSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(delta.isSaving ? Theme.positive : Theme.summit)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .numericValue(abs(result.yearlyDelta).rounded())
        }
        Text(delta.suffix)
            .font(delta.amount.isEmpty ? .title3.weight(.semibold) : .title3.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
    }

    // MARK: Legend

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.s) { legendItems }
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) { legendItems }
        }
    }

    @ViewBuilder
    private var legendItems: some View {
        StatsLegendItem(label: "Einzeltickets", style: AnyShapeStyle(Theme.dawn))
        if let best = result.bestTicket {
            StatsLegendItem(label: best.name, style: AnyShapeStyle(Theme.glacier))
            if result.crossing != nil {
                HStack(spacing: 5) {
                    Image(systemName: "flag.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.positive)
                    Text("Break-even")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Ranking

/// Single tickets and the best matching KlimaTickets, cheapest first, with a bar per option (ticket price solid, fares of the
/// trips it does not cover faded).
struct WhatIfRankingCard: View {
    let result: WhatIfResult

    var body: some View {
        let shown = result.displayOptions(limit: 4)
        let maxCost = max(shown.map(\.yearlyCost).max() ?? 1, 1)
        let cheapestID = result.options.first?.id
        GlassCard(padding: Theme.Spacing.m + 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                StatsCardHeader(kicker: "Rangliste · pro Jahr", title: nil)
                ForEach(shown) { option in
                    WhatIfOptionRow(option: option, result: result, maxCost: maxCost, isCheapest: option.id == cheapestID)
                }
            }
        }
        // Only a change of the order moves rows; the numbers and bars follow the slider without any animation.
        .motionAnimation(Motion.smooth, value: shown.map(\.id))
    }
}

struct WhatIfOptionRow: View {
    let option: WhatIfOption
    let result: WhatIfResult
    let maxCost: Double
    let isCheapest: Bool

    var body: some View {
        let color = isCheapest ? Theme.positive : (option.isCurrent ? Theme.glacier : Theme.textTertiary)
        let detail = WhatIfText.detail(option, result: result)
        var label = option.name
        if option.isCurrent { label += ", dein Ticket" }
        if isCheapest { label += ", am günstigsten" }
        let cost = Format.euro(option.yearlyCost.rounded(), decimals: 0)
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
                                StatsBadge(text: "Dein Ticket", symbol: "ticket.fill", foreground: Theme.accentText,
                                           fill: Theme.glacier.opacity(0.15))
                            }
                            if isCheapest {
                                StatsBadge(text: "Am günstigsten", symbol: "checkmark", foreground: Theme.positiveText,
                                           fill: Theme.positive.opacity(0.16))
                            }
                        }
                    }
                }
                Spacer(minLength: Theme.Spacing.xs)
                Text(cost)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(isCheapest ? Theme.positiveText : Theme.textPrimary)
                    .lineLimit(1)
                    .numericValue(option.yearlyCost.rounded())
            }
            bar(color: color)
            Text(detail)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !option.isSingle, let breakEven = option.breakEvenTripsPerMonth {
                Text("Lohnt sich ab \(WhatIfText.trips(breakEven)) pro Monat")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(cost) pro Jahr. \(detail)" + (option.breakEvenTripsPerMonth.flatMap { be in
            option.isSingle ? nil : ". Lohnt sich ab \(WhatIfText.trips(be)) pro Monat"
        } ?? ""))
    }

    private func bar(color: Color) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let ticket = width * CGFloat(option.ticketPrice / maxCost)
            let extra = width * CGFloat(option.uncoveredYearly / maxCost)
            HStack(spacing: 2) {
                if option.ticketPrice > 0 {
                    Capsule().fill(color).frame(width: max(ticket, 6))
                }
                if option.uncoveredYearly > 0 {
                    Capsule().fill(color.opacity(0.38)).frame(width: max(extra, 6))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

// MARK: - Empty states

/// „Eigene Annahmen“ without a route: an invitation with the three presets.
struct WhatIfInviteCard: View {
    var onPreset: (WhatIfPreset) -> Void
    var onCustom: () -> Void

    var body: some View {
        GlassCard(padding: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 44, height: 44)
                        .background(Theme.accent.opacity(0.14), in: .circle)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wie oft fährst du wohin?")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text("Dein Ticket musst du dafür noch nicht haben.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(WhatIfPreset.all) { preset in
                        WhatIfPresetRow(preset: preset) { onPreset(preset) }
                    }
                }
                Button(action: onCustom) {
                    Label("Eigene Strecke wählen", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glass)
            }
        }
    }
}

struct WhatIfPresetRow: View {
    let preset: WhatIfPreset
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: preset.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 36, height: 36)
                    .background(Theme.accent.opacity(0.14), in: .rect(cornerRadius: Theme.Radius.modeTile, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(preset.subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Spacing.xs)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, Theme.Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(Theme.surfaceSecondary, in: .rect(cornerRadius: Theme.Radius.tile - 4, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Füllt die Rechnung mit diesem Beispiel")
    }
}

/// „Meine Fahrten“ without a single trip in the last 12 months.
struct WhatIfNoHistoryCard: View {
    var onSwitch: () -> Void

    var body: some View {
        GlassCard(padding: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text("Noch keine Fahrten")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("In den letzten 12 Monaten hast du keine Fahrt erfasst. Rechne mit eigenen Annahmen – das geht auch ohne Ticket.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onSwitch) {
                    Label("Eigene Annahmen", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glass)
            }
        }
    }
}

// MARK: - Footnote

/// The honest line: a calculation aid, what the prices are, the tariff date.
struct WhatIfFootnote: View {
    let result: WhatIfResult

    var body: some View {
        Label {
            Text(WhatIfText.footnote(result))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "checkmark.shield")
        }
        .font(.footnote)
        .foregroundStyle(Theme.textSecondary)
        .accessibilityElement(children: .combine)
    }
}
