import SwiftUI
import SwiftData
import KlimaCore

// "Reise mit Etappen" in the Fahrten list (docs/JOURNEYS.md §5): a journey is ONE row – first start, last destination,
// the legs' modes as a strip, the summed value. A tap unfolds its legs below (each opens its own detail) and
// "Reise ansehen" (the journey detail: timeline, map, actions).

// MARK: - Model

/// A row of the Fahrten list: a trip of its own, or a journey with its legs in travel order.
struct TripListItem: Identifiable {
    /// The trip's id, or the journey's.
    let id: UUID
    let legs: [TripEntity]

    var first: TripEntity { legs[0] }
    var last: TripEntity { legs[legs.count - 1] }
    var isJourney: Bool { legs.count > 1 }
    var date: Date { first.date }
    var totalValue: Double { legs.reduce(0) { $0 + $1.totalValue } }
    var totalDistanceKm: Double { legs.reduce(0) { $0 + $1.totalDistanceKm } }
    var modes: [TransportMode] { legs.map(\.mode) }

    /// Trips (newest first) → rows: the legs of a journey gather in the row of its first appearance, in travel order. A
    /// journey with one live leg left is a trip again.
    static func group(_ trips: [TripEntity]) -> [TripListItem] {
        var order: [UUID] = []
        var buckets: [UUID: [TripEntity]] = [:]
        for trip in trips {
            let key = trip.journeyID ?? trip.id
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(trip)
        }
        return order.compactMap { key in
            guard var legs = buckets[key], !legs.isEmpty else { return nil }
            if legs.count == 1 { return TripListItem(id: legs[0].id, legs: legs) }
            legs.sort { ($0.legIndex, $0.date, $0.createdAt) < ($1.legIndex, $1.date, $1.createdAt) }
            return TripListItem(id: key, legs: legs)
        }
    }
}

// MARK: - Rows

/// Collapsed journey row: "HEUTE / 07:12" · ◯ Lech / ● Wien Praterstern · 🚌›🚆›🚇 3 Etappen ⌄ · € 90,40.
struct TripListJourneyRow: View {
    let item: TripListItem
    let isExpanded: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var dateColumnWidth: CGFloat = 62
    @ScaledMetric(relativeTo: .subheadline) private var stationSpacing: CGFloat = 7

