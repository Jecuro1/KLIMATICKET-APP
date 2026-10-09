import SwiftUI
import SwiftData
import KlimaCore

/// Tab 1 „Übersicht“ – answers „Hat sich mein Ticket schon rentiert?“ at a glance (DESIGN.md §5.1).
///
/// Top → bottom (mock 01): own header (ticket eyebrow + large title + avatar, no navigation bar), the `AmortizationHero`,
/// the Bilanz card, "Schnell erfassen", trip suggestions, recent trips, next achievement and "Diese Woche".
/// Presents Settings and the Gipfelbuch as sheets and the break-even celebration once per ticket.
///
/// The body depends on the data only (@Query results, the selected ticket, the catalog, trip suggestions). Everything that
/// changes while the data does not – the scroll position (`DashScrollScrim`), account and update state
/// (`DashAccountHeader`, `DashUpdateCapsuleHost`), the selected tab and the open sheets (`DashPresentation`) – is read
/// by small child views and modifiers, so a tab switch, a sheet or scrolling past the header never re-runs this body.
///
/// Motion (docs/MOTION.md): the sections rise in once in reading order (`reveal`), the 75 % counts up together with the
/// climber on the summit chart, every figure rolls when it changes, the hero condenses while scrolling and a glass pill
/// with the percentage takes its place under the status bar (tap → back to the top). Trips zoom into their detail,
/// the Gipfelbuch and Einstellungen zoom out of the card / avatar that opened them.
struct DashboardView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date, order: .reverse)
    private var trips: [TripEntity]
    @Query(filter: #Predicate<FavoriteRouteEntity> { $0.deletedAt == nil }, sort: \FavoriteRouteEntity.sortIndex)
    private var favorites: [FavoriteRouteEntity]

    /// Scroll progress of the hero (0 at rest … 1 condensed). Only `heroCondense` and `DashCondensedSummit` read it.
    @State private var condense = ScrollCondense()

    /// CI screenshot "dashboardBottom" opens scrolled to the end (Gipfelbuch, „Diese Woche“, Vorteile).
    private static let screenshotAnchor: UnitPoint? = LaunchMode.screenshotScreen == "dashboardBottom" ? .bottom : nil

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
        .modifier(DashPresentation(ticketID: ticket?.id, ticketName: ticket?.name ?? "",
                                   isPaidOff: snapshot?.summary.isPaidOff ?? false,
                                   hasTrips: (snapshot?.summary.tripCount ?? 0) > 0,
                                   profit: snapshot?.summary.net ?? 0))
        // One namespace for the pushed trip details and the two sheets (Gipfelbuch, Einstellungen).
        .zoomTransitionScope()
    }

    // MARK: Content

    private func dashboard(ticket: TicketEntity, snapshot: AnalyticsSnapshot) -> some View {
        let summary = snapshot.summary
        let hasTrips = summary.tripCount > 0
        let suggestions = app.detection.suggestions
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topSection(ticket: ticket, snapshot: snapshot)

                    if hasTrips {
                        // Overlaps the faded valley of the summit chart by a few points (spec §8.1); the route starts above it.
                        DashBalanceCard(snapshot: snapshot, catalog: app.catalog)
                            .padding(.horizontal, Theme.Spacing.cardGutter)
                            .padding(.top, -Theme.Spacing.xs)
                            .reveal(order: 2)
                    } else {
                        DashEmptyInviteCard(hasFavorites: !favorites.isEmpty) { app.presentAddTrip() }
                            .padding(.horizontal, Theme.Spacing.cardGutter)
                            .padding(.top, Theme.Spacing.xs)
                            .reveal(order: 2)
                    }

                    if hasTrips || !favorites.isEmpty {
                        // No second "Neue Fahrt" button – the "+" tab does that (DESIGN.md §5.1 · 5).
                        DashQuickLogSection(favorites: favorites, summary: summary, ticketID: ticket.id,
                                            ticketIsCurrent: ticket.isActive, showsNewTripButton: false)
                            // The chip row carries 8 pt of vertical breathing room for glass and shadows → 10 pt below the card.
                            .padding(.top, 2)
                            .padding(.bottom, -Theme.Spacing.xs)
                            .reveal(order: 3)
                    }

                    if !suggestions.isEmpty {
                        DashSuggestionsSection(suggestions: suggestions)
                            .padding(.horizontal, Theme.Spacing.cardGutter)
                            .padding(.top, DashStyle.sectionSpacing)
                            .reveal(order: 4)
                            .motionTransition(.rise)
                    }

                    if !trips.isEmpty {
                        DashRecentTripsSection(trips: Array(trips.prefix(5)))
                            .padding(.horizontal, Theme.Spacing.cardGutter)
                            .padding(.top, suggestions.isEmpty ? Theme.Spacing.m : DashStyle.sectionSpacing)
                            .reveal(order: 5)
                            .scrollCardTransition()
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
                        .reveal(order: 8)
                        .scrollCardTransition()
                }
                .padding(.bottom, Theme.Spacing.xl)
                .motionAnimation(Motion.smooth, value: suggestions.count)
            }
            .accessibilityIdentifier("perf.scroll.overview") // MARK: perf – KlimaBilanzPerfTests
            .revealScope()
            .tracksScrollCondense(condense, distance: Self.condenseDistance)
            .modifier(DashScrollScrim())
            .overlay(alignment: .top) {
                DashCondensedSummit(condense: condense, summary: summary) {
                    withMotion(Motion.smooth) { proxy.scrollTo(Self.topID, anchor: .top) }
                }
            }
            .defaultScrollAnchor(Self.screenshotAnchor)
            // The sun glow brightens towards the summit, capped so the verdict lines above it keep their contrast.
            .ambientBackground(.standard, glow: 0.4 + 0.4 * summary.progressClamped)
            .refreshable { await refresh() }
        }
    }

    private static let topID = "dash.top"
    /// The hero's numeral and verdict have scrolled away (under the status bar) at about this offset.
    private static let condenseDistance: CGFloat = 250

    @ViewBuilder
    private func topSection(ticket: TicketEntity, snapshot: AnalyticsSnapshot) -> some View {
        let eyebrow = ticketEyebrow(ticket, summary: snapshot.summary)
        DashAccountHeader(eyebrow: eyebrow.full, compactEyebrow: eyebrow.compact, holderName: ticket.holderName) {
            app.selectedTab = .ticket
        }
        .id(Self.topID)
        .reveal(order: 0)

        // Status capsules between the title and the hero: a running ride first (it is happening right now), then a
        // pending update. Both render nothing when idle, so the hero keeps its place on a normal day.
        // MARK: live – "Unterwegs nach …" capsule(s) while a ride runs.
        RideDashCapsule()
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, Theme.Spacing.xs)
            .reveal(order: 0)

        DashUpdateCapsuleHost()
            .reveal(order: 0)

        // Spec §8.1: mountain canvas 134 pt, full width. Fades in (its numeral counts and its climber walks – that is
        // the movement), then condenses and falls behind the Bilanz card while scrolling.
        AmortizationHero(snapshot: snapshot, chartHeight: 134, countInDelay: Motion.Stagger.delay(1))
            .padding(.top, Theme.Spacing.xxs)
            .reveal(.fade, order: 1)
            .heroCondense(condense, minScale: 0.9, fadeTo: 0.15)
    }

    @ViewBuilder
    private func insights(snapshot: AnalyticsSnapshot) -> some View {
        VStack(spacing: DashStyle.cardSpacing) {
            DashAchievementTeaser(next: snapshot.nextAchievement,
                                  unlockedCount: snapshot.unlockedAchievements.count,
                                  totalCount: snapshot.achievements.count) {
                app.isShowingAchievements = true
            }
            .zoomSource(id: DashZoomID.gipfelbuch, cornerRadius: Theme.Radius.card)
            .reveal(order: 6)
            .scrollCardTransition()

            DashWeekInsightCard(stats: DashWeekStats.make(fromNewestFirst: trips))
                .reveal(order: 7)
                .scrollCardTransition()
        }
    }

    /// Fallback – RootView normally shows onboarding when there is no ticket.
    private var noTicket: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                DashAccountHeader(eyebrow: DashStyle.longDate(Date()), compactEyebrow: nil, holderName: "")
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
}

