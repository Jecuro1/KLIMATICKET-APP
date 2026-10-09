import SwiftUI
import KlimaCore

// MARK: - Top-Strecken

/// Ranked list of the most travelled routes with proportional bars.
struct StatsTopRoutesCard: View {
    let snapshot: AnalyticsSnapshot
    let grow: Double

    var body: some View {
        let routes = snapshot.topRoutes
        let maxTrips = Double(routes.map(\.trips).max() ?? 1)
        GlassCard(padding: Theme.Spacing.m + 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                StatsCardHeader(kicker: "Top-Strecken", title: "Deine Stammstrecken")
                VStack(spacing: Theme.Spacing.s) {
                    ForEach(Array(routes.enumerated()), id: \.element.id) { index, route in
                        row(route, rank: index + 1, fraction: Double(route.trips) / max(maxTrips, 1))
                        if index < routes.count - 1 {
                            Rectangle()
                                .fill(Theme.separator)
                                .frame(height: 0.5)
                                .padding(.leading, 34)
                        }
                    }
                }
            }
        }
    }

    private func row(_ route: RouteStat, rank: Int, fraction: Double) -> some View {
        let title = "\(TripRow.short(route.fromName)) ⇄ \(TripRow.short(route.toName))"
        let fill = rank == 1
            ? AnyShapeStyle(Theme.routeGradient)
            : AnyShapeStyle(LinearGradient(colors: [Theme.glacier.opacity(0.9), Theme.glacier.opacity(0.55)],
                                           startPoint: .leading, endPoint: .trailing))
        return HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Text("\(rank)")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(rank == 1 ? Theme.summitText : Theme.textTertiary)
                .frame(minWidth: 22, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    Spacer(minLength: Theme.Spacing.xs)
                    Text(Format.euro(route.value, decimals: 0))
                        .font(Theme.Typography.numberSmall)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                ProgressRail(progress: fraction * grow, height: 6, fill: fill)
                Text("\(StatsNames.trips(route.trips)) · \(Format.km(route.distanceKm))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Platz \(rank): \(route.fromName) und \(route.toName)")
        .accessibilityValue("\(StatsNames.trips(route.trips)), \(Format.euro(route.value, decimals: 0)), \(Format.km(route.distanceKm))")
    }
}

// MARK: - Rekorde

/// Record tiles: longest & most valuable trip, best month, streaks, stations.
struct StatsRecordsSection: View {
    let snapshot: AnalyticsSnapshot

    @Environment(\.dynamicTypeSize) private var typeSize

    private var columns: [GridItem] {
        let count = typeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.s, alignment: .top), count: count)
    }

    var body: some View {
        let records = snapshot.records
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(title: "Rekorde")
                .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.s) {
                tiles(records)
            }
        }
    }

    /// Each tile settles in on its own as it scrolls up from the bottom edge.
    @ViewBuilder
    private func tiles(_ records: TravelRecords) -> some View {
        Group {
            if let trip = records.longestTrip {
                StatTile(value: Format.number(trip.distanceKm), unit: "km",
                         label: "Längste Fahrt · \(routeName(trip))",
                         symbol: "arrow.left.and.right", color: Theme.accent)
            }
            if let trip = records.mostValuableTrip {
                StatTile(value: Format.euro(trip.totalValue), label: "Wertvollste Fahrt · \(routeName(trip))",
                         symbol: "eurosign", color: Theme.summit)
            }
            if let month = records.bestMonth {
                StatTile(value: Format.euro(month.value, decimals: 0),
                         label: "Bester Monat · \(StatsNames.wideMonth(month.month))",
                         symbol: "crown.fill", color: Theme.gold)
            }
            StatTile(value: "\(records.longestStreakDays)", unit: records.longestStreakDays == 1 ? "Tag" : "Tage",
                     label: "Längste Serie in Folge", symbol: "calendar", color: Theme.dusk)
            StatTile(value: "\(records.currentStreakDays)", unit: records.currentStreakDays == 1 ? "Tag" : "Tage",
                     label: "Aktuelle Serie", symbol: "clock.arrow.circlepath", color: Theme.positive)
            StatTile(value: "\(records.uniqueStations)", label: "Verschiedene Haltestellen",
                     symbol: "mappin.and.ellipse", color: Theme.alpenglow)
        }
        .scrollCardTransition()
    }

    private func routeName(_ trip: TripRecord) -> String {
        "\(TripRow.short(trip.fromName)) → \(TripRow.short(trip.toName))"
    }
}

