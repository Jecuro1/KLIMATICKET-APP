import SwiftUI
import Charts
import KlimaCore

// MARK: - Verkehrsmittel

/// Small donut (share of value) + directly labelled horizontal bars per transport mode – never colour alone.
struct StatsModesCard: View {
    let snapshot: AnalyticsSnapshot
    let grow: Double

    @Environment(\.dynamicTypeSize) private var typeSize

    private var totalValue: Double { max(snapshot.modes.reduce(0) { $0 + $1.value }, 0.01) }

    var body: some View {
        GlassCard(padding: Theme.Spacing.m + 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                StatsCardHeader(kicker: "Verkehrsmittel", title: headline)
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.m))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.l))
                layout {
                    donut
                        .frame(width: 118, height: 118)
                    rows
                }
            }
        }
    }

    private var headline: String {
        guard let top = snapshot.modes.first else { return "Noch keine Fahrten" }
        let share = Format.percent(top.value / totalValue)
        return "\(share) deines Werts mit \(dative(top.mode))"
    }

    /// "mit dem Zug", "mit der Bim" …
    private func dative(_ mode: TransportMode) -> String {
        switch mode {
        case .train: "dem Zug"
        case .sBahn: "der S-Bahn"
        case .metro: "der U-Bahn"
        case .tram: "der Bim"
        case .bus: "dem Bus"
        case .ferry: "dem Schiff"
        case .cableCar: "der Seilbahn"
        case .other: "sonstigen Öffis"
        }
    }

    private var donut: some View {
        Chart(snapshot.modes) { bucket in
            SectorMark(angle: .value("Wert", bucket.value), innerRadius: .ratio(0.62), angularInset: 1.5)
                .cornerRadius(4)
                .foregroundStyle(Theme.modeColor(bucket.mode))
                .accessibilityLabel(bucket.mode.displayName)
                .accessibilityValue("\(Format.percent(bucket.value / totalValue)), \(Format.euro(bucket.value, decimals: 0)), \(StatsNames.trips(bucket.trips))")
        }
        .chartLegend(.hidden)
        .chartBackground { proxy in
            GeometryReader { geo in
                if let anchor = proxy.plotFrame {
                    let frame = geo[anchor]
                    VStack(spacing: 0) {
                        Text("\(snapshot.summary.tripCount)")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .numericValue(Double(snapshot.summary.tripCount))
                        Text("Fahrten")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(width: frame.width * 0.56)
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .rotationEffect(.degrees(-50 * (1 - grow)))
        .scaleEffect(0.86 + 0.14 * grow)
        .opacity(0.2 + 0.8 * grow)
        .accessibilityLabel("Verkehrsmittel nach Wert")
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(snapshot.modes.prefix(5)) { bucket in
                row(bucket)
            }
            if snapshot.modes.count > 5 {
                Text("+ \(snapshot.modes.count - 5) weitere")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ bucket: ModeBucket) -> some View {
        let share = bucket.value / totalValue
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: Theme.Spacing.xs) {
                ModeIcon(mode: bucket.mode, size: 22)
                Text(bucket.mode.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(bucket.trips) · \(Format.percent(share))")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .numericValue(share)
            }
            ProgressRail(progress: share * grow, height: 5, fill: AnyShapeStyle(Theme.modeColor(bucket.mode)))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bucket.mode.displayName)
        .accessibilityValue("\(StatsNames.trips(bucket.trips)), \(Format.euro(bucket.value, decimals: 0)), \(Format.percent(share)) des Werts")
    }
}

// MARK: - Wochentage

/// Trips per weekday – favourite day highlighted.
struct StatsWeekdayCard: View {
    let snapshot: AnalyticsSnapshot
    let grow: Double

    private var favorite: WeekdayBucket? {
        snapshot.weekdays.filter { $0.trips > 0 }.max { ($0.trips, $0.value) < ($1.trips, $1.value) }
    }

    private var weekdayShare: Double {
        let total = snapshot.weekdays.reduce(0) { $0 + $1.trips }
        guard total > 0 else { return 0 }
        let workdays = snapshot.weekdays.filter { $0.weekday <= 5 }.reduce(0) { $0 + $1.trips }
        return Double(workdays) / Double(total)
    }

    var body: some View {
        GlassCard(padding: Theme.Spacing.m + 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                StatsCardHeader(kicker: "Wochentage", title: headline)
                chart
                    .frame(height: 150)
                Text("\(Format.percent(weekdayShare)) deiner Fahrten an Werktagen, \(Format.percent(1 - weekdayShare)) am Wochenende")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var headline: String {
        guard let favorite else { return "Noch keine Fahrten" }
        return "Am liebsten unterwegs: \(StatsNames.wideWeekday(favorite.weekday))"
    }

    private var maxTrips: Double { Double(snapshot.weekdays.map(\.trips).max() ?? 1) }

    private var chart: some View {
        Chart(snapshot.weekdays) { day in
            BarMark(x: .value("Wochentag", day.shortName), y: .value("Fahrten", Double(day.trips) * grow), width: .ratio(0.56))
                .cornerRadius(5)
                .foregroundStyle(style(for: day))
                .annotation(position: .top, spacing: 3) {
                    Text("\(day.trips)")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(day.weekday == favorite?.weekday ? Theme.textPrimary : Theme.textSecondary)
                        .opacity(grow)
                }
                .accessibilityLabel(StatsNames.wideWeekday(day.weekday))
                .accessibilityValue("\(StatsNames.trips(day.trips)), \(Format.euro(day.value, decimals: 0))")
        }
        .chartYScale(domain: 0...max(maxTrips * 1.25, 1))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let name = value.as(String.self) {
                        Text(name)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .accessibilityLabel("Fahrten pro Wochentag")
    }

    private func style(for day: WeekdayBucket) -> AnyShapeStyle {
        if day.weekday == favorite?.weekday {
            return AnyShapeStyle(LinearGradient(colors: [Theme.dawn, Theme.dusk], startPoint: .top, endPoint: .bottom))
        }
        let base = day.weekday >= 6 ? Theme.dusk : Theme.glacier
        return AnyShapeStyle(LinearGradient(colors: [base.opacity(0.85), base.opacity(0.42)], startPoint: .top, endPoint: .bottom))
    }
}