/// Payload of the break-even overlay.
struct DashCelebrationInfo: Equatable {
    var ticketName: String
    var profit: Double
}

// MARK: - Header

/// `DashHeader` with the account avatar and the update dot. Reads the sign-in and update state itself, so an update check
/// (`.checking` → `.upToDate` on every return to the app) or a sign-in re-renders only this header.
private struct DashAccountHeader: View {
    var eyebrow: String
    var compactEyebrow: String?
    /// Ticket holder – initials when nobody is signed in.
    var holderName: String
    var onEyebrow: (() -> Void)? = nil

    @Environment(AppState.self) private var app

    var body: some View {
        DashHeader(eyebrow: eyebrow, compactEyebrow: compactEyebrow, onEyebrow: onEyebrow,
                   avatarInitials: avatarInitials,
                   isSignedIn: app.auth.profile != nil,
                   hasUpdate: app.updates.availableManifest != nil && !LaunchMode.isScreenshot) {
            app.isShowingSettings = true
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.top, Theme.Spacing.xxs)
    }

    /// Same identity as Einstellungen: the signed-in profile (demo profile in CI screenshots), else the ticket holder.
    private var avatarInitials: String? {
        if let profile = app.auth.profile ?? (LaunchMode.isScreenshot ? SetDemo.profile : nil) {
            if let initials = DashAvatarButton.initials(from: profile.displayName) { return initials }
            if let initials = DashAvatarButton.initials(from: holderName) { return initials }
            if let first = profile.email?.first { return String(first).uppercased() }
            return nil
        }
        return DashAvatarButton.initials(from: holderName)
    }
}

