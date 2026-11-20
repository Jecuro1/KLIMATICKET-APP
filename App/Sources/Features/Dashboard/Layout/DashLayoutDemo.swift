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
        "dashGoalStates", "dashGoalStatesAX5",   // MARK: review-uebersicht – every goal state at a ticket's edges (synthetic)
        "dashKpisCar",                           // MARK: review-uebersicht – the Bilanz card's car row above the „Auto-Vergleich“ tile
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
        case "dashKpisCar":   // MARK: review-uebersicht – „Mit dem Auto“ on the Bilanz card and the tile say the same euros
            NavigationStack {
                DashEditorSnapshot { snapshot, trips in
                    ScrollView {
                        if let snapshot {
                            VStack(alignment: .leading, spacing: DashStyle.sectionSpacing) {
                                DashBalanceCard(snapshot: snapshot, catalog: app.catalog)
                                DashKpiSection(snapshot: snapshot, trips: trips)
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
        case "dashGoalStates", "dashGoalStatesAX5":   // MARK: review-uebersicht
            NavigationStack {
                ScrollView {
                    DashGoalStatesDemo()
                        .padding(.horizontal, Theme.Spacing.cardGutter)
                        .padding(.vertical, Theme.Spacing.m)
                }
                .ambientBackground(.standard, glow: 0.4)
                .navigationTitle("Ziele")
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
        case "dashKpisCar":   // MARK: review-uebersicht
            store.installDemo(layout: .standard, kpis: [.carComparison, .distance, .totalValue, .tripCount], goals: [])
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

// MARK: review-uebersicht – scene dashGoalStates: the goal rows at a ticket's edges, from fixed synthetic tickets and trips (no store, no
// network): a ticket that started yesterday, one that ended inside the month, one that starts next month, a break-even after the goal's
// day and a forecast after the ticket's end. Each row is what GoalEvaluator says for that case on that day.
struct DashGoalStatesDemo: View {
    private struct Case: Identifiable {
        let id: Int
        let caption: String
        let progress: GoalProgress
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            ForEach(Self.cases()) { item in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(item.caption)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, DashStyle.headerInset)
                    GlassCard(padding: 0) {
                        DashGoalRow(progress: item.progress, isVisible: false)
                            .padding(.horizontal, Theme.Spacing.m)
                            .padding(.vertical, Theme.Spacing.s)
                    }
                }
            }
        }
    }

    private static func cases() -> [Case] {
        let cal = Calendar.vienna
        func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 8) -> Date {
            cal.date(from: DateComponents(year: y, month: m, day: d, hour: h)) ?? Date()
        }
        func ticket(from start: Date) -> TicketPeriod {
            TicketPeriod(productID: "oe-klassik", name: "KlimaTicket Ö Klassik", price: 1_400, start: start,
                         end: TicketPeriod.standardEnd(for: start, calendar: cal))
        }
        func trip(_ date: Date, fare: Double = 12) -> TripRecord {
            TripRecord(date: date, fromName: "Innsbruck Hbf", toName: "Wörgl Hbf", mode: .train, distanceKm: 56, fareEUR: fare)
        }
        func evaluate(_ goal: Goal, _ trips: [TripRecord], _ t: TicketPeriod, now: Date) -> GoalProgress {
            let summary = SavingsCalculator.summary(ticket: t, trips: trips, now: now, calendar: cal)
            return GoalEvaluator.evaluate(goal, trips: trips, ticket: t, summary: summary, now: now, calendar: cal)
        }
        let started = ticket(from: day(2026, 11, 15, 0))
        let ending = ticket(from: day(2025, 11, 26, 0))
        let upcoming = ticket(from: day(2026, 12, 1, 0))
        let running = ticket(from: day(2026, 3, 1, 0))
        let lateTrips = [trip(day(2026, 5, 1), fare: 700), trip(day(2026, 7, 2), fare: 760)]
        let slowTrips = (2...11).map { trip(day(2026, 3, $0), fare: 10) }
        return [
            Case(id: 0, caption: "Ticket seit gestern · 16. Nov.",
                 progress: evaluate(Goal(kind: .tripsPerMonth, target: 20), [trip(day(2026, 11, 15)), trip(day(2026, 11, 15, 18))],
                                    started, now: day(2026, 11, 16, 12))),
            Case(id: 1, caption: "Ticket bis 25. Nov. · 21. Nov.",
                 progress: evaluate(Goal(kind: .valuePerMonth, target: 150), (3...9).map { trip(day(2026, 11, $0)) },
                                    ending, now: day(2026, 11, 21, 12))),
            Case(id: 2, caption: "Ticket bis 25. Nov. · 28. Nov.",
                 progress: evaluate(Goal(kind: .tripsPerMonth, target: 10), (3...6).map { trip(day(2026, 11, $0)) },
                                    ending, now: day(2026, 11, 28, 12))),
            Case(id: 3, caption: "Ticket ab 1. Dez. · 20. Nov.",
                 progress: evaluate(Goal(kind: .co2PerMonth, target: 30), [], upcoming, now: day(2026, 11, 20, 12))),
            Case(id: 4, caption: "Rentiert am 2. Juli · 3. Juli",
                 progress: evaluate(Goal(kind: .breakEvenBy, until: day(2026, 6, 30, 0)), lateTrips, running, now: day(2026, 7, 3, 12))),
            Case(id: 5, caption: "Langsames Tempo · 10. Apr.",
                 progress: evaluate(Goal(kind: .breakEvenBy, until: day(2026, 12, 31, 0)), slowTrips, running, now: day(2026, 4, 10, 12))),
        ]
    }
}
