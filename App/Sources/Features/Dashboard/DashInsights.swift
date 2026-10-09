import SwiftUI
import SwiftData
import KlimaCore

// MARK: - Recent trips

/// "Letzte Fahrten" (5) in one card; rows dip under the finger and zoom into the trip detail (motion system, Reduce
/// Motion: push), a long press shows the trip's preview card with Bearbeiten · Heute nochmal fahren · Löschen (with
/// "Rückgängig"). "Alle" switches to the Fahrten tab.
struct DashRecentTripsSection: View {
    var trips: [TripEntity]

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: DashStyle.cardSpacing) {
            SectionHeader(title: "Letzte Fahrten", actionTitle: "Alle") {
                app.selectedTab = .trips
            }
            .padding(.horizontal, DashStyle.headerInset)
            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(trips) { trip in
                        if trip.id != trips.first?.id {
                            Rectangle()
                                .fill(Theme.separator)
                                .frame(height: 1)
                                .padding(.leading, Theme.Spacing.m + 42 + Theme.Spacing.s)
                                .accessibilityHidden(true)
                        }
                        row(trip)
                    }
                }
                .padding(.vertical, Theme.Spacing.xxs)
                .clipShape(.rect(cornerRadius: Theme.Radius.card, style: .continuous))
            }
        }
    }

    private func row(_ trip: TripEntity) -> some View {
        NavigationLink {
            TripDetailView(trip: trip)
                .zoomDestination(id: trip.id)
        } label: {
            TripRow(trip: trip)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.xxs)
                .contentShape(.rect)
        }
        .buttonStyle(.pressableCard)
        .zoomSource(id: trip.id, cornerRadius: Theme.Radius.chip)
        .contextMenu {
            menu(for: trip)
        } preview: {
            TripListPreviewCard(trip: trip)
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private func menu(for trip: TripEntity) -> some View {
        let actions = TripListActions(app: app, context: context)
        Button { actions.edit(trip) } label: { Label("Bearbeiten", systemImage: "pencil") }
        Button { withMotion(Motion.smooth) { actions.repeatToday(trip) } } label: {
            Label("Heute nochmal fahren", systemImage: "arrow.clockwise")
        }
        Divider()
        Button(role: .destructive) { withMotion(Motion.smooth) { actions.delete(trip) } } label: {
            Label("Löschen", systemImage: "trash")
        }
    }
}

// MARK: - Next achievement

/// Compact "Nächster Erfolg" row – opens the Gipfelbuch (which zooms out of it). The ring and the rail fill when the card
/// first scrolls into view; a newly unlocked achievement makes the medal pop with a gold ring.
struct DashAchievementTeaser: View {
    var next: Achievement?
    var unlockedCount: Int
    var totalCount: Int
    var action: () -> Void

    /// Bumped when `unlockedCount` goes up (not on the first appearance, not when trips are deleted).
    @State private var unlockTick = 0

    var body: some View {
        Button(action: action) {
            DrawInReader { isDrawn in
                content(isDrawn: isDrawn)
            }
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(accessibilityDetail)
        .accessibilityHint("Öffnet das Gipfelbuch")
        .onChange(of: unlockedCount) { old, new in
            if new > old { unlockTick += 1 }
        }
    }

    private func content(isDrawn: Bool) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            medal(isDrawn: isDrawn)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Kicker(text: next == nil ? "Gipfelbuch" : "Nächster Erfolg")
                    Spacer(minLength: Theme.Spacing.xs)
                    Text("\(unlockedCount) von \(totalCount)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                        .numericValue(Double(unlockedCount))
                }
                // The title gets the full width (a progress label beside it broke "Streckenkenner:in" mid-word).
                Text(next?.title ?? "Alle Erfolge erreicht")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                if let next {
                    HStack(alignment: .center, spacing: Theme.Spacing.xs) {
                        ProgressRail(progress: isDrawn ? next.progress : 0, height: 6)
                        if !next.progressLabel.isEmpty {
                            Text(next.progressLabel)
                                .font(.caption.weight(.medium).monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                                .fixedSize()
                                .numericValue(next.progress)
                        }
                    }
                    .padding(.top, 3)
                }
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frostedCard(cornerRadius: Theme.Radius.card)
        .contentShape(.rect(cornerRadius: Theme.Radius.card, style: .continuous))
        .motionAnimation(Motion.smooth, value: next?.id)
    }

    private var progress: Double { next?.progress ?? 1 }

    private var accessibilityTitle: String {
        guard let next else { return "Gipfelbuch: alle Erfolge erreicht" }
        return "Nächster Erfolg: " + next.title + ". " + next.detail
    }

    private var accessibilityDetail: String {
        let count = "\(unlockedCount) von \(totalCount) Erfolgen erreicht"
        guard let next else { return count }
        return next.progressLabel + ", " + count
    }

    private func medal(isDrawn: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(Theme.textTertiary.opacity(0.35), lineWidth: 3)
            Circle()
                .trim(from: 0, to: isDrawn ? progress : 0)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(Theme.tierGradient(next?.tier ?? .gold))
                .padding(5)
                .opacity(next == nil ? 1 : 0.9)
            Image(systemName: next?.symbolName ?? "book.closed.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.onAccent)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                .symbolReplaceTransition()
        }
        .frame(width: 48, height: 48)
        .celebrate(trigger: unlockTick, haptic: nil)   // the action that unlocked it plays the one haptic
        .celebrationRing(trigger: unlockTick)
        .accessibilityHidden(true)
    }
}

// MARK: - This week

/// "Diese Woche": trips & value of the current week vs. the previous one, with a paired Mon–Sun bar strip.
struct DashWeekInsightCard: View {
    var stats: DashWeekStats