// MARK: - Bundesländer

/// Nine state chips – visited ones highlighted (with a check, not colour alone).
struct StatsStatesCard: View {
    let snapshot: AnalyticsSnapshot

    private var states: [FederalState] { FederalState.allCases.filter { $0 != .foreign } }

    var body: some View {
        let visited = snapshot.records.statesVisited
        let count = states.filter { visited.contains($0.rawValue) }.count
        GlassCard(padding: Theme.Spacing.m + 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                StatsCardHeader(kicker: "Bundesländer bereist", title: nil) {
                    if count == states.count {
                        StatsBadge(text: "Ganz Österreich", symbol: "flag.checkered",
                                   foreground: Theme.positiveText, fill: Theme.positive.opacity(0.16))
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(count)")
                        .font(Theme.Typography.numberLarge)
                        .foregroundStyle(Theme.textPrimary)
                        .numericValue(Double(count))
                    Text("von \(states.count) Bundesländern")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Theme.Spacing.xs)],
                          alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(states) { state in
                        chip(state, isVisited: visited.contains(state.rawValue))
                    }
                }
            }
        }
    }

    private func chip(_ state: FederalState, isVisited: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: isVisited ? "checkmark.circle.fill" : "circle.dashed")
                .font(.caption.weight(.bold))
            Text(state.displayName)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(isVisited ? Theme.positiveText : Theme.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(isVisited ? Theme.positive.opacity(0.16) : Theme.textTertiary.opacity(0.10), in: .capsule)
        .overlay(Capsule().strokeBorder(isVisited ? Theme.positive.opacity(0.35) : Theme.separator, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.displayName)
        .accessibilityValue(isVisited ? "bereist" : "noch nicht bereist")
    }
}

// MARK: - Gipfelbuch

/// Compact entry to the "Gipfelbuch" (achievements), presented as a sheet from the statistics tab
/// via the shared `app.isShowingAchievements` flag.
struct StatsSummitBookRow: View {
    let snapshot: AnalyticsSnapshot

    @Environment(AppState.self) private var app

    var body: some View {
        let unlocked = snapshot.unlockedAchievements.count
        let total = snapshot.achievements.count
        Button {
            app.isShowingAchievements = true
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                // The book opens: the closed book morphs into an open one while its sheet zooms out of this row.
                Image(systemName: app.isShowingAchievements ? "book.fill" : "book.closed.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .symbolReplaceTransition()
                    .frame(width: 44, height: 44)
                    .background(Theme.tierGradient(.gold), in: .rect(cornerRadius: Theme.Radius.modeTile, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gipfelbuch")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: Theme.Spacing.xs)
                Text("\(unlocked)/\(total)")
                    .font(Theme.Typography.numberSmall)
                    .foregroundStyle(Theme.textPrimary)
                    .numericValue(Double(unlocked))
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frostedCard(cornerRadius: Theme.Radius.tile)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
        .zoomSource(id: StatsZoomID.summitBook, cornerRadius: Theme.Radius.tile)
        .accessibilityLabel("Gipfelbuch, \(unlocked) von \(total) Erfolgen")
        .accessibilityHint(detail)
        .sheet(isPresented: sheetBinding) {
            NavigationStack {
                AchievementsView()
            }
            .zoomDestination(id: StatsZoomID.summitBook)
        }
    }

    /// Shared flag (also used by the dashboard) – only the visible tab presents the sheet.
    private var sheetBinding: Binding<Bool> {
        Binding(get: { app.isShowingAchievements && app.selectedTab == .stats },
                set: { app.isShowingAchievements = $0 })
    }

    private var detail: String {
        guard let next = snapshot.nextAchievement else { return "Alle Erfolge erreicht – Gratulation!" }
        return "Als Nächstes: \(next.title) · \(next.progressLabel)"
    }
}
