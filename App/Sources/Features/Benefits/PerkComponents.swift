import SwiftUI
import Charts
import KlimaCore

// Building blocks of the Vorteilswelt screens: icon tiles, the hero numeral, the monthly chart stacked by
// category with its legend, rows, quick-add chips and small pills.

// MARK: - Icon tile

/// Coloured rounded-square tile with the partner's SF Symbol (white glyph). The colours resolve to their
/// saturated light variants so the glyph keeps its contrast in dark mode.
struct PerkIconTile: View {
    var symbol: String
    var category: PerkCategory
    var size: CGFloat = 40

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let side = size * min(max(scale, 1), 1.4)
        let tint = PerkStyle.tint(category)
        Image(systemName: symbol)
            .font(.system(size: side * 0.44, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(
                LinearGradient(colors: [tint, tint.mix(with: .black, by: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: side * 0.31, style: .continuous))
            .environment(\.colorScheme, .light)
            .accessibilityHidden(true)
    }
}

extension PerkIconTile {
    init(partner: PerkPartner?, size: CGFloat = 40) {
        self.init(symbol: partner?.symbolName ?? PerkCategory.custom.symbolName, category: partner?.category ?? .custom, size: size)
    }
}

// MARK: - Numerals

/// Big light figure with a smaller prefix ("+ € 86"), like the temperature in Apple Weather.
struct PerkEuroNumeral: View {
    var amount: Double
    var prefix: String = "+ €"
    var decimals: Int = 0
    var numberFont: Font = PerkStyle.heroNumber
    var prefixFont: Font = PerkStyle.heroSymbol
    var accessibilityPrefix: String = "plus"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(prefix)
                .font(prefixFont)
                .foregroundStyle(Theme.textSecondary)
            Text(Format.number(amount, decimals: decimals))
                .font(numberFont)
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText(value: amount))
                .animation(reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.15), value: amount)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(accessibilityPrefix) \(Format.euro(amount, decimals: decimals))")
    }
}

// MARK: - Monthly chart (stacked by category)

/// Validity months of the period with the savings per month, stacked by category (Swift Charts).
struct PerkMonthlyChart: View {
    struct Entry: Identifiable {
        var monthIndex: Int
        var category: PerkCategory
        var total: Double
        var id: String { "\(monthIndex)-\(category.rawValue)" }
    }

    var benefits: [BenefitEntity]
    var period: PerkPeriod
    var height: CGFloat = 112

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let months = PerkPassengerRights.validityMonths(start: period.start, end: period.end)
        let entries = makeEntries(months: months)
        let todayIndex = PerkPassengerRights.monthIndex(of: Date(), in: months)
        let maxTotal = monthTotals(entries).max() ?? 0
        Chart {
            ForEach(entries) { entry in
                BarMark(x: .value("Monat", String(entry.monthIndex)),
                        y: .value("Ersparnis", entry.total),
                        width: .ratio(0.56))
                    .foregroundStyle(PerkStyle.tint(entry.category))
                    .cornerRadius(3)
            }
        }
        .chartXScale(domain: months.indices.map { String($0) })
        .chartYScale(domain: 0...max(maxTotal * 1.15, 5))
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    axisLabel(value.as(String.self), months: months, todayIndex: todayIndex)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Theme.separator)
                AxisValueLabel {
                    if let euros = value.as(Double.self) {
                        Text(Format.number(euros))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: height)
        .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: entries.map(\.total))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zusatz-Ersparnis pro Monat")
        .accessibilityValue(accessibilitySummary(entries: entries, months: months))
    }

    private func makeEntries(months: [DateInterval]) -> [Entry] {
        var totals: [String: Entry] = [:]
        let catalog = PerkCatalogStore.shared
        for benefit in benefits where benefit.deletedAt == nil {
            guard let index = PerkPassengerRights.monthIndex(of: benefit.date, in: months) else { continue }
            let category = catalog.category(forPartnerID: benefit.partnerID)
            let key = "\(index)-\(category.rawValue)"
            totals[key, default: Entry(monthIndex: index, category: category, total: 0)].total += max(0, benefit.savedEUR)
        }
        let order = PerkCategory.allCases
        return totals.values.sorted { lhs, rhs in
            if lhs.monthIndex != rhs.monthIndex { return lhs.monthIndex < rhs.monthIndex }
            return (order.firstIndex(of: lhs.category) ?? 0) < (order.firstIndex(of: rhs.category) ?? 0)
        }
    }

    private func monthTotals(_ entries: [Entry]) -> [Double] {
        Dictionary(grouping: entries, by: \.monthIndex).values.map { group in group.reduce(0.0) { $0 + $1.total } }
    }

    private func axisLabel(_ id: String?, months: [DateInterval], todayIndex: Int?) -> Text {
        let index = Int(id ?? "") ?? -1
        let isToday = index == todayIndex
        return Text(monthLetter(index, months: months))
            .font(.caption2.weight(isToday ? .bold : .regular))
            .foregroundStyle(isToday ? Theme.textPrimary : Theme.textSecondary)
    }

    /// "J", "F", "M" … of the validity month's start.
    private func monthLetter(_ index: Int, months: [DateInterval]) -> String {
        guard months.indices.contains(index) else { return "" }
        let name = months[index].start.formatted(.dateTime.month(.narrow).locale(Format.locale))
        return name.uppercased(with: Format.locale)
    }

    private func accessibilitySummary(entries: [Entry], months: [DateInterval]) -> String {
        let byMonth = Dictionary(grouping: entries, by: \.monthIndex).mapValues { group in group.reduce(0.0) { $0 + $1.total } }
        guard let best = byMonth.max(by: { $0.value < $1.value }), months.indices.contains(best.key) else {
            return "Noch keine Vorteile in diesem Zeitraum"
        }
        let monthName = months[best.key].start.formatted(.dateTime.month(.wide).locale(Format.locale))
        let active = byMonth.filter { $0.value > 0 }.count
        return "In \(active) von \(months.count) Monaten genutzt. Stärkster Monat: \(monthName) mit \(Format.euroPrecise(best.value))."
    }
}

