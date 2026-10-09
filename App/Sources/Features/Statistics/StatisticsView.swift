import SwiftUI
import SwiftData
import KlimaCore

/// Tab 3 – "Statistik": insights for the selected ticket year (DESIGN.md §5.4).
struct StatisticsView: View {
    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }, sort: \TicketEntity.startDate, order: .reverse)
    private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date)
    private var trips: [TripEntity]

    /// Local ticket-year choice (nil = the app-wide active ticket).
    @State private var pickedTicketID: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if let ticket = Analytics.activeTicket(in: tickets, selectedID: pickedTicketID ?? app.settings.selectedTicketID) {
                    StatsScreen(ticket: ticket,
                                snapshot: Analytics.make(ticket: ticket, trips: trips, catalog: app.catalog),
                                tickets: tickets,
                                selection: $pickedTicketID)
                } else {
                    noTicket
                }
            }
            .ambientBackground()
        }
        // Cards zoom into the screens and sheets they open (Karte, Öffis vs. Auto, Gipfelbuch).
        .zoomTransitionScope()
    }

    private var noTicket: some View {
        ScrollView {
            EmptyStateView(symbol: "ticket", title: "Noch kein Ticket",
                           message: "Lege dein KlimaTicket an – dann siehst du hier, wie es sich Monat für Monat rentiert.",
                           actionTitle: "Zum Ticket") {
                app.selectedTab = .ticket
            }
            .padding(.top, Theme.Spacing.xxl)
        }
        .navigationTitle("Statistik")
    }
}

/// The populated statistics screen for one ticket period.
struct StatsScreen: View {
    let ticket: TicketEntity
    let snapshot: AnalyticsSnapshot
    let tickets: [TicketEntity]
    @Binding var selection: UUID?

