import SwiftUI
import Combine
import SwiftData
import KlimaCore

/// Top-level switch between onboarding and the main tab interface, plus global sheets/overlays.
struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]

    var body: some View {
        @Bindable var app = app
        @Bindable var updates = app.updates

        Group {
            if let screen = LaunchMode.screenshotScreen {
                ScreenshotRouter(screen: screen)
            } else if !app.settings.onboardingCompleted || tickets.isEmpty {
                OnboardingFlow()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.5), value: app.settings.onboardingCompleted)
        .sheet(item: $app.tripDraft) { draft in
            TripEditorView(draft: draft)
        }
        .sheet(isPresented: $updates.isPresentingSheet) {
            UpdateSheet()
                .interactiveDismissDisabled(app.updates.isRequired)
        }
        .overlay(alignment: .top) {
            ToastOverlay()
        }
        .preferredColorScheme(app.settings.appearance.colorScheme)
        .tint(Theme.accent)
        .onOpenURL { url in handleDeepLink(url) }
        .onReceive(NotificationCenter.default.publisher(for: QuickLogQueue.didEnqueue)) { _ in
            handleExternalRequests()
        }
        .task {
            guard !LaunchMode.isScreenshot else { return }
            handleExternalRequests()
            let repo = Repository(context: context, app: app)
            repo.refreshWidgets()
            repo.configureTripDetection()
            if app.settings.autoUpdateCheck { await app.refreshRemoteContent() }
            await app.sync.sync(context: context, auth: app.auth)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !LaunchMode.isScreenshot else { return }
            handleExternalRequests()
            Task {
                if app.settings.autoUpdateCheck { await app.refreshRemoteContent() }
                await app.sync.sync(context: context, auth: app.auth)
            }
        }
    }

    /// Pending quick logs (widgets/Siri) and "open add trip" requests from App Intents.
    private func handleExternalRequests() {
        let added = Repository(context: context, app: app).ingestQuickLogs()
        if added > 0 {
            app.showToast("checkmark.circle.fill", added == 1 ? "Fahrt erfasst" : "\(added) Fahrten erfasst", "über Widget oder Siri")
        }
        if AppGroup.defaults.bool(forKey: OpenAddTripIntent.pendingKey) {
            AppGroup.defaults.removeObject(forKey: OpenAddTripIntent.pendingKey)
            app.presentAddTrip()
        }
    }

    /// klimabilanz://add · klimabilanz://add?from=<stationID>&to=<stationID>
    /// klimabilanz://log?favorite=<uuid> · klimabilanz://tab/<overview|trips|stats|ticket> · klimabilanz://update
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == AppConfig.urlScheme else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        switch url.host() {
        case "add":
            var draft = TripDraft()
            draft.fromStationID = value("from")
            draft.toStationID = value("to")
            app.presentAddTrip(draft)
        case "log":
            guard let id = value("favorite").flatMap(UUID.init(uuidString:)) else { return }
            let repo = Repository(context: context, app: app)
            if let fav = repo.liveFavorites().first(where: { $0.id == id }) {
                let trip = repo.logFavorite(fav)
                app.showToast("checkmark.circle.fill", "Fahrt erfasst", "\(fav.displayTitle) · \(Format.euro(trip.totalValue))")
            }
        case "tab":
            if let tab = AppTab(rawValue: url.lastPathComponent) { app.selectedTab = tab }
        case "update":
            Task { await app.updates.checkIfDue(force: true) }
        default:
            break
        }
    }
}

/// The main interface: Liquid Glass tab bar with a separated "+" action.
struct MainTabView: View {
    @Environment(AppState.self) private var app
    @State private var lastContentTab: AppTab = .overview

