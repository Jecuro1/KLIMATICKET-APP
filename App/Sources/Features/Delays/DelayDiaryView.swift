import SwiftUI
import SwiftData
import KlimaCore

// MARK: delaydiary – „Verspätungs-Tagebuch“ (docs/DELAY_DIARY.md §3)

/// The diary of one ticket year: the personal on-time share with the AGB caveat, the validity months as bars and as rows
/// that open to their late Fahrten, „Nachtragen“, „Nachweis als PDF“ and the settings. No network, no permission.
struct DelayDiaryView: View {
    /// Ticket year chosen in Statistik (nil = the app-wide active ticket).
    var period: TicketPeriod? = nil
    /// CI screenshots: fixed inputs instead of the stored trips (the empty diary).
    var fixture: [DelayDiaryTrip]? = nil
    /// CI screenshots: the month (index) that starts open.
    var initiallyExpanded: Int? = nil

    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }, sort: \TicketEntity.startDate, order: .reverse)
    private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date)
    private var trips: [TripEntity]

    var body: some View {
        Group {
            if let ticket = WorkCarCalc.ticket(matching: period, in: tickets, selectedID: app.settings.selectedTicketID) {
                DelayDiaryScreen(ticket: ticket, trips: trips, fixture: fixture, initiallyExpanded: initiallyExpanded)
            } else {
                ScrollView {
                    EmptyStateView(symbol: "ticket", title: "Noch kein Ticket",
                                   message: "Lege dein KlimaTicket an – dann führst du hier dein Verspätungs-Tagebuch für das Ticketjahr.",
                                   actionTitle: "Zum Ticket") {
                        app.selectedTab = .ticket
                    }
                    .padding(.top, Theme.Spacing.xxl)
                }
                .navigationTitle(DelayDiaryText.title)
            }
        }
        .ambientBackground(.standard, glow: 0.5)
    }
}

/// The populated screen for one ticket year.
struct DelayDiaryScreen: View {
    let ticket: TicketEntity
    let trips: [TripEntity]
    let fixture: [DelayDiaryTrip]?

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Bindable private var settings = DelayDiarySettings.shared

    @State private var expanded: Set<Int>
    @State private var titleChrome = TktTitleChrome()
    @State private var editing: TripEntity?
    @State private var backfill: DelayBackfillRequest?
    @State private var showsOptions = false
    @State private var showsReport = false
    @State private var toggleTick = 0

    init(ticket: TicketEntity, trips: [TripEntity], fixture: [DelayDiaryTrip]?, initiallyExpanded: Int?) {
        self.ticket = ticket
        self.trips = trips
        self.fixture = fixture
        _expanded = State(initialValue: initiallyExpanded.map { [$0] } ?? [])
    }

    private var year: DelayDiaryYear {
        let now = Date()
        if let fixture {
            return DelayDiaryMemo.year(fixture: fixture, start: ticket.startDate, end: ticket.endDate, now: now, options: settings.options)
        }
        return DelayDiaryMemo.year(trips: trips, start: ticket.startDate, end: ticket.endDate, now: now, options: settings.options)
    }

