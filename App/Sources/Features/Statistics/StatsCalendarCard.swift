import SwiftUI
import KlimaCore

/// "Reise-Kalender": weeks × weekdays heatmap across the whole ticket period with a single-hue
/// brightness ramp (glacier), today ringed in dawn, future days dashed. Tap a day for its trips.
struct StatsCalendarCard: View {
    let snapshot: AnalyticsSnapshot

    @Environment(AppState.self) private var app
    @ScaledMetric(relativeTo: .caption2) private var cell: CGFloat = 15
    @State private var selectedDay: Date?

    private let gap: CGFloat = 3

    var body: some View {
        let weeks = StatsCalc.heatmap(snapshot)
        GlassCard(padding: Theme.Spacing.m + 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                header(weeks)
                HStack(alignment: .top, spacing: 6) {
                    weekdayColumn
                    grid(weeks)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Reise-Kalender")
                .accessibilityValue(summaryText)
                legend
                selectionLine(weeks)
            }
        }
        .sensoryFeedback(.selection, trigger: selectedDay) { _, new in
            new != nil && app.settings.hapticsEnabled
        }
    }

    // MARK: Header & footer

    private func header(_ weeks: [StatsHeatWeek]) -> some View {
        StatsCardHeader(kicker: "Reise-Kalender · \(weeks.count) Wochen", title: summaryText)
    }

    private var summaryText: String {
        let summary = snapshot.summary
        var parts = [StatsNames.trips(summary.tripCount), summary.travelDays == 1 ? "1 Reisetag" : "\(summary.travelDays) Reisetage"]
        if snapshot.records.longestStreakDays > 1 {
            parts.append("Längste Serie \(Format.days(snapshot.records.longestStreakDays))")
        }
        return parts.joined(separator: " · ")
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("weniger")
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(StatsHeat.color(level: level))
                    .frame(width: 11, height: 11)
            }
            Text("mehr")
            Spacer(minLength: Theme.Spacing.xs)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Theme.summit, lineWidth: 2)
                .frame(width: 11, height: 11)
            Text("Heute")
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(1)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func selectionLine(_ weeks: [StatsHeatWeek]) -> some View {
        let day = heatDay(for: selectedDay, in: weeks)
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: day == nil ? "hand.tap" : "calendar")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(day == nil ? Theme.textTertiary : Theme.accentText)
            if let day {
                Text(Format.weekdayDayMonth(day.date))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(day.trips == 0 ? "keine Fahrt" : "\(StatsNames.trips(day.trips)) · \(Format.euro(day.value))")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("Tippe auf einen Tag für Details")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.textTertiary.opacity(0.08), in: .rect(cornerRadius: Theme.Radius.modeTile, style: .continuous))
        .accessibilityElement(children: .combine)
        .animation(.snappy(duration: 0.25), value: selectedDay)
    }

    private func heatDay(for date: Date?, in weeks: [StatsHeatWeek]) -> StatsHeatDay? {
        guard let date else { return nil }
        for week in weeks {
            if let match = week.days.first(where: { $0.date == date }) { return match }
        }
        return nil
    }

    // MARK: Grid

    private var weekdayColumn: some View {
        VStack(alignment: .trailing, spacing: gap) {
            Text(" ")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            ForEach(0..<7, id: \.self) { index in
                Text(index % 2 == 0 ? StatsNames.weekdayShort[index] : " ")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(height: cell)
            }
        }
        .accessibilityHidden(true)
    }

    private func grid(_ weeks: [StatsHeatWeek]) -> some View {
        let todayWeek = weeks.firstIndex { week in week.days.contains { $0.isToday } } ?? max(weeks.count - 1, 0)
        let target = min(todayWeek + 2, max(weeks.count - 1, 0))
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: gap) {
                    ForEach(weeks) { week in
                        weekColumn(week)
                            .id(week.id)
                    }
                }
                .padding(.trailing, Theme.Spacing.xxs)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                proxy.scrollTo(target, anchor: .trailing)
                // Second pass once the horizontal content has been laid out.
                DispatchQueue.main.async { proxy.scrollTo(target, anchor: .trailing) }
            }
            // Another ticket year picked: open the new period on its current (or last) week as well.
            .onChange(of: snapshot.ticket.start) { _, _ in
                DispatchQueue.main.async { proxy.scrollTo(target, anchor: .trailing) }
            }
        }
    }

    private func weekColumn(_ week: StatsHeatWeek) -> some View {
        VStack(alignment: .leading, spacing: gap) {
            Text(week.monthLabel ?? " ")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .fixedSize()
                .frame(width: cell, alignment: .leading)
            ForEach(week.days) { day in
                dayCell(day)
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: StatsHeatDay) -> some View {
        let shape = RoundedRectangle(cornerRadius: cell * 0.28, style: .continuous)
        switch day.kind {
        case .outside:
            Color.clear
                .frame(width: cell, height: cell)
        case .future:
            shape
                .strokeBorder(Theme.textTertiary.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .frame(width: cell, height: cell)
        case .past:
            shape
                .fill(StatsHeat.color(level: day.level))
                .frame(width: cell, height: cell)
                .overlay {
                    if day.isToday {
                        shape.strokeBorder(Theme.summit, lineWidth: 2)
                    } else if selectedDay == day.date {
                        shape.strokeBorder(Theme.textPrimary, lineWidth: 1.5)
                    }
                }
                .scaleEffect(selectedDay == day.date ? 1.18 : 1)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.snappy(duration: 0.25)) {
                        selectedDay = selectedDay == day.date ? nil : day.date
                    }
                }
        }
    }
}
