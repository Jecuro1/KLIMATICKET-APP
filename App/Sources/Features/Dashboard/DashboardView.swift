import SwiftUI
import SwiftData
import KlimaCore

/// Tab 1 „Übersicht“ – answers „Hat sich mein Ticket schon rentiert?“ at a glance (DESIGN.md §5.1).
///
/// Top → bottom (mock 01): own header (ticket eyebrow + large title + avatar, no navigation bar), the `AmortizationHero`,
/// the Bilanz card, "Schnell erfassen", trip suggestions, recent trips, next achievement and "Diese Woche".
/// Presents Settings and the Gipfelbuch as sheets and the break-even celebration once per ticket.
struct DashboardView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date, order: .reverse)
    private var trips: [TripEntity]
    @Query(filter: #Predicate<FavoriteRouteEntity> { $0.deletedAt == nil }, sort: \FavoriteRouteEntity.sortIndex)
    private var favorites: [FavoriteRouteEntity]

    /// Drives the staggered entrance; already true in screenshot mode (end state immediately).
    @State private var appeared = LaunchMode.isScreenshot
    /// The header has scrolled away – shows the frosted fade under the status bar.
    @State private var isScrolled = false
    @State private var celebration: DashCelebrationInfo?
    @Namespace private var tripZoom

    var body: some View {
        let ticket = Analytics.activeTicket(in: tickets, selectedID: app.settings.selectedTicketID)
        let snapshot = ticket.map { Analytics.make(ticket: $0, trips: trips, catalog: app.catalog) }

        NavigationStack {
            Group {
                if let ticket, let snapshot {
                    dashboard(ticket: ticket, snapshot: snapshot)
                } else {
                    noTicket
                }
            }
            // Title kept for the back button of pushed trip details; the bar itself is replaced by `DashHeader`.
            .navigationTitle(AppTab.overview.title)
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: settingsBinding) {
            NavigationStack { SettingsView() }
        }
        .sheet(isPresented: achievementsBinding) {
            NavigationStack { AchievementsView() }
        }
        .overlay { celebrationOverlay }
        .onAppear {
            if !appeared { appeared = true }
        }
        .onChange(of: celebrationKey(ticket: ticket, snapshot: snapshot), initial: true) { _, _ in
            evaluateCelebration(ticket: ticket, snapshot: snapshot)
        }
    }

    // MARK: Content

    private func dashboard(ticket: TicketEntity, snapshot: AnalyticsSnapshot) -> some View {
        let summary = snapshot.summary
        let hasTrips = summary.tripCount > 0
        let suggestions = app.detection.suggestions
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topSection(ticket: ticket, snapshot: snapshot)

                if hasTrips {
                    // Overlaps the faded valley of the summit chart by a few points (spec §8.1); the route starts above it.
                    DashBalanceCard(snapshot: snapshot, kilometergeld: app.catalog.kilometergeldEUR)
                        .padding(.horizontal, Theme.Spacing.cardGutter)
                        .padding(.top, -Theme.Spacing.xs)
                        .dashEntrance(2, visible: appeared)
                } else {
                    DashEmptyInviteCard(hasFavorites: !favorites.isEmpty) { app.presentAddTrip() }
                        .padding(.horizontal, Theme.Spacing.cardGutter)
                        .padding(.top, Theme.Spacing.xs)
                        .dashEntrance(2, visible: appeared)
                }

                if hasTrips || !favorites.isEmpty {
                    // No second "Neue Fahrt" button – the "+" tab does that (DESIGN.md §5.1 · 5).
                    DashQuickLogSection(favorites: favorites, summary: summary, ticketIsCurrent: ticket.isActive,
                                        showsNewTripButton: false)
                        // The chip row carries 8 pt of vertical breathing room for glass and shadows → 10 pt below the card.
                        .padding(.top, 2)
                        .padding(.bottom, -Theme.Spacing.xs)
                        .dashEntrance(3, visible: appeared)
                }

                if !suggestions.isEmpty {
                    DashSuggestionsSection(suggestions: suggestions)
                        .padding(.horizontal, Theme.Spacing.cardGutter)
                        .padding(.top, DashStyle.sectionSpacing)
                        .dashEntrance(4, visible: appeared)
                }

                if !trips.isEmpty {
                    DashRecentTripsSection(trips: Array(trips.prefix(5)), namespace: tripZoom)
                        .padding(.horizontal, Theme.Spacing.cardGutter)
                        .padding(.top, suggestions.isEmpty ? Theme.Spacing.m : DashStyle.sectionSpacing)
                        .dashEntrance(5, visible: appeared)
                }

                if hasTrips {
                    insights(snapshot: snapshot)
                        .padding(.horizontal, Theme.Spacing.cardGutter)
                        .padding(.top, DashStyle.sectionSpacing)
                }

                // MARK: benefits
                PerkSummaryCard()
                    .padding(.horizontal, Theme.Spacing.cardGutter)
                    .padding(.top, hasTrips ? DashStyle.cardSpacing : DashStyle.sectionSpacing)
                    .dashEntrance(8, visible: appeared)
            }
            .padding(.bottom, Theme.Spacing.xl)
            .animation(.smooth, value: suggestions.count)
        }
        .onScrollGeometryChange(for: Bool.self, of: { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 6
        }, action: { _, scrolled in
            withAnimation(.easeInOut(duration: 0.2)) { isScrolled = scrolled }
        })
        .overlay(alignment: .top) {
            DashTopScrim()
                .opacity(isScrolled ? 1 : 0)
        }
        // The sun glow brightens towards the summit, capped so the verdict lines above it keep their contrast.
        .ambientBackground(.standard, glow: 0.4 + 0.4 * summary.progressClamped)
        .refreshable { await refresh() }
    }

    @ViewBuilder
    private func topSection(ticket: TicketEntity, snapshot: AnalyticsSnapshot) -> some View {
        let eyebrow = ticketEyebrow(ticket, summary: snapshot.summary)
        header(eyebrow: eyebrow.full, compact: eyebrow.compact, ticket: ticket) {
            app.selectedTab = .ticket
        }
        .dashEntrance(0, visible: appeared)

        if let manifest = app.updates.availableManifest, !LaunchMode.isScreenshot {
            DashUpdateCapsule(version: manifest.version.description) {
                app.updates.isPresentingSheet = true
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, Theme.Spacing.xs)
            .dashEntrance(0, visible: appeared)
        }

        // Spec §8.1: mountain canvas 134 pt, full width.
        AmortizationHero(snapshot: snapshot, chartHeight: 134)
            .padding(.top, Theme.Spacing.xxs)
            .dashEntrance(1, visible: appeared)
    }

    private func header(eyebrow: String, compact: String?, ticket: TicketEntity?,
                        onEyebrow: (() -> Void)? = nil) -> some View {
        DashHeader(eyebrow: eyebrow, compactEyebrow: compact, onEyebrow: onEyebrow,
                   avatarInitials: avatarInitials(ticket: ticket),
                   isSignedIn: app.auth.profile != nil,
                   hasUpdate: app.updates.availableManifest != nil && !LaunchMode.isScreenshot) {
            app.isShowingSettings = true
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.top, Theme.Spacing.xxs)
    }

    @ViewBuilder
    private func insights(snapshot: AnalyticsSnapshot) -> some View {
        VStack(spacing: DashStyle.cardSpacing) {
            DashAchievementTeaser(next: snapshot.nextAchievement,
                                  unlockedCount: snapshot.unlockedAchievements.count,
                                  totalCount: snapshot.achievements.count) {
                app.isShowingAchievements = true
            }
            .dashEntrance(6, visible: appeared)

            DashWeekInsightCard(stats: DashWeekStats.make(from: trips))
                .dashEntrance(7, visible: appeared)
        }
    }

    /// Fallback – RootView normally shows onboarding when there is no ticket.
    private var noTicket: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                header(eyebrow: DashStyle.longDate(Date()), compact: nil, ticket: nil)
                EmptyStateView(symbol: "ticket",
                               title: "Noch kein Ticket",
                               message: "Lege dein KlimaTicket an – dann siehst du, ab wann es sich rentiert.",
                               actionTitle: "Ticket anlegen") {
                    app.selectedTab = .ticket
                }
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.top, Theme.Spacing.xxl)
            }
        }
        .ambientBackground(.standard, glow: 0.4)
    }

    // MARK: Sheets

    /// Only the visible tab presents the shared sheets (other tabs may bind to the same flags).
    private var settingsBinding: Binding<Bool> {
        Binding(get: { app.isShowingSettings && app.selectedTab == .overview },
                set: { app.isShowingSettings = $0 })
    }

    private var achievementsBinding: Binding<Bool> {
        Binding(get: { app.isShowingAchievements && app.selectedTab == .overview },
                set: { app.isShowingAchievements = $0 })
    }

    // MARK: Break-even celebration

    @ViewBuilder
    private var celebrationOverlay: some View {
        if let info = celebration {
            BreakEvenCelebration(ticketName: info.ticketName, profit: info.profit) {
                withAnimation(.smooth(duration: 0.35)) { celebration = nil }
            }
            .transition(.opacity)
            .zIndex(1)
        }
    }

    /// True while a sheet covers the dashboard (Settings, Gipfelbuch, add/edit trip, update). The celebration waits
    /// until it is gone – otherwise confetti and haptics would play unseen and the ticket would still count as celebrated.
    private var isCoveredBySheet: Bool {
        app.isShowingSettings || app.isShowingAchievements || app.tripDraft != nil || app.updates.isPresentingSheet
    }

    private func celebrationKey(ticket: TicketEntity?, snapshot: AnalyticsSnapshot?) -> String {
        guard let ticket, let snapshot else { return "none" }
        let visible = app.selectedTab == .overview && !isCoveredBySheet
        return "\(ticket.id.uuidString)|\(snapshot.summary.isPaidOff)|\(visible)|\(app.celebrateBreakEven)"
    }

    /// Shows the celebration once per ticket (ids in `celebratedBreakEvenTicketIDs`), only while this tab is visible
    /// and uncovered. Also consumes `app.celebrateBreakEven`.
    private func evaluateCelebration(ticket: TicketEntity?, snapshot: AnalyticsSnapshot?) {
        guard !LaunchMode.isScreenshot, celebration == nil, app.selectedTab == .overview, !isCoveredBySheet,
              let ticket, let snapshot, snapshot.summary.isPaidOff, snapshot.summary.tripCount > 0 else { return }
        if app.celebrateBreakEven { app.celebrateBreakEven = false }
        let id = ticket.id.uuidString
        guard !app.settings.celebratedBreakEvenTicketIDs.contains(id) else { return }
        app.settings.celebratedBreakEvenTicketIDs.append(id)
        let info = DashCelebrationInfo(ticketName: ticket.name, profit: snapshot.summary.net)
        withAnimation(.smooth(duration: 0.4)) { celebration = info }
    }

    // MARK: Helpers

    private func refresh() async {
        await app.sync.sync(context: context, auth: app.auth)
        if case .failed(let message) = app.sync.state {
            app.showToast("exclamationmark.icloud.fill", "Synchronisierung fehlgeschlagen", message)
        }
    }

    private func ticketStatus(_ ticket: TicketEntity, summary: SavingsSummary) -> String {
        let now = Date()
        if now < ticket.startDate { return "ab " + Format.dayMonth(ticket.startDate) }
        if now > ticket.endDate { return "abgelaufen" }
        return summary.daysRemaining == 0 ? "letzter Tag" : "noch " + Format.days(summary.daysRemaining)
    }

    /// "KlimaTicket Ö Klassik · noch 142 Tage", compact "Klassik · noch 142 Tage".
    private func ticketEyebrow(_ ticket: TicketEntity, summary: SavingsSummary) -> (full: String, compact: String) {
        let status = ticketStatus(ticket, summary: summary)
        var short = ticket.name
        for prefix in ["KlimaTicket Ö ", "KlimaTicket "] where short.hasPrefix(prefix) {
            short = String(short.dropFirst(prefix.count))
            break
        }
        let compact = short == ticket.name || short.isEmpty ? status : short + " · " + status
        return (ticket.name + " · " + status, compact)
    }

    /// Same identity as Einstellungen: the signed-in profile (demo profile in CI screenshots), else the ticket holder.
    private func avatarInitials(ticket: TicketEntity?) -> String? {
        let holder = ticket?.holderName ?? ""
        if let profile = app.auth.profile ?? (LaunchMode.isScreenshot ? SetDemo.profile : nil) {
            if let initials = DashAvatarButton.initials(from: profile.displayName) { return initials }
            if let initials = DashAvatarButton.initials(from: holder) { return initials }
            if let first = profile.email?.first { return String(first).uppercased() }
            return nil
        }
        return DashAvatarButton.initials(from: holder)
    }
}

/// Payload of the break-even overlay.
struct DashCelebrationInfo: Equatable {
    var ticketName: String
    var profit: Double
}