    var body: some View {
        let year = self.year
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    header
                        .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
                        .reveal(.focus)
                    if year.months.isEmpty {
                        notStartedCard
                            .reveal(order: 1)
                    } else if year.isEmpty {
                        emptyCard(year)
                            .reveal(order: 1)
                    } else {
                        DelayDiaryHeroCard(year: year, onOptions: { showsOptions = true })
                            .reveal(order: 1)
                        DelayMonthChartCard(year: year, selected: expanded) { index in
                            open(index, proxy: proxy)
                        }
                        .reveal(order: 2)
                        .scrollCardTransition()
                    }
                    if !year.months.isEmpty {
                        monthsSection(year)
                    }
                    if !year.isEmpty {
                        reportCard(year)
                            .reveal(order: 5)
                            .scrollCardTransition()
                    }
                    DelayDiaryMethodCard(threshold: year.threshold)
                        .reveal(order: 6)
                        .scrollCardTransition()
                }
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.top, Theme.Spacing.xxs)
                .padding(.bottom, Theme.Spacing.xxl)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .task {
                // CI screenshot „delayDiaryMonth“: the open month in view.
                guard LaunchMode.screenshotScreen == "delayDiaryMonth", let index = expanded.first else { return }
                try? await Task.sleep(for: .milliseconds(450))
                proxy.scrollTo(DelayMonthCard.scrollID(index), anchor: .top)
            }
        }
        .revealScope()
        .scrollIndicators(.hidden)
        .tktInlineTitleTracking(titleChrome)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(DelayDiaryText.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                TktInlineTitle(title: "Verspätungen", chrome: titleChrome)
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarTrailing) {
                Button("Einstellungen", systemImage: "slider.horizontal.3") { showsOptions = true }
                    .accessibilityLabel("Tagebuch einstellen")
            }
        }
        .haptic(.tap, trigger: toggleTick)
        .sheet(item: $editing) { trip in
            DelayEntrySheet(trip: trip)
        }
        .sheet(item: $backfill) { request in
            DelayBackfillSheet(ticket: ticket, request: request)
        }
        .sheet(isPresented: $showsOptions) {
            DelayOptionsSheet()
        }
        .sheet(isPresented: $showsReport) {
            DelayReportSheet(ticket: ticket, year: year)
        }
        .accessibilityIdentifier("delayDiary.screen")
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Kicker(text: "Tagebuch · Ticketjahr \(StatsCalc.ticketYearLabel(ticket.period))")
            Text("Verspätungen")
                .font(Theme.Typography.heroTitle)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
            Text("Dein Tagebuch: welche Fahrten pünktlich waren und welche nicht – so, wie du sie festgehalten hast.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Months

    @ViewBuilder
    private func monthsSection(_ year: DelayDiaryYear) -> some View {
        Text("Monate")
            .font(Theme.Typography.sectionTitle)
            .foregroundStyle(Theme.textPrimary)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
            .padding(.top, Theme.Spacing.s)
            .reveal(order: 3)
        ForEach(year.months.reversed()) { month in
            DelayMonthCard(month: month, threshold: year.threshold, isExpanded: expanded.contains(month.index),
                           onToggle: { toggle(month.index) },
                           onEdit: { edit($0) },
                           onBackfill: { backfill = DelayBackfillRequest(monthIndex: month.index) })
                .id(DelayMonthCard.scrollID(month.index))
                .reveal(order: 4)
        }
    }

    private func toggle(_ index: Int) {
        withMotion(Motion.smooth) {
            if expanded.contains(index) { expanded.remove(index) } else { expanded.insert(index) }
        }
        toggleTick += 1
    }

    private func open(_ index: Int, proxy: ScrollViewProxy) {
        withMotion(Motion.smooth) {
            expanded.insert(index)
            proxy.scrollTo(DelayMonthCard.scrollID(index), anchor: .top)
        }
        toggleTick += 1
    }

    private func edit(_ entry: DelayDiaryEntry) {
        guard fixture == nil else { return }
        editing = Repository(context: context, app: app).liveTrip(id: entry.editTripID)
    }

    // MARK: Empty and not started

    private func emptyCard(_ year: DelayDiaryYear) -> some View {
        GlassCard {
            VStack(spacing: 0) {
                EmptyStateView(symbol: "clock.badge.questionmark", title: "Dein Tagebuch ist leer",
                               message: DelayDiaryText.emptyState,
                               actionTitle: year.notRecordedCount > 0 ? "Letzte Fahrten nachtragen" : nil) {
                    if fixture == nil { backfill = DelayBackfillRequest(monthIndex: nil) }
                }
                if year.tripCount > 0 {
                    Text("\(DelayDiaryText.fahrten(year.tripCount)) in diesem Ticketjahr – noch keine mit Eintrag.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, Theme.Spacing.s)
                }
            }
        }
        .accessibilityIdentifier("delayDiary.empty")
    }

    private var notStartedCard: some View {
        GlassCard {
            EmptyStateView(symbol: "calendar.badge.clock", title: "Dein Ticket startet bald",
                           message: "Ab dem \(Format.date(ticket.startDate, .long)) kannst du hier festhalten, welche Fahrten pünktlich waren.")
        }
    }

    // MARK: Report

    private func reportCard(_ year: DelayDiaryYear) -> some View {
        GlassCard(padding: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(width: 44, height: 44)
                        .background(Theme.accent.opacity(0.14), in: .rect(cornerRadius: Theme.Radius.modeTile, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Kicker(text: "Nachweis")
                        Text("Deine Liste als PDF")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Die verspäteten Fahrten der Monate, die du wählst – mit Datum, Strecke, Zug, Minuten und Herkunft. Für den Fall, dass du bei der Bahn nachfragen willst.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button {
                    showsReport = true
                } label: {
                    Label("Nachweis als PDF", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.primary)
                .accessibilityIdentifier("delayDiary.report")
            }
        }
    }
}

/// „Nachtragen“ for one validity month (nil = the whole ticket year).
struct DelayBackfillRequest: Identifiable, Hashable {
    var monthIndex: Int?
    var id: Int { monthIndex ?? -1 }
}
