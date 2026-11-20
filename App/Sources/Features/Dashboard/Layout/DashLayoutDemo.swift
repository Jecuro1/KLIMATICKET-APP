import SwiftUI
import SwiftData
import KlimaCore

// MARK: uebersicht – the calm button at the end of the Übersicht and the CI scenes of „Übersicht nach Maß“ (demo data, no network, no
// system alert; the layout, figures and goals of a scene live in memory only).

/// „Übersicht anpassen“ – a calm text button under the last card.
struct DashCustomizeButton: View {
    /// Shown to everyone once the editor's screens were looked at in screenshots; until then only in this track's CI scenes.
    static let isLive = false

    private var store: DashLayoutStore { .shared }

    var body: some View {
        if Self.isLive || DashLayoutScreenshotHost.screens.contains(LaunchMode.screenshotScreen ?? "") {
            Button {
                store.openEditor()
            } label: {
                Label("Übersicht anpassen", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .padding(.horizontal, Theme.Spacing.m)
                    .frame(minHeight: 44)
                    .contentShape(.capsule)
            }
            .buttonStyle(.pressable)
            .frame(maxWidth: .infinity)
            .padding(.top, DashStyle.sectionSpacing)
            .accessibilityHint("Karten ordnen und ausblenden, Kennzahlen und Ziele wählen")
        }
    }
}

struct DashLayoutScreenshotHost: View {
    static let screens: Set<String> = [
        "dashEdit", "dashEditFull", "dashEditSort", "dashEditAX5", "dashKpis", "dashKpisAX5", "dashGoals", "dashQuiet",
        "dashQuietBottom", "dashKpiPicker", "dashGoalEditor", "dashEditSettings",
    ]

    let screen: String
    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date, order: .reverse)
    private var trips: [TripEntity]
    @State private var isReady = false

    var body: some View {
        ZStack {
            Color.clear
            if isReady { content }
        }
        .dynamicTypeSize(screen.hasSuffix("AX5") ? .accessibility5 : .large)
        .onAppear {
            install()
            isReady = true
        }
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case "dashKpiPicker":
            NavigationStack { DashKpiPicker() }
        case "dashGoalEditor":
            NavigationStack {
                DashEditorSnapshot { snapshot, _ in
                    DashGoalEditor(target: DashGoalEditorTarget(goal: nil), snapshot: snapshot)
                }
            }
        case "dashEditSettings":
            NavigationStack { DashCustomizeView() }
        case "dashEdit", "dashEditFull", "dashEditSort", "dashEditAX5":
            MainTabView()
                .task {
                    app.selectedTab = .overview
                    DashLayoutStore.shared.editorStartsLarge = screen != "dashEdit"
                    try? await Task.sleep(for: .milliseconds(700))
                    DashLayoutStore.shared.openEditor()
                }
        default:
            MainTabView().onAppear { app.selectedTab = .overview }
        }
    }

    /// The scene's layout, figures and goals. Goal targets follow the demo trips of the running month, so the rings show one goal met,
    /// one under way and the break-even goal whatever day the run is on.
    private func install() {
        let store = DashLayoutStore.shared
        let figures: [KpiKind] = [.net, .tripCount, .co2, .costPerDay]
        let goals = demoGoals()
        switch screen {
        case "dashQuiet", "dashQuietBottom":
            store.installDemo(layout: DashPreset.quiet.layout, kpis: figures, goals: goals)
        case "dashKpis", "dashKpisAX5":
            var layout = DashPreset.numbers.layout
            layout.place(.balance, after: .kpis)   // the tiles right under the summit for the capture
            store.installDemo(layout: layout, kpis: figures, goals: goals)
        case "dashGoals":
            var layout = DashLayout.standard   // the rings right under the summit for the capture
            layout.move(fromOffsets: IndexSet(integer: layout.order.firstIndex(of: .goals) ?? 0), toOffset: 0)
            store.installDemo(layout: layout, kpis: figures, goals: goals)
        case "dashGoalEditor":
            store.installDemo(layout: .standard, kpis: [], goals: [])
        default:
            var layout = DashPreset.numbers.layout
            layout.setHidden(.yearReview, true)
            store.installDemo(layout: layout, kpis: figures, goals: Array(goals.prefix(2)))
        }
    }

    private func demoGoals() -> [Goal] {
        guard let ticket = Analytics.activeTicket(in: tickets, selectedID: app.settings.selectedTicketID) else {
            return [Goal(kind: .tripsPerMonth, target: 20), Goal(kind: .valuePerMonth, target: 150)]
        }
        let snapshot = Analytics.make(ticket: ticket, trips: trips, catalog: app.catalog)
        let probe = DashGoalEvaluation.progress([Goal(kind: .tripsPerMonth, target: 100), Goal(kind: .valuePerMonth, target: 2000)],
                                                snapshot: snapshot, catalog: app.catalog)
        let tripsSoFar = probe.first?.actual ?? 0
        let valueSoFar = probe.last?.actual ?? 0
        // Under way: a few more trips than so far; met: a value a bit below what the month already has.
        let tripsGoal = Goal(kind: .tripsPerMonth, target: max(4, tripsSoFar + 6))
        let valueGoal = Goal(kind: .valuePerMonth, target: max(10, ((valueSoFar * 0.8) / 10).rounded(.down) * 10))
        let range = GoalEvaluator.dateRange(for: snapshot.ticket, now: Date())
        let day = Calendar.vienna.date(byAdding: .day, value: 75, to: range.lowerBound).map { min($0, range.upperBound) } ?? range.upperBound
        return [tripsGoal, valueGoal, Goal(kind: .breakEvenBy, until: day)]
    }
}