    private var isStacked: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        let layout = isStacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.s))
        layout {
            TripListDateColumn(date: item.date, width: dateColumnWidth, isStacked: isStacked)
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: 5) {
                    stations
                    legStrip
                }
                .alignmentGuide(.listRowSeparatorLeading) { dimensions in dimensions[.leading] }
                Spacer(minLength: Theme.Spacing.xs)
                trailing
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityValue(spokenValue)
        .accessibilityHint(isExpanded ? "Blendet die Etappen aus" : "Zeigt die Etappen")
        .accessibilityAddTraits(.isButton)
    }

    private var stations: some View {
        VStack(alignment: .leading, spacing: stationSpacing) {
            Text(TripRow.short(item.first.fromName))
            Text(TripRow.short(item.last.toName))
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Theme.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .padding(.leading, 21)
        .background(alignment: .leading) { glyph }
    }

    private var glyph: some View {
        GeometryReader { geo in
            let line = max(0, (geo.size.height - stationSpacing) / 2)
            RouteGlyph(color: Theme.modeColor(item.first.mode), endColor: Theme.summit, height: line + stationSpacing + 11)
                .offset(y: line / 2 - 5.5)
        }
        .frame(width: 11)
    }

    /// "🚌 › 🚆 › 🚇  3 Etappen ⌄" – the disclosure of the row.
    private var legStrip: some View {
        HStack(spacing: 6) {
            TripJourneyModeStrip(modes: item.modes)
            Text(TripJourneyFormat.legCount(item.legs.count))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.textSecondary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .padding(.leading, 21)
    }

    private var trailing: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text(Format.euroPrecise(item.totalValue))
                .font(Theme.Typography.numberSmall)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .numericValue(item.totalValue)
            HStack(spacing: 5) {
                MetaTripRowPurpose(category: item.first.category, isInduced: item.legs.contains(where: \.isInduced))
                if item.first.isRoundTrip {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .fixedSize()
    }

    private var spokenLabel: String {
        var text = "Reise von \(item.first.fromName) nach \(item.last.toName), \(TripJourneyFormat.legCount(item.legs.count)): "
            + TripJourneyFormat.modeList(item.modes)
        if let transfers = TripJourneyFormat.transfers(item.legs.dropLast().map(\.toName)) { text += ", " + transfers }
        if item.first.isRoundTrip { text += ", hin und retour" }
        return text
    }

    private var spokenValue: String {
        var parts = [Format.euroPrecise(item.totalValue), Format.relativeDay(item.date), Format.time(item.date)]
        if let category = item.first.category { parts.append(category.displayName) }
        let note = item.first.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { parts.append("Notiz: \(note)") }
        return parts.joined(separator: ", ")
    }
}

/// "HEUTE / 07:12" – the date column of the list rows (as TripListRow's).
struct TripListDateColumn: View {
    let date: Date
    let width: CGFloat
    let isStacked: Bool

    var body: some View {
        if isStacked {
            Text("\(TripListFormat.dayLabel(date)) · \(Format.time(date))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Kicker(text: TripListFormat.dayLabel(date))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(Format.time(date))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: width, alignment: .leading)
        }
    }
}

/// An unfolded leg under its journey: the leg's mode colour runs down the rail · mode plate · "Bus" / "Lech → Langen" ·
/// price ›. Opens the leg's detail.
struct TripListJourneyLegRow: View {
    let leg: TripEntity
    let index: Int
    let count: Int

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var dateColumnWidth: CGFloat = 62

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            if !dynamicTypeSize.isAccessibilitySize {
                rail
                    .frame(width: dateColumnWidth)
            }
            ModeIcon(mode: leg.mode, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(leg.mode.displayName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if let badge = TripListFormat.badge(for: leg.mode), badge != leg.mode.displayName {
                        TripListModeBadge(text: badge)
                    }
                }
                Text(TripListFormat.routeTitle(leg.fromName, leg.toName))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                let via = leg.via
                if !via.isEmpty { ViaCaption(vias: via) }
            }
            Spacer(minLength: Theme.Spacing.xs)
            Text(Format.euroPrecise(leg.totalValue))
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Etappe \(index + 1) von \(count): \(leg.mode.displayName), \(leg.fromName) nach \(leg.toName)")
        .accessibilityValue(Format.euroPrecise(leg.totalValue))
        .accessibilityHint("Zeigt die Details der Etappe")
    }

    /// "2" in a small circle on a line in the leg's mode colour – the journey's timeline continues down the rows.
    private var rail: some View {
        HStack {
            Spacer(minLength: 0)
            Text("\(index + 1)")
                .font(.caption2.weight(.heavy).monospacedDigit())
                .foregroundStyle(Theme.modeColor(leg.mode))
                .frame(width: 20, height: 20)
                .background(Theme.modeColor(leg.mode).opacity(0.14), in: .circle)
                .overlay(Circle().strokeBorder(Theme.modeColor(leg.mode).opacity(0.45), lineWidth: 1))
        }
        .padding(.trailing, 4)
        .accessibilityHidden(true)
    }
}

/// "Reise ansehen" under the unfolded legs – the journey detail (zooms out of this row).
struct TripListJourneyDetailLinkRow: View {
    let item: TripListItem

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var dateColumnWidth: CGFloat = 62

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            if !dynamicTypeSize.isAccessibilitySize {
                Color.clear.frame(width: dateColumnWidth, height: 1)
            }
            Label("Reise ansehen", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accentText)
            Spacer(minLength: Theme.Spacing.xs)
            Text("Karte & Summe")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reise ansehen")
        .accessibilityHint("Zeigt Zeitleiste, Karte und Summe der Reise")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Long-press preview

/// Context-menu preview of a journey: date, total, the leg timeline.
struct TripListJourneyPreviewCard: View {
    let item: TripListItem

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                Kicker(text: TripListFormat.detailDateLine(item.date))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: Theme.Spacing.xs)
                TripJourneyModeStrip(modes: item.modes)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("€")
                    .font(.system(.title2, design: .rounded, weight: .light))
                    .foregroundStyle(Theme.textSecondary)
                Text(Format.number(item.totalValue, decimals: 2))
                    .font(Theme.Typography.priceNumeral)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(TripJourneyFormat.legCount(item.legs.count))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(item.legs.enumerated()), id: \.element.id) { _, leg in
                    HStack(spacing: Theme.Spacing.s) {
                        ModeIcon(mode: leg.mode, size: 24)
                        Text(TripListFormat.routeTitle(leg.fromName, leg.toName))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: Theme.Spacing.xs)
                        Text(Format.euroPrecise(leg.totalValue))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .padding(Theme.Spacing.l)
        .frame(width: 320, alignment: .leading)
        .background(Theme.sheetBackground)
    }
}
