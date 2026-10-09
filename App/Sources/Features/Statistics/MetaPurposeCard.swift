import SwiftUI
import Charts
import KlimaCore

extension AnalyticsSnapshot {
    /// Trips, value and share per purpose ("Wofür du fährst"); uncategorised last.
    var metaCategoryBuckets: [CategoryBucket] { CategoryStats.buckets(trips) }
    /// Payoff split into money really saved and extra value ("Ehrliche Bilanz").
    var metaHonestBalance: HonestBalance { CategoryStats.honestBalance(ticket: ticket, trips: trips) }
}

// MARK: - Wofür du fährst

/// Donut + spotlight + directly labelled rows per trip purpose (value or trips), "Ohne Kategorie" always last.
/// Tapping a slice or a row puts that purpose into the spotlight.
struct MetaPurposeCard: View {
    let snapshot: AnalyticsSnapshot
    let grow: Double

    enum Metric: String, CaseIterable, Identifiable {
        case value, trips
        var id: String { rawValue }
        var title: String { self == .value ? "Wert" : "Fahrten" }
    }

    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title) private var spotlightSize: CGFloat = 30
    @State private var metric: Metric = .value
    @State private var selectedID: String?
    /// The tinted row highlight glides from row to row instead of blinking.
    @Namespace private var rowSelection

    var body: some View {
        let buckets = sorted(snapshot.metaCategoryBuckets)
        let categorised = buckets.filter { !$0.isUncategorized }
        GlassCard(padding: Theme.Spacing.m + 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                header(hasData: !categorised.isEmpty)
                if let top = categorised.first {
                    Text(headline(top))
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                        .padding(.top, -Theme.Spacing.xs)
                    overview(buckets, fallback: top)
                    rows(buckets)
                    footer(buckets)
                } else {
                    emptyContent
                }
            }
        }
        // Switching the metric re-sorts the rows and re-cuts the donut (a layout change → smooth); picking a purpose
        // is a direct touch (snappy). The segmented control plays its own selection haptic.
        .motionAnimation(Motion.smooth, value: metric)
        .motionAnimation(Motion.snappy, value: selectedID)
        .haptic(.selection, trigger: selectedID, when: { _, new in new != nil })
        .metaScreenshotScrollTarget("statsCategories")
    }

    // MARK: Header

    private func header(hasData: Bool) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s) {
            Kicker(text: "Wofür du fährst")
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Spacing.xs)
            if hasData {
                GlassSegmentedPicker(selection: $metric, options: Metric.allCases) { item in
                    Text(item.title)
                }
                .fixedSize()
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Kennzahl")
            }
        }
    }

    private func headline(_ top: CategoryBucket) -> String {
        switch metric {
        case .value: "\(Format.percent(top.valueShare)) deines Werts \(MetaCategoryStyle.phrase(top.category))"
        case .trips: "\(Format.percent(top.tripShare)) deiner Fahrten \(MetaCategoryStyle.phrase(top.category))"
        }
    }

    // MARK: Donut + spotlight

    @ViewBuilder
    private func overview(_ buckets: [CategoryBucket], fallback: CategoryBucket) -> some View {
        let focus = buckets.first { $0.id == selectedID } ?? fallback
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.m))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.l))
        layout {
            donut(buckets, focus: focus)
                .frame(width: 132, height: 132)
            spotlight(focus)
        }
    }

    private func donut(_ buckets: [CategoryBucket], focus: CategoryBucket) -> some View {
        Chart(buckets) { bucket in
            SectorMark(angle: .value(metric.title, amount(bucket)), innerRadius: .ratio(0.64), angularInset: 1.5)
                .cornerRadius(4)
                .foregroundStyle(MetaCategoryStyle.color(bucket.category).opacity(bucket.isUncategorized ? 0.55 : 1))
                .opacity(selectedID == nil || selectedID == bucket.id ? 1 : 0.32)
                .accessibilityLabel(MetaCategoryStyle.name(bucket.category))
                .accessibilityValue(spokenValue(bucket))
        }
        .chartLegend(.hidden)
        .chartAngleSelection(value: angleBinding(buckets))
        .chartBackground { proxy in
            GeometryReader { geo in
                if let anchor = proxy.plotFrame {
                    let frame = geo[anchor]
                    VStack(spacing: 0) {
                        Text(Format.percent(share(focus)))
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                            .numericValue(share(focus))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Image(systemName: MetaCategoryStyle.symbol(focus.category))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(focus.isUncategorized ? Theme.textSecondary : MetaCategoryStyle.color(focus.category))
                            .symbolReplaceTransition()
                    }
                    .frame(width: frame.width * 0.56)
                    .position(x: frame.midX, y: frame.midY)
                    .accessibilityHidden(true)
                }
            }
        }
        .rotationEffect(.degrees(-50 * (1 - grow)))
        .scaleEffect(0.86 + 0.14 * grow)
        .opacity(0.2 + 0.8 * grow)
        .accessibilityLabel(metric == .value ? "Wert nach Kategorie" : "Fahrten nach Kategorie")
    }

    private func spotlight(_ focus: CategoryBucket) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Theme.Spacing.xs) {
                MetaCategoryIcon(category: focus.category, size: 26)
                Text(MetaCategoryStyle.name(focus.category))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(primaryText(focus))
                .font(.system(size: spotlightSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .numericValue(amount(focus))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(secondaryText(focus))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if focus.inducedTrips > 0 {
                Label {
                    Text("davon \(StatsNames.trips(focus.inducedTrips)) Mehrwert")
                } icon: {
                    Image(systemName: MetaCategoryStyle.inducedSymbol).foregroundStyle(MetaCategoryStyle.inducedColor)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(selectedID == nil ? "Größte Kategorie: \(MetaCategoryStyle.name(focus.category))"
                                              : "Ausgewählt: \(MetaCategoryStyle.name(focus.category))")
        .accessibilityValue(spokenValue(focus))
    }

    // MARK: Rows

    private func rows(_ buckets: [CategoryBucket]) -> some View {
        VStack(spacing: 2) {
            ForEach(buckets) { bucket in
                row(bucket)
            }
        }
    }

    private func row(_ bucket: CategoryBucket) -> some View {
        let isSelected = selectedID == bucket.id
        let color = MetaCategoryStyle.color(bucket.category)
        return Button {
            selectedID = isSelected ? nil : bucket.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: Theme.Spacing.xs) {
                    MetaCategoryIcon(category: bucket.category, size: 24)
                    Text(MetaCategoryStyle.name(bucket.category))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(bucket.isUncategorized ? Theme.textSecondary : Theme.textPrimary)
                        .lineLimit(1)
                    if bucket.inducedTrips > 0 {
                        Image(systemName: MetaCategoryStyle.inducedSymbol)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(MetaCategoryStyle.inducedColor)
                    }
                    Spacer(minLength: Theme.Spacing.xxs)
                    Text(primaryText(bucket))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .numericValue(amount(bucket))
                    Text(Format.percent(share(bucket)))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .frame(minWidth: 38, alignment: .trailing)
                        .numericValue(share(bucket))
                }
                ProgressRail(progress: share(bucket) * grow, height: 4,
                             fill: AnyShapeStyle(color.opacity(bucket.isUncategorized ? 0.6 : 1)))
                    .padding(.leading, 32)
            }
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Theme.Radius.modeTile, style: .continuous)
                        .fill(color.opacity(0.12))
                        .matchedGeometryEffect(id: "purpose.selection", in: rowSelection)
                }
            }
            .contentShape(.rect(cornerRadius: Theme.Radius.modeTile))
        }
        .buttonStyle(.pressableCard)
        .padding(.horizontal, -Theme.Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MetaCategoryStyle.name(bucket.category))
        .accessibilityValue(spokenValue(bucket))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Footer & empty state

    @ViewBuilder
    private func footer(_ buckets: [CategoryBucket]) -> some View {
        let uncategorized = buckets.first { $0.isUncategorized }
        let work = CategoryStats.workRelatedValueShare(snapshot.trips)
        if (work ?? 0) > 0 || uncategorized != nil {
            VStack(alignment: .leading, spacing: 6) {
                if let work, work > 0 {
                    Label {
                        Text("\(Format.percent(work)) deines Werts beruflich – Arbeitsweg und Dienstreisen")
                    } icon: {
                        Image(systemName: "briefcase.fill").foregroundStyle(MetaCategoryStyle.color(.commute))
                    }
                }
                if let uncategorized {
                    Label {
                        Text("\(StatsNames.trips(uncategorized.trips)) ohne Kategorie – in der Fahrtenliste lange drücken, um sie zuzuordnen.")
                    } icon: {
                        Image(systemName: "hand.tap.fill").foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Wofür lohnt sich dein Ticket?")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("Wähle beim Erfassen, wofür du unterwegs warst – Arbeitsweg, Freizeit, Urlaub … Dann siehst du hier, welcher Teil deines Alltags dein Ticket bezahlt macht.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(TripCategory.allCases) { category in
                    MetaCategoryIcon(category: category, size: 28)
                }
            }
            .accessibilityHidden(true)
            .padding(.top, Theme.Spacing.xxs)
        }
    }

    // MARK: Derived

    /// Ordered by the current metric; "Ohne Kategorie" stays last.
    private func sorted(_ buckets: [CategoryBucket]) -> [CategoryBucket] {
        let order = TripCategory.allCases
        func rank(_ bucket: CategoryBucket) -> Int { bucket.category.flatMap { order.firstIndex(of: $0) } ?? order.count }
        return buckets.sorted { lhs, rhs in
            if lhs.isUncategorized != rhs.isUncategorized { return rhs.isUncategorized }
            if amount(lhs) != amount(rhs) { return amount(lhs) > amount(rhs) }
            return rank(lhs) < rank(rhs)
        }
    }

    private func amount(_ bucket: CategoryBucket) -> Double {
        metric == .value ? bucket.value : Double(bucket.trips)
    }

    private func share(_ bucket: CategoryBucket) -> Double {
        metric == .value ? bucket.valueShare : bucket.tripShare
    }

    private func primaryText(_ bucket: CategoryBucket) -> String {
        metric == .value ? Format.euro(bucket.value, decimals: 0) : StatsNames.trips(bucket.trips)
    }

    private func secondaryText(_ bucket: CategoryBucket) -> String {
        metric == .value
            ? "\(StatsNames.trips(bucket.trips)) · \(Format.percent(bucket.valueShare)) des Werts"
            : "\(Format.euro(bucket.value, decimals: 0)) Wert · \(Format.percent(bucket.tripShare)) der Fahrten"
    }

    private func spokenValue(_ bucket: CategoryBucket) -> String {
        var text = "\(Format.euro(bucket.value, decimals: 0)), \(StatsNames.trips(bucket.trips)), \(Format.percent(share(bucket)))"
        text += metric == .value ? " des Werts" : " der Fahrten"
        if bucket.inducedTrips > 0 { text += ", davon \(StatsNames.trips(bucket.inducedTrips)) ohne KlimaTicket nicht gefahren" }
        return text
    }

    /// Dragging around the donut reports a new angle every frame. Stored in `@State`, each frame re-ran this body and
    /// rebuilt the chart; mapped straight to the slice instead, the state changes only when the finger enters another
    /// slice (and stays on lift-off).
    private func angleBinding(_ buckets: [CategoryBucket]) -> Binding<Double?> {
        Binding(get: { nil }, set: { value in
            guard let value, let id = bucket(atCumulative: value, in: buckets)?.id, id != selectedID else { return }
            selectedID = id
        })
    }

    /// `chartAngleSelection` reports the cumulative amount under the finger – walk the slices to find it.
    private func bucket(atCumulative value: Double, in buckets: [CategoryBucket]) -> CategoryBucket? {
        var running = 0.0
        for bucket in buckets {
            running += amount(bucket)
            if value <= running { return bucket }
        }
        return buckets.last
    }
}
