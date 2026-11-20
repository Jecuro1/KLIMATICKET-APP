import SwiftUI
import SwiftData
import KlimaCore

// MARK: uebersicht – the calm button at the end of the Übersicht and the CI scenes of „Übersicht nach Maß“ (demo data, no network, no
// system alert; the layout, figures and goals of a scene live in memory only).

/// „Übersicht anpassen“ – a calm text button under the last card.
struct DashCustomizeButton: View {
    /// Live for everyone (the editor's screens were looked at in two screenshot runs, light and dark, AX5).
    static let isLive = true
    /// The button and the row in Einstellungen › Darstellung.
    static var isShown: Bool { isLive || DashLayoutScreenshotHost.screens.contains(LaunchMode.screenshotScreen ?? "") }

    private var store: DashLayoutStore { .shared }

    var body: some View {
        if Self.isShown {
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

/// Einstellungen › Darstellung › „Übersicht anpassen“ – the editor as a page.
struct DashSettingsRow: View {
    var body: some View {
        NavigationLink {
            DashCustomizeView()
        } label: {
            SetRowLabel(title: "Übersicht anpassen", subtitle: "Karten ordnen und ausblenden, Kennzahlen, Ziele",
                        symbol: "rectangle.3.group.fill", tint: Theme.dawn)
        }
    }
}

struct DashLayoutScreenshotHost: View {
    static let screens: Set<String> = [
        "dashEdit", "dashEditFull", "dashEditSort", "dashEditAX5", "dashKpis", "dashKpisAX5", "dashGoals", "dashQuiet",
        "dashQuietBottom", "dashKpiPicker", "dashGoalEditor", "dashEditSettings", "dashStandardAX5", "dashGoalsAX5", "dashSettingsRow",
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
        case "dashSettingsRow":
            NavigationStack {
                List { SetAppearanceSection() }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(Theme.Spacing.l)
                    .listSectionMargins(.horizontal, Theme.Spacing.cardGutter)
                    .scrollContentBackground(.hidden)
                    .background { SetBackdrop() }
                    .tint(Theme.accent)
                    .navigationTitle("Einstellungen")
                    .navigationBarTitleDisplayMode(.inline)
            }
        case "dashKpisAX5", "dashGoalsAX5":
            // The two cards themselves at the largest text size (the Übersicht's header and summit above them are another story).
            NavigationStack {
                DashEditorSnapshot { snapshot, trips in
                    ScrollView {
                        if let snapshot {
                            VStack(alignment: .leading, spacing: 0) {
                                if screen == "dashKpisAX5" {
                                    DashKpiSection(snapshot: snapshot, trips: trips)
                                } else {
                                    DashGoalsSection(snapshot: snapshot)
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.cardGutter)
                            .padding(.vertical, Theme.Spacing.m)
                        }
                    }
                    .ambientBackground(.standard, glow: 0.4)
                }
                .navigationTitle("Übersicht")
                .navigationBarTitleDisplayMode(.inline)
            }
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
        case "dashGoals", "dashGoalsAX5":
            var layout = DashLayout.standard   // the rings right under the summit for the capture
            layout.move(fromOffsets: IndexSet(integer: layout.order.firstIndex(of: .goals) ?? 0), toOffset: 0)
            store.installDemo(layout: layout, kpis: figures, goals: goals)
        case "dashGoalEditor", "dashStandardAX5":
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