    var body: some View {
        GlassCard(padding: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    Kicker(text: "Diese Woche")
                    Spacer(minLength: Theme.Spacing.xs)
                    trend
                }
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    DashEuroNumeral(amount: stats.value)
                    Text(DashStyle.trips(stats.trips))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .numericValue(Double(stats.trips))
                }
                // The bars grow from the baseline when the card first scrolls into view.
                DrawInReader { isDrawn in
                    bars(isDrawn: isDrawn)
                }
                .padding(.top, Theme.Spacing.xxs)
                legend
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Diese Woche")
        .accessibilityValue(accessibilityText)
    }

    @ViewBuilder
    private var trend: some View {
        if stats.isEmpty {
            Text("Noch keine Fahrten")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        } else if abs(stats.delta) < 0.5 {
            Label("wie Vorwoche", systemImage: "equal")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        } else {
            Label("\(DashStyle.signedEuro(stats.delta)) vs. Vorwoche",
                  systemImage: stats.delta > 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(stats.delta > 0 ? Theme.positiveText : Theme.textSecondary)
                .symbolReplaceTransition()
                .numericValue(stats.delta)
        }
    }

    private func bars(isDrawn: Bool) -> some View {
        let maxValue = max(stats.dayValues.max() ?? 0, stats.previousDayValues.max() ?? 0, 1)
        return VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: Theme.Spacing.xs) {
                ForEach(0..<7, id: \.self) { day in
                    DashDayBars(current: stats.dayValues[day], previous: stats.previousDayValues[day], maxValue: maxValue,
                                isToday: day == stats.todayIndex, isFuture: day > stats.todayIndex)
                        // Grow from the baseline, Monday first (a transform – the layout never changes).
                        .scaleEffect(x: 1, y: isDrawn ? 1 : 0.04, anchor: .bottom)
                        .animation(isDrawn ? Motion.gentle.delay(Motion.Stagger.delay(day)) : nil, value: isDrawn)
                }
            }
            .frame(height: 56)
            .motionAnimation(Motion.gentle, value: stats)
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(0..<7, id: \.self) { day in
                    Text(DashStyle.weekdays[day])
                        .font(.caption2.weight(day == stats.todayIndex ? .bold : .regular))
                        .foregroundStyle(day == stats.todayIndex ? Theme.textPrimary : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.m) {
                currentLegend
                previousLegend
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                currentLegend
                previousLegend
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.textSecondary)
    }

    private var currentLegend: some View {
        HStack(spacing: 5) {
            Capsule().fill(Theme.accent).frame(width: 10, height: 6)
            Text("Diese Woche")
        }
    }

    private var previousLegend: some View {
        HStack(spacing: 5) {
            Capsule().fill(Theme.textTertiary.opacity(0.45)).frame(width: 10, height: 6)
            Text("Vorwoche · \(Format.euro(stats.previousValue, decimals: 0)) · \(DashStyle.trips(stats.previousTrips))")
                .numericValue(stats.previousValue)
        }
    }

    private var accessibilityText: String {
        let current = "\(DashStyle.trips(stats.trips)), \(Format.euroPrecise(stats.value))"
        let previous = "Vorwoche: \(DashStyle.trips(stats.previousTrips)), \(Format.euroPrecise(stats.previousValue))"
        return current + ". " + previous
    }
}

/// One weekday: previous week (ghost) and current week side by side.
private struct DashDayBars: View {
    var current: Double
    var previous: Double
    var maxValue: Double
    var isToday: Bool
    var isFuture: Bool

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            HStack(alignment: .bottom, spacing: 2) {
                Capsule()
                    .fill(Theme.textTertiary.opacity(0.45))
                    .frame(height: barHeight(previous, in: height))
                Capsule()
                    .fill(currentFill)
                    .frame(height: barHeight(current, in: height))
                    .opacity(isFuture ? 0.35 : 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private var currentFill: AnyShapeStyle {
        isToday ? AnyShapeStyle(Theme.ctaGradient) : AnyShapeStyle(Theme.accent)
    }

    private func barHeight(_ value: Double, in height: CGFloat) -> CGFloat {
        guard value > 0, maxValue > 0 else { return 4 }
        return max(6, height * CGFloat(value / maxValue))
    }
}

// MARK: - Empty state

/// Invitation below the 0 % summit scene when no trip has been logged for this ticket yet.
struct DashEmptyInviteCard: View {
    var hasFavorites: Bool
    var onAdd: () -> Void

    var body: some View {
        GlassCard(padding: Theme.Spacing.xxs) {
            VStack(spacing: 0) {
                EmptyStateView(symbol: "flag.checkered",
                               title: "Dein Aufstieg beginnt",
                               message: Copy.subline,
                               actionTitle: "Erste Fahrt erfassen",
                               action: onAdd)
                if !hasFavorites {
                    Label {
                        Text("Tipp: Speichere Strecken, die du oft fährst, als Favorit – dann reicht künftig ein Tipp.")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "star.fill")
                            .foregroundStyle(Theme.gold)
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.bottom, Theme.Spacing.l)
                }
            }
        }
    }
}
