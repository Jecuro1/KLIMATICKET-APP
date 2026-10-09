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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Already in the end state in screenshot mode (no empty first frame).
    @State private var grow: Double = LaunchMode.isScreenshot ? 1 : 0
    /// Inline-title state in a reference: only the toolbar title reads it, so crossing the scroll threshold
    /// doesn't re-run this body (and every card's) mid-scroll.
    @State private var chrome = StatsChromeState()
    // MARK: reports
    @State private var isShowingReport = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                header
                    .padding(.bottom, Theme.Spacing.xxs)
                if snapshot.trips.isEmpty {
                    emptyTrips
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
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 64
        } action: { _, isScrolled in
            withAnimation(.easeInOut(duration: 0.2)) { chrome.showsInlineTitle = isScrolled }
        }
        .navigationTitle("Statistik")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sensoryFeedback(.selection, trigger: ticket.id) { _, _ in app.settings.hapticsEnabled }
        .onAppear { startEntrance() }
        // MARK: reports
        .sheet(isPresented: $isShowingReport) { RepReportSheet(ticketID: ticket.id) }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Kicker(text: "Ticketjahr \(StatsCalc.ticketYearLabel(snapshot.ticket))")
            Text("Statistik")
                .font(Theme.Typography.heroTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
        }
        .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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

    @ViewBuilder
    private var primarySections: some View {
        StatsSavingsCard(snapshot: snapshot, grow: grow)
            .statsEntrance(0)
        StatsMonthlyCard(snapshot: snapshot, grow: grow)
            .statsEntrance(1)
        StatsModesCard(snapshot: snapshot, grow: grow)
            .statsEntrance(2)
        // MARK: tripmeta – "Wofür du fährst" and "Ehrliche Bilanz"
        MetaPurposeCard(snapshot: snapshot, grow: grow)
            .statsEntrance(3)
        MetaHonestBalanceCard(snapshot: snapshot, grow: grow)
            .statsEntrance(3)
        StatsCalendarCard(snapshot: snapshot)
            .statsEntrance(3)
        StatsWeekdayCard(snapshot: snapshot, grow: grow)
            .statsEntrance(4)
    }

    @ViewBuilder
    private var secondarySections: some View {
        if !snapshot.topRoutes.isEmpty {
            StatsTopRoutesCard(snapshot: snapshot, grow: grow)
                .statsEntrance(5)
        }
        // MARK: map
        AtlasPreviewCard(snapshot: snapshot, ticketID: ticket.id)
        StatsRecordsSection(snapshot: snapshot)
            .padding(.top, Theme.Spacing.s)
        StatsStatesCard(snapshot: snapshot)
        // The Gipfelbuch sheet always shows the app-wide ticket – only offer it (with its counts) for that ticket,
        // otherwise the row's "6/17" would contradict the sheet it opens.
        if showsSummitBook {
            StatsSummitBookRow(snapshot: snapshot)
        }
        StatsTicketComparisonCard(snapshot: snapshot, products: app.catalog.products, variant: ticket.variant, grow: grow)
            .padding(.top, Theme.Spacing.s)
        StatsCarCO2Section(snapshot: snapshot, kilometergeld: app.catalog.kilometergeldEUR, grow: grow)
        StatsEffectiveCostsSection(snapshot: snapshot)
            .padding(.top, Theme.Spacing.s)
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
            StatsInlineTitle(chrome: chrome)
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

    // MARK: Motion

    private func startEntrance() {
        guard grow < 1 else { return }
        if reduceMotion || LaunchMode.isScreenshot {
            grow = 1
        } else {
            withAnimation(.smooth(duration: 0.9).delay(0.12)) { grow = 1 }
        }
    }
}

/// Scroll-driven chrome of the Statistik screen.
@Observable
@MainActor
final class StatsChromeState {
    var showsInlineTitle = false
}

/// The inline navigation title, faded in once the large header has scrolled away.
private struct StatsInlineTitle: View {
    let chrome: StatsChromeState

    var body: some View {
        Text("Statistik")
            .font(.headline)
            .foregroundStyle(Theme.textPrimary)
            .opacity(chrome.showsInlineTitle ? 1 : 0)
            .accessibilityHidden(!chrome.showsInlineTitle)
    }
}
