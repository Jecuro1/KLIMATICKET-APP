import SwiftUI
import SwiftData
import KlimaCore

/// „Zeitbilanz“: how long you were on trains and buses, how long you would have driven the same trips yourself, what
/// recorded delays cost – with honest labels for what was entered, what comes from departure and arrival, and what is
/// estimated (docs/TIME_BALANCE.md). No network: everything is computed on the device from the saved trips.
struct TimeBalanceView: View {
    /// Ticket year chosen in Statistik (nil = the app-wide active ticket).
    var period: TicketPeriod? = nil
    /// CI screenshots: fixed inputs instead of the stored trips (delays, an empty period).
    var fixture: [TimeTripInput]? = nil
    var initialKind: TimeBalancePeriodKind = .ticketYear

    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }, sort: \TicketEntity.startDate, order: .reverse)
    private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date)
    private var trips: [TripEntity]

    var body: some View {
        Group {
            if let ticket = WorkCarCalc.ticket(matching: period, in: tickets, selectedID: app.settings.selectedTicketID) {
                TimeBalanceScreen(ticket: ticket.period, trips: trips, fixture: fixture, initialKind: initialKind)
            } else {
                ScrollView {
                    EmptyStateView(symbol: "ticket", title: "Noch kein Ticket",
                                   message: "Lege dein KlimaTicket an – dann zeigt dir die Zeitbilanz, wie viele Stunden du in Bahn und Bus unterwegs warst.",
                                   actionTitle: "Zum Ticket") {
                        app.selectedTab = .ticket
                    }
                    .padding(.top, Theme.Spacing.xxl)
                }
                .navigationTitle("Zeitbilanz")
            }
        }
        .ambientBackground(.standard, glow: 0.55)
    }
}

/// The populated screen for one ticket year.
struct TimeBalanceScreen: View {
    let ticket: TicketPeriod
    let trips: [TripEntity]
    let fixture: [TimeTripInput]?

    @State private var kind: TimeBalancePeriodKind
    @State private var month: Date?
    @State private var titleChrome = TktTitleChrome()

    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize

    init(ticket: TicketPeriod, trips: [TripEntity], fixture: [TimeTripInput]?, initialKind: TimeBalancePeriodKind) {
        self.ticket = ticket
        self.trips = trips
        self.fixture = fixture
        _kind = State(initialValue: initialKind)
        _month = State(initialValue: TimeBalancePeriods.defaultMonth(of: ticket, now: Date()))
    }

    var body: some View {
        let now = Date()
        let profile = WorkSettings.shared.carProfile(catalog: app.catalog)
        let range = TimeBalancePeriods.range(of: ticket, kind: kind, month: month)
        let balance = fixture.map { TimeBalanceMemo.balance(inputs: $0, range: range, now: now, profile: profile) }
            ?? TimeBalanceMemo.balance(trips: trips, range: range, now: now, profile: profile)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                header
                    .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
                    .reveal(.focus)
                periodPicker
                    .reveal(order: 1)
                if balance.isEmpty {
                    emptyCard
                        .reveal(order: 2)
                } else {
                    TimeBalanceHeroCard(balance: balance, periodTitle: periodTitle)
                        .reveal(order: 2)
                    TimeBalanceCarCard(balance: balance)
                        .reveal(order: 3)
                        .scrollCardTransition()
                    if let delays = balance.delays {
                        TimeBalanceDelayCard(delays: delays, tripCount: balance.tripCount)
                            .reveal(order: 4)
                            .scrollCardTransition()
                            .motionTransition(.rise)
                    }
                    TimeBalanceWeekChartCard(balance: balance)
                        .reveal(order: 5)
                        .scrollCardTransition()
                    TimeBalanceFactsRow(balance: balance)
                        .reveal(order: 6)
                        .scrollCardTransition()
                    if balance.modes.count > 0 {
                        TimeBalanceModesCard(balance: balance)
                            .reveal(order: 7)
                            .scrollCardTransition()
                    }
                }
                TimeBalanceMethodCard(roadFactor: profile.roadDistanceFactor)
                    .reveal(order: 8)
                    .scrollCardTransition()
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .padding(.top, Theme.Spacing.xxs)
            .padding(.bottom, Theme.Spacing.xxl)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .motionAnimation(Motion.smooth, value: balance.delays == nil)
        }
        .revealScope()
        .scrollIndicators(.hidden)
        .tktInlineTitleTracking(titleChrome)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("Zeitbilanz")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                TktInlineTitle(title: "Zeitbilanz", chrome: titleChrome)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .accessibilityIdentifier("timeBalance.screen")
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Kicker(text: "Ticketjahr \(StatsCalc.ticketYearLabel(ticket))")
            Text("Zeitbilanz")
                .font(Theme.Typography.heroTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Deine Stunden in Bahn und Bus – und wie lange du mit dem Auto selbst gefahren wärst.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var periodTitle: String {
        switch kind {
        case .ticketYear: "Ticketjahr \(StatsCalc.ticketYearLabel(ticket))"
        case .month: month.map(TimeBalancePeriods.monthTitle) ?? "Monat"
        }
    }

    // MARK: Period

    private var months: [Date] { TimeBalancePeriods.months(of: ticket, now: Date()) }

    @ViewBuilder
    private var periodPicker: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if typeSize.isAccessibilitySize {
                WhatIfStackedChoice(selection: kindBinding, options: TimeBalancePeriodKind.allCases) { $0.title }
            } else {
                GlassSegmentedPicker(selection: kindBinding, options: TimeBalancePeriodKind.allCases) { Text($0.title) }
                    .accessibilityLabel("Zeitraum")
            }
            if kind == .month, let month {
                TimeBalanceMonthStepper(month: month, months: months) { picked in
                    withMotion(Motion.smooth) { self.month = picked }
                }
                .motionTransition(.rise)
            }
        }
    }

    private var kindBinding: Binding<TimeBalancePeriodKind> {
        Binding(get: { kind }, set: { new in
            withMotion(Motion.smooth) { kind = new }
        })
    }

    // MARK: Empty

    private var emptyCard: some View {
        GlassCard {
            EmptyStateView(symbol: "clock.badge.questionmark", title: "Noch keine Fahrten",
                           message: kind == .month
                               ? "In \(periodTitle) hast du noch keine Fahrt erfasst. Sobald du fährst, siehst du hier deine Stunden in Bahn und Bus."
                               : "Sobald du Fahrten erfasst, siehst du hier deine Stunden in Bahn und Bus – und wie lange das Auto gebraucht hätte.",
                           actionTitle: "Fahrt erfassen") {
                app.presentAddTrip()
            }
        }
        .accessibilityIdentifier("timeBalance.empty")
    }
}