/// „Neue Version … verfügbar“ under the header while an update is waiting (renders nothing otherwise).
private struct DashUpdateCapsuleHost: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if let manifest = app.updates.availableManifest, !LaunchMode.isScreenshot {
            DashUpdateCapsule(version: manifest.version.description) {
                app.updates.isPresentingSheet = true
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, Theme.Spacing.xs)
            .motionTransition(.rise)
        }
    }
}

// MARK: - Scroll scrim

/// Frosted fade under the status bar once the header has scrolled away. Owns the scroll flag, so crossing the threshold
/// re-renders only the scrim – never the dashboard content.
private struct DashScrollScrim: ViewModifier {
    @State private var isScrolled = false
    /// The scroll view reaches under the status bar: its top safe-area inset is the status bar height.
    @State private var statusBarHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self, of: { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 6
            }, action: { _, scrolled in
                withMotion(Motion.snappy) { isScrolled = scrolled }
            })
            .onGeometryChange(for: CGFloat.self, of: { proxy in proxy.safeAreaInsets.top }, action: { inset in
                statusBarHeight = inset
            })
            .overlay(alignment: .top) {
                DashTopScrim(statusBarHeight: statusBarHeight)
                    .opacity(isScrolled ? 1 : 0)
            }
    }
}

// MARK: - Sheets & celebration

/// Settings and Gipfelbuch sheets plus the one-time break-even celebration. The only place that reads the selected tab
/// and the app-level sheet flags, so presenting or dismissing a sheet (also the „+“ trip editor) and switching tabs do
/// not recompute the dashboard while the transition animates.
private struct DashPresentation: ViewModifier {
    var ticketID: UUID?
    var ticketName: String
    var isPaidOff: Bool
    var hasTrips: Bool
    var profit: Double