/// Category legend: dot + name + amount, wraps into two columns.
struct PerkCategoryLegend: View {
    var totals: [PerkSummary.CategoryTotal]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Theme.Spacing.s, alignment: .leading)],
                  alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(totals) { item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(PerkStyle.tint(item.category))
                        .frame(width: 8, height: 8)
                    Text(item.category.displayName)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    // Whole euros like the hero total; cents only for amounts below one euro.
                    Text(Format.euro(item.total, decimals: item.total >= 1 ? 0 : 2))
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                .font(.footnote)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.category.displayName): \(Format.euroPrecise(item.total)), \(PerkFormat.count(item.count))")
            }
        }
    }
}

// MARK: - Rows

/// One logged benefit: partner tile · title · day + note · "+ € 7,00".
struct PerkBenefitRow: View {
    let benefit: BenefitEntity
    let partner: PerkPartner?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            PerkIconTile(partner: partner, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(benefit.title.isEmpty ? (partner?.name ?? "Vorteil") : benefit.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
            }
            .alignmentGuide(.listRowSeparatorLeading) { dimensions in dimensions[.leading] }
            Spacer(minLength: Theme.Spacing.xs)
            Text(PerkFormat.plusEuro(benefit.savedEUR))
                .font(Theme.Typography.numberSmall)
                .foregroundStyle(Theme.positiveText)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(benefit.title.isEmpty ? (partner?.name ?? "Vorteil") : benefit.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Bearbeiten")
    }

    private var subtitle: String {
        var parts = [PerkFormat.day(benefit.date)]
        let note = benefit.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            parts.append(note)
        } else if let partner {
            parts.append(partner.category.displayName)
        } else {
            parts.append("Eigener Vorteil")
        }
        return parts.joined(separator: " · ")
    }

    private var accessibilityValue: String {
        var parts = ["\(Format.euroPrecise(benefit.savedEUR)) gespart", Format.date(benefit.date, .long)]
        if !benefit.note.isEmpty { parts.append("Notiz: \(benefit.note)") }
        return parts.joined(separator: ", ")
    }
}

/// Month header in the benefit list ("Oktober 2026 · + € 21").
struct PerkMonthHeader: View {
    var group: PerkMonthGroup

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(PerkFormat.month(group.month))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: Theme.Spacing.xs)
            Text(PerkFormat.plusEuro(group.total))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Quick add

/// Glass capsule chip "[tile] CAT · ≈ € 7 [+]" – opens the editor prefilled with the partner.
struct PerkQuickAddChip: View {
    var partner: PerkPartner
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                PerkIconTile(partner: partner, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(partner.shortName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(PerkFormat.typical(partner.typicalSavingEUR))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
                .lineLimit(1)
                Image(systemName: "plus")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 26, height: 26)
                    .background(Theme.accent.opacity(0.14), in: .circle)
            }
            .padding(.leading, 6)
            .padding(.trailing, Theme.Spacing.xs)
            .padding(.vertical, 6)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel("\(partner.name) erfassen")
        .accessibilityValue("typisch \(Format.euroPrecise(partner.typicalSavingEUR)) gespart")
    }
}

// MARK: - Small pieces

/// Tinted capsule ("93 %-Garantie", "Code KLIMATICKET20"). `foreground` must be a text-safe colour.
struct PerkPill: View {
    var text: String
    var symbol: String? = nil
    var foreground: Color = Theme.accentText
    var fill: Color = Theme.accent

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption.weight(.bold))
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(fill.opacity(0.14), in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

/// Gentle press-down scale for card-like buttons.
struct PerkPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
    }
}