/// „‹ November 2026 ›“ – steps through the months of the ticket year (none after today).
struct TimeBalanceMonthStepper: View {
    let month: Date
    let months: [Date]
    let onPick: (Date) -> Void

    private var index: Int? { months.firstIndex(of: month) }

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            stepButton(symbol: "chevron.left", label: "Voriger Monat", target: index.flatMap { $0 > 0 ? months[$0 - 1] : nil })
            Text(TimeBalancePeriods.monthTitle(month))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            stepButton(symbol: "chevron.right", label: "Nächster Monat",
                       target: index.flatMap { $0 + 1 < months.count ? months[$0 + 1] : nil })
        }
        .padding(.horizontal, Theme.Spacing.xxs)
        .haptic(.selection, trigger: month)
        // One adjustable element for VoiceOver: swipe up / down steps through the months.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Monat")
        .accessibilityValue(TimeBalancePeriods.monthTitle(month))
        .accessibilityHint("Wische nach oben oder unten, um den Monat zu wechseln")
        .accessibilityIdentifier("timeBalance.month")
        .accessibilityAdjustableAction { direction in
            guard let index else { return }
            switch direction {
            case .increment: if index + 1 < months.count { onPick(months[index + 1]) }
            case .decrement: if index > 0 { onPick(months[index - 1]) }
            @unknown default: break
            }
        }
    }

    private func stepButton(symbol: String, label: String, target: Date?) -> some View {
        Button {
            if let target { onPick(target) }
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .foregroundStyle(target == nil ? Theme.textTertiary : Theme.textPrimary)
        .glassEffect(.regular.interactive(), in: .circle)
        .disabled(target == nil)
        .accessibilityLabel(label)
    }
}

/// „So rechnen wir“ – where every minute comes from, in plain words.
struct TimeBalanceMethodCard: View {
    let roadFactor: Double

    var body: some View {
        GlassCard(padding: Theme.Spacing.m + 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                StatsCardHeader(kicker: "So rechnen wir", title: "Was erfasst ist – und was geschätzt") { EmptyView() }
                row(symbol: "pencil", tint: Theme.glacier, title: "Eingetragen",
                    text: "Die Dauer, die du bei einer Fahrt angibst (Fahrt bearbeiten › Dauer).")
                row(symbol: "clock", tint: Theme.dusk, title: "Abfahrt & Ankunft",
                    text: "Verbindungen aus dem Fahrplan mit ihren planmäßigen Zeiten (Umstiege inklusive) und aufgezeichnete Fahrten.")
                row(symbol: "wand.and.stars", tint: Theme.dawn, title: "Geschätzt",
                    text: "Alle anderen Fahrten: grobes Durchschnittstempo je Verkehrsmittel und Strecke, Halte inklusive – etwa Zug 70 km/h auf 60 km, Bus 28 km/h auf 15 km. Keine genauen Fahrzeiten.")
                row(symbol: "car", tint: Theme.remaining, title: "Auto",
                    text: "Dieselben Strecken × \(Format.number(roadFactor, decimals: 2)) auf der Straße, mit Durchschnittstempo ohne Stau und Parkplatzsuche – derselbe Wert wie im Auto-Vergleich.")
                Text("Hin und zurück zählt doppelt. Der Weg zur Haltestelle und das Warten am Bahnsteig sind nicht dabei. Verspätungen zählen nur, wo sie erfasst sind, und stehen extra.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(symbol: String, tint: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