    @Environment(AppState.self) private var app
    @State private var celebration: DashCelebrationInfo?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: settingsBinding) {
                SettingsSheet() // MARK: settings – own NavigationStack + toast above every settings page
                    .zoomDestination(id: DashZoomID.settings)   // grows out of the avatar
            }
            .sheet(isPresented: achievementsBinding) {
                NavigationStack { AchievementsView() }
                    .zoomDestination(id: DashZoomID.gipfelbuch)   // grows out of the "Nächster Erfolg" card
            }
            .overlay { celebrationOverlay }
            .onChange(of: celebrationKey, initial: true) { _, _ in
                evaluateCelebration()
            }
    }

    /// Only the visible tab presents the shared sheets (other tabs may bind to the same flags).
    private var settingsBinding: Binding<Bool> {
        Binding(get: { app.isShowingSettings && app.selectedTab == .overview },
                set: { app.isShowingSettings = $0 })
    }

    private var achievementsBinding: Binding<Bool> {
        Binding(get: { app.isShowingAchievements && app.selectedTab == .overview },
                set: { app.isShowingAchievements = $0 })
    }

    @ViewBuilder
    private var celebrationOverlay: some View {
        if let info = celebration {
            BreakEvenCelebration(ticketName: info.ticketName, profit: info.profit) {
                withMotion(Motion.smooth) { celebration = nil }
            }
            .transition(.opacity)
            .zIndex(1)
        }
    }

    /// The Übersicht is on screen and no sheet covers it (Settings, Gipfelbuch, add/edit trip, update). The celebration
    /// waits until then – otherwise confetti and haptics would play unseen and the ticket would still count as celebrated.
    private var isVisible: Bool {
        app.selectedTab == .overview
            && !(app.isShowingSettings || app.isShowingAchievements || app.tripDraft != nil || app.updates.isPresentingSheet)
    }

    private var celebrationKey: String {
        guard let ticketID else { return "none" }
        return "\(ticketID.uuidString)|\(isPaidOff)|\(isVisible)|\(app.celebrateBreakEven)"
    }

    /// Shows the celebration once per ticket (ids in `celebratedBreakEvenTicketIDs`), only while the tab is visible
    /// and uncovered. Also consumes `app.celebrateBreakEven`.
    private func evaluateCelebration() {
        guard !LaunchMode.isScreenshot, celebration == nil, isVisible, let ticketID, isPaidOff, hasTrips else { return }
        if app.celebrateBreakEven { app.celebrateBreakEven = false }
        let id = ticketID.uuidString
        guard !app.settings.celebratedBreakEvenTicketIDs.contains(id) else { return }
        app.settings.celebratedBreakEvenTicketIDs.append(id)
        let info = DashCelebrationInfo(ticketName: ticketName, profit: profit)
        withMotion(Motion.smooth) { celebration = info }
    }
}

// MARK: - Zoom sources

/// Ids of the zoom transitions that start on the Übersicht (docs/MOTION.md §9).
enum DashZoomID {
    static let settings = "dash.settings"
    static let gipfelbuch = "dash.gipfelbuch"
    static let car = "dash.car"
}

// MARK: - Condensed hero

/// Once the hero has scrolled under the status bar, its essence stays in reach: a glass pill "◔ 75 % · noch € 350"
/// drops in below the status bar (tap → back to the top). Reads the scroll progress itself – the only view besides the
/// hero's transform that updates while scrolling.
private struct DashCondensedSummit: View {
    let condense: ScrollCondense
    let summary: SavingsSummary
    var onTap: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            if condense.isCondensed {
                // A frosted band continues the status-bar scrim under the pill, so the rows scrolling beneath never read
                // through around it; it fades out below the pill.
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask {
                        LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.62),
                                               .init(color: .clear, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .frame(height: 66)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .motionTransition(.opacity)
                Button(action: onTap) {
                    HStack(spacing: Theme.Spacing.xs) {
                        DashProgressDot(progress: summary.progressClamped, isPaidOff: summary.isPaidOff)
                        Text(Format.number(SummitFigures.percent(summary.amortizedFraction)) + " %")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                            .numericValue(summary.amortizedFraction)
                        Text(detail)
                            .font(.footnote.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                            .numericValue(summary.isPaidOff ? summary.shownProfitEuro : summary.shownRemainingEuro)
                    }
                    .lineLimit(1)
                    .padding(.leading, 8)
                    .padding(.trailing, 14)
                    .frame(minHeight: 38)
                    .contentShape(.capsule)
                }
                .buttonStyle(.pressable)
                .glassEffect(.regular.interactive(), in: .capsule)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .padding(.top, Theme.Spacing.xxs)
                .motionTransition(.drop)
                .accessibilityLabel("\(Format.percent(summary.amortizedFraction)) amortisiert, \(detail)")
                .accessibilityHint("Scrollt nach oben zur Übersicht")
            }
        }
        .motionAnimation(Motion.snappy, value: condense.isCondensed)
    }

    /// "noch € 350" · "+ € 156"
    private var detail: String {
        summary.isPaidOff ? "+ " + SummitFigures.euro(summary.shownProfitEuro)
                          : "noch " + SummitFigures.euro(summary.shownRemainingEuro)
    }
}

/// 18 pt progress ring in the route gradient (pine once paid off).
private struct DashProgressDot: View {
    var progress: Double
    var isPaidOff: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.textTertiary.opacity(0.3), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.02, min(progress, 1)))
                .stroke(isPaidOff ? AnyShapeStyle(Theme.positive) : AnyShapeStyle(Theme.routeGradient),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}