    @Environment(AppState.self) private var app
    /// How far the large header has condensed (0 … 1). Only the header and the inline title read it, so scrolling
    /// never re-runs this body (and every card's).
    @State private var condense = ScrollCondense()
    // MARK: reports
    @State private var isShowingReport = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                StatsScreenHeader(ticketYear: StatsCalc.ticketYearLabel(snapshot.ticket), subtitle: subtitle, condense: condense)
                    .padding(.bottom, Theme.Spacing.xxs)
                    .reveal(.focus)
                if snapshot.trips.isEmpty {
                    emptyTrips
                        .reveal(order: 1)
                } else {
                    primarySections
                    secondarySections
                }
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .padding(.top, Theme.Spacing.xxs)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .accessibilityIdentifier("perf.scroll.stats") // MARK: perf – KlimaBilanzPerfTests
        .scrollIndicators(.hidden)
        .tracksScrollCondense(condense, distance: 72)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .revealScope()
        .navigationTitle("Statistik")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .haptic(.selection, trigger: ticket.id)
        // MARK: reports
        .sheet(isPresented: $isShowingReport) { RepReportSheet(ticketID: ticket.id) }
    }

    // MARK: Header

    private var subtitle: String {
        let summary = snapshot.summary
        if StatsCalc.isRunning(snapshot.ticket) {
            return "\(ticket.name) · Tag \(summary.daysElapsed) von \(summary.daysTotal)"
        }
        if Date() < snapshot.ticket.start {
            return "\(ticket.name) · startet am \(Format.date(snapshot.ticket.start))"
        }
        return "\(ticket.name) · abgelaufen am \(Format.date(snapshot.ticket.end))"
    }

    // MARK: Sections

    /// Cards in reading order: each one rises in once (staggered), settles in as it scrolls up from the bottom edge,
    /// and its charts grow when it first comes into view.
    @ViewBuilder
    private var primarySections: some View {
        StatsGrowOnView(delay: Motion.Stagger.delay(1)) { StatsSavingsCard(snapshot: snapshot, grow: $0) }
            .statsCard(order: 1)
        StatsGrowOnView(delay: Motion.Stagger.delay(2)) { StatsMonthlyCard(snapshot: snapshot, grow: $0) }
            .statsCard(order: 2)
        StatsGrowOnView(delay: Motion.Stagger.delay(3)) { StatsModesCard(snapshot: snapshot, grow: $0) }
            .statsCard(order: 3)
        // MARK: tripmeta – "Wofür du fährst" and "Ehrliche Bilanz"
        StatsGrowOnView(delay: Motion.Stagger.delay(4)) { MetaPurposeCard(snapshot: snapshot, grow: $0) }
            .statsCard(order: 4)
        StatsGrowOnView(delay: Motion.Stagger.delay(5)) { MetaHonestBalanceCard(snapshot: snapshot, grow: $0) }
            .statsCard(order: 5)
        StatsCalendarCard(snapshot: snapshot)
            .statsCard(order: 6)
        StatsGrowOnView(delay: Motion.Stagger.delay(7)) { StatsWeekdayCard(snapshot: snapshot, grow: $0) }
            .statsCard(order: 7)
    }

    @ViewBuilder
    private var secondarySections: some View {
        if !snapshot.topRoutes.isEmpty {
            StatsGrowOnView(delay: Motion.Stagger.delay(8)) { StatsTopRoutesCard(snapshot: snapshot, grow: $0) }
                .statsCard(order: 8)
        }
        // MARK: map
        AtlasPreviewCard(snapshot: snapshot, ticketID: ticket.id)
            .statsCard(order: 8)
        StatsRecordsSection(snapshot: snapshot)
            .padding(.top, Theme.Spacing.s)
            .reveal(order: 8)
        StatsStatesCard(snapshot: snapshot)
            .statsCard(order: 8)
        // The Gipfelbuch sheet always shows the app-wide ticket – only offer it (with its counts) for that ticket,
        // otherwise the row's "6/17" would contradict the sheet it opens.
        if showsSummitBook {
            StatsSummitBookRow(snapshot: snapshot)
                .statsCard(order: 8)
        }
        StatsGrowOnView { StatsTicketComparisonCard(snapshot: snapshot, products: app.catalog.products, variant: ticket.variant, grow: $0) }
            .padding(.top, Theme.Spacing.s)
            .statsCard(order: 8)
        StatsGrowOnView { StatsCarCO2Section(snapshot: snapshot, kilometergeld: app.catalog.kilometergeldEUR, grow: $0) }
            .reveal(order: 8)
        StatsEffectiveCostsSection(snapshot: snapshot)
            .padding(.top, Theme.Spacing.s)
            .reveal(order: 8)
    }

    private var showsSummitBook: Bool {
        Analytics.activeTicket(in: tickets, selectedID: app.settings.selectedTicketID)?.id == ticket.id
    }

    private var emptyTrips: some View {
        GlassCard {
            EmptyStateView(symbol: "chart.line.uptrend.xyaxis", title: "Noch keine Fahrten",
                           message: "Sobald du Fahrten erfasst, siehst du hier deinen Ersparnis-Verlauf, deine Monatsbilanz und deine Rekorde.",
                           actionTitle: "Erste Fahrt erfassen") {
                app.presentAddTrip()
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            StatsInlineTitle(title: "Statistik", condense: condense)
        }
        // iOS 26 wraps custom toolbar views in a shared glass capsule – it would stay visible as an
        // empty pill while the title is faded out (same as the dashboard).
        .sharedBackgroundVisibility(.hidden)
        ToolbarItemGroup(placement: .topBarTrailing) {
            if tickets.count > 1 {
                ticketMenu
            }
            shareButton
        }
    }

    private var ticketMenu: some View {
        Menu {
            Picker("Ticketjahr", selection: pickerBinding) {
                ForEach(tickets) { item in
                    Text(menuTitle(for: item)).tag(Optional(item.id))
                }
            }
        } label: {
            Label("Ticketjahr wählen", systemImage: "calendar")
        }
        .accessibilityLabel("Ticketjahr wählen")
        .accessibilityValue(menuTitle(for: ticket))
    }

    private var pickerBinding: Binding<UUID?> {
        Binding(get: { ticket.id }, set: { selection = $0 })
    }

    private func menuTitle(for item: TicketEntity) -> String {
        "\(StatsCalc.ticketYearLabel(item.period)) · \(item.name)"
    }

    // MARK: reports – share menu: image card + "Jahresbericht als PDF"
    private var shareButton: some View {
        // The card image is rendered by the share sheet when it exports (and for its preview) – not up front.
        let payload = StatsSharePayload(snapshot: snapshot, ticketName: ticket.name)
        return Menu {
            ShareLink(item: payload, preview: SharePreview("Meine KlimaBilanz", image: payload)) {
                Label("Bilanz als Bild teilen", systemImage: "photo")
            }
            RepReportMenuButton { isShowingReport = true }
        } label: {
            Label("Teilen", systemImage: "square.and.arrow.up")
        }
        .accessibilityLabel("Teilen")
    }
}

/// "Ticketjahr 2026/27 · Statistik · KlimaTicket Ö · Tag 210 von 365" – condenses as the screen scrolls (only this
/// view reads the scroll progress).
private struct StatsScreenHeader: View {
    let ticketYear: String
    let subtitle: String
    let condense: ScrollCondense

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Kicker(text: "Ticketjahr \(ticketYear)")
            Text("Statistik")
                .font(Theme.Typography.heroTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .statsHeaderCondense(condense)
    }
}

private extension View {
    /// A statistics card: rises in once with the screen's staggered entrance and settles in as it scrolls up from the
    /// bottom edge (docs/MOTION.md §4, §10).
    func statsCard(order: Int) -> some View {
        reveal(order: order).scrollCardTransition()
    }
}
