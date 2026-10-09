import SwiftUI
import KlimaCore

/// Small "Öffis vs. Auto" card for the statistics tab (replaces the plain Kilometergeld card) → opens the detail.
struct WorkCarStatsCard: View {
    let snapshot: AnalyticsSnapshot
    /// 0…1 – the sparkline grows with the statistics cards (`StatsGrowOnView`).
    var grow: Double = 1

    @Environment(AppState.self) private var app

    var body: some View {
        let result = WorkCarCalc.result(period: snapshot.ticket, records: snapshot.trips, catalog: app.catalog)
        NavigationLink {
            WorkCarView(period: snapshot.ticket)
                .zoomDestination(id: StatsZoomID.car)
        } label: {
            GlassCard(padding: Theme.Spacing.m + 2) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack(alignment: .top, spacing: Theme.Spacing.s) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Kicker(text: "Öffis vs. Auto")
                            headline(result)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(WorkCarCalc.modeSummary(result)) · \(Format.km(result.roadKm)) Straße")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: Theme.Spacing.xs)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.top, 2)
                    }
                    if result.tripCount > 0 {
                        WorkCarChart(result: result, period: snapshot.ticket, style: .compact, grow: grow)
                            .frame(height: 58)
                            .allowsHitTesting(false)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
        .zoomSource(id: StatsZoomID.car, cornerRadius: Theme.Radius.card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Öffis vs. Auto")
        .accessibilityValue(accessibilityValue(result))
        .accessibilityHint("Öffnet den ausführlichen Auto-Vergleich")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func headline(_ result: CarComparisonResult) -> some View {
        if result.tripCount == 0 {
            Text("Erfasse Fahrten, dann vergleichen wir mit dem Auto")
        } else if result.isCheaperThanCar {
            Text("\(Text(Format.euro(result.savings, decimals: 0)).foregroundStyle(Theme.positiveText)) günstiger als mit dem Auto")
        } else {
            Text("Noch \(Text(Format.euro(result.remainingToBreakEven, decimals: 0)).foregroundStyle(Theme.summitText)) bis zum Gleichstand mit dem Auto")
        }
    }

    private func accessibilityValue(_ result: CarComparisonResult) -> String {
        guard result.tripCount > 0 else { return "Noch keine Fahrten" }
        let base = "Mit dem Auto \(Format.euro(result.carCost, decimals: 0)), dein KlimaTicket \(Format.euro(result.ticketCost, decimals: 0))"
        if result.isCheaperThanCar { return "\(base). \(Format.euro(result.savings, decimals: 0)) günstiger als mit dem Auto." }
        return "\(base). Noch \(Format.euro(result.remainingToBreakEven, decimals: 0)) bis zum Gleichstand."
    }
}