    var body: some View {
        TabView(selection: tabSelection) {
            Tab(AppTab.overview.title, systemImage: AppTab.overview.symbol, value: AppTab.overview) {
                DashboardView()
            }
            Tab(AppTab.trips.title, systemImage: AppTab.trips.symbol, value: AppTab.trips) {
                TripsView()
            }
            Tab(AppTab.stats.title, systemImage: AppTab.stats.symbol, value: AppTab.stats) {
                StatisticsView()
            }
            Tab(AppTab.ticket.title, systemImage: AppTab.ticket.symbol, value: AppTab.ticket) {
                TicketView()
            }
            Tab(AppTab.add.title, systemImage: AppTab.add.symbol, value: AppTab.add, role: .search) {
                Color.clear
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }

    /// The "+" tab never becomes selected – it opens the add-trip sheet instead.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { app.selectedTab == .add ? lastContentTab : app.selectedTab },
            set: { newValue in
                if newValue == .add {
                    app.presentAddTrip()
                } else {
                    lastContentTab = newValue
                    app.selectedTab = newValue
                }
            }
        )
    }
}

/// Routes CI screenshot launches (`-KBScreenshot <screen>`) to the right UI state.
struct ScreenshotRouter: View {
    let screen: String
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context

    var body: some View {
        content
            .task {
                switch screen {
                case "addTrip":
                    var draft = TripDraft()
                    draft.fromName = "St. Anton am Arlberg"
                    draft.toName = "Innsbruck Hbf"
                    draft.fromStationID = app.stations.station(named: "St. Anton am Arlberg")?.id
                    draft.toStationID = app.stations.station(named: "Innsbruck Hbf")?.id
                    draft.isRoundTrip = true
                    try? await Task.sleep(for: .milliseconds(600))
                    app.presentAddTrip(draft)
                case "update":
                    try? await Task.sleep(for: .milliseconds(600))
                    app.updates.presentSample()
                default:
                    break
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case "onboarding":
            OnboardingFlow()
        case "trips":
            MainTabView().onAppear { app.selectedTab = .trips }
        case "stats":
            MainTabView().onAppear { app.selectedTab = .stats }
        case "ticket":
            MainTabView().onAppear { app.selectedTab = .ticket }
        case "tripDetail":
            NavigationStack {
                if let trip = Repository(context: context, app: app).liveTrips().first {
                    TripDetailView(trip: trip)
                }
            }
        case "achievements":
            NavigationStack { AchievementsView() }
        case "settings":
            NavigationStack { SettingsView() }
        case "widgets":
            NavigationStack { WidgetGalleryView() }
        case "hero":
            DesignSystemPreview()
        case _ where screen.hasPrefix("map"):
            AtlasScreenshotScene(screen: screen)
        default:
            MainTabView().onAppear { app.selectedTab = .overview }
        }
    }
}

/// Design-system QA screen (CI screenshot "hero"): hero, cards, rows and the ticket card with demo data.
struct DesignSystemPreview: View {
    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date, order: .reverse) private var trips: [TripEntity]

    var body: some View {
        ScrollView {
            if let ticket = tickets.first {
                let snap = Analytics.make(ticket: ticket, trips: trips, catalog: app.catalog)
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    Kicker(text: Format.weekdayDayMonth(Date()))
                    Text("Übersicht").font(.largeTitle.bold())
                    AmortizationHero(snapshot: snap, chartHeight: 220)
                    HStack(spacing: Theme.Spacing.s) {
                        StatTile(value: "\(snap.summary.tripCount)", label: "Fahrten", symbol: "tram.fill")
                        StatTile(value: Format.number(snap.summary.co2SavedKg), unit: "kg", label: "CO₂ gespart", symbol: "leaf.fill", color: Theme.pine)
                    }
                    GlassCard(padding: Theme.Spacing.m) {
                        VStack(spacing: 0) {
                            ForEach(trips.prefix(3)) { TripRow(trip: $0) }
                        }
                    }
                    TicketCard(title: ticket.name, subtitle: "Klassik · Gültig in ganz Österreich", holder: ticket.holderName,
                               validFrom: ticket.startDate, validUntil: ticket.endDate, ticketNumber: ticket.ticketNumber,
                               theme: .twilight, roll: 0.3, pitch: 0.1, hasPhoto: true,
                               amortizedFraction: snap.summary.amortizedFraction,
                               valueText: "\(Format.euro(snap.summary.totalValue)) von \(Format.euro(ticket.price))",
                               onOriginal: {})
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.top, 60)
                .padding(.bottom, 40)
            }
        }
        .ambientBackground()
    }
}
