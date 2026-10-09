import SwiftUI
import Combine
import SwiftData
import KlimaCore

/// Top-level switch between onboarding and the main tab interface, plus global sheets/overlays.
struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]
    @State private var showsAccountSwitch = false
    /// The scene was in the background since the last activation. A plain .inactive → .active (Control Center,
    /// Notification Center, a system alert, the app switcher, the launch itself) is no return to the app.
    @State private var returnedFromBackground = false

    var body: some View {
        @Bindable var app = app
        @Bindable var updates = app.updates

        Group {
            if let screen = LaunchMode.screenshotScreen {
                ScreenshotRouter(screen: screen)
            } else if app.sync.isReplacingLocalData {
                // Every local row is being replaced (account data, "Alles löschen"): no screen may still hold one of
                // them – SwiftData traps when a view reads a deleted model (SyncService.performLocalDataReplacement).
                AmbientBackground(animated: false)
                    .overlay { ProgressView() }
                    .transition(.opacity)
            } else if !app.settings.onboardingCompleted || tickets.isEmpty {
                if app.auth.isLoaded {
                    OnboardingFlow()
                        .transition(.opacity.combined(with: .scale(scale: 1.02)))
                } else {
                    // The welcome step decides once whether you are signed in: wait the moment the Keychain read
                    // takes (off the main thread, see AuthService) under the welcome sky.
                    AmbientBackground(style: colorScheme == .dark ? .onboarding : .standard, glow: 0.95)
                }
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .environment(\.ambientSkyPaused, isCoveredByAppSheet)
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
        .alert("Anderes Konto angemeldet", isPresented: $showsAccountSwitch, presenting: app.sync.pendingAccountSwitch) { change in
            Button("Daten dieses iPhones übernehmen") {
                Task {
                    await app.sync.mergeLocalDataIntoAccount(context: context, auth: app.auth)
                    Repository(context: context, app: app).refreshWidgets()
                }
            }
            Button(change.unsyncedItemCount > 0 ? "Durch Konto ersetzen (\(change.unsyncedItemCount) ungesichert)" : "Durch Daten des Kontos ersetzen",
                   role: .destructive) {
                Task {
                    await app.sync.discardLocalDataAndSync(context: context, auth: app.auth)
                    Repository(context: context, app: app).refreshWidgets()
                }
            }
            Button("Abbrechen – abmelden", role: .cancel) {
                Task { await app.sync.cancelAccountSwitch(auth: app.auth) }
            }
        } message: { change in
            Text(Self.accountSwitchMessage(change))
        }
        .onChange(of: app.sync.pendingAccountSwitch, initial: true) { _, _ in
            updateAccountSwitchAlert(afterDismissal: false)
        }
        .onChange(of: isCoveredByAppSheet) { _, covered in
            if !covered { updateAccountSwitchAlert(afterDismissal: true) }
        }
        .onChange(of: tickets.isEmpty, initial: true) { _, isEmpty in
            // Tickets came from the account (reinstall, new iPhone): the setup is done – onboarding would add a second
            // ticket starting today. finish() sets the flag in the same turn as its ticket, so this skips it.
            guard !isEmpty, !app.settings.onboardingCompleted, !LaunchMode.isSandboxed else { return }
            app.settings.onboardingCompleted = true
            app.showToast("checkmark.icloud.fill", "Willkommen zurück", "Deine Daten wurden geladen")
        }
        .onChange(of: app.auth.phase) { old, new in
            // Signed in during onboarding (welcome step): fetch the account's data right away (see above).
            guard case .signingIn = old, new == .signedIn, !app.settings.onboardingCompleted, !LaunchMode.isSandboxed else { return }
            Task { await app.sync.sync(context: context, auth: app.auth) }
        }
        .preferredColorScheme(app.settings.appearance.colorScheme)
        .tint(Theme.accent)
        .diagnosticsNavigationTracking() // MARK: Diagnostics – breadcrumbs (tab, global sheets)
        .onOpenURL { url in handleDeepLink(url) }
        .onReceive(NotificationCenter.default.publisher(for: QuickLogQueue.didEnqueue).receive(on: RunLoop.main)) { _ in
            handleExternalRequests()
        }
        .rideActivityHost()  // MARK: live
        .task {
            LaunchTrace.mark("root.task")
            // All Austrian stops + localities (places.bin): built once off the main thread, then every station
            // search (StationIndex façade) covers all ~40.000 stops.
            PlaceIndexLoader.shared.preload()
            let bundled = app.bundled
            PlaceIndexLoader.shared.whenReady { index in bundled.stations.value.attach(places: index) }
            guard !LaunchMode.isSandboxed else { return }
            handleExternalRequests()
            // Nothing below is visible right away: let the first frames and the entrance animations run first.
            try? await Task.sleep(for: .milliseconds(700))
            KBTips.configure()   // MARK: motion – TipKit, once per launch (never in screenshot/perf runs)
            let repo = Repository(context: context, app: app)
            if widgetSnapshotIsStale() { repo.refreshWidgets() }   // date-dependent fields; data changes refresh on save
            if app.detection.isEnabled { repo.configureTripDetection() }
            if app.settings.autoUpdateCheck { await app.refreshRemoteContent() }
            await Diagnostics.measureAsync("Sync") { await app.sync.sync(context: context, auth: app.auth) }
            repo.refreshWidgets()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard !LaunchMode.isSandboxed else { return }
            switch phase {
            case .background:
                returnedFromBackground = true
            case .active:
                // MARK: dashboardTicket – an expired pinned ticket year gives way to the running one (checked once a day).
                if TktSelection.releaseStalePin(tickets: tickets, app: app) {
                    Repository(context: context, app: app).refreshWidgets()
                }
                // Cheap, and needed on every activation: quick logs and "Fahrt erfassen" from Control Center / widgets.
                handleExternalRequests()
                guard returnedFromBackground else { return }
                returnedFromBackground = false
                Task { await refreshAfterReturn() }
            default:
                break
            }
        }
        .onAppear { LaunchTrace.mark("root.appear") }
    }

    /// One of the app-level sheets is up (RootView's own, or Einstellungen / Gipfelbuch, presented by a tab).
    private var isCoveredByAppSheet: Bool {
        app.tripDraft != nil || app.isShowingSettings || app.isShowingAchievements || app.updates.isPresentingSheet
    }

    /// Back from the background: remote content, sync, detection regions and – only if something changed – widgets.
    private func refreshAfterReturn() async {
        let catalogVersion = app.catalog.version
        if app.settings.autoUpdateCheck { await app.refreshRemoteContent() }
        await Diagnostics.measureAsync("Sync") { await app.sync.sync(context: context, auth: app.auth) }
        let repo = Repository(context: context, app: app)
        if app.detection.isEnabled { repo.configureTripDetection() }   // favourites and trips may have changed
        if app.catalog.version != catalogVersion || widgetSnapshotIsStale() { repo.refreshWidgets() }
    }

    /// The widget snapshot follows every save already; it is out of date only on a new day or after a sync.
    private func widgetSnapshotIsStale() -> Bool {
        guard let snapshot = WidgetSnapshot.load() else { return true }
        if !Calendar.vienna.isDateInToday(snapshot.generatedAt) { return true }
        if let lastSync = app.sync.lastSync, lastSync > snapshot.generatedAt { return true }
        return false
    }

    /// The account-switch decision is a RootView alert, which SwiftUI cannot show over a sheet. Signing in happens in
    /// Einstellungen (a sheet), so that closes first; other sheets are waited for (`isCoveredByAppSheet`).
    private func updateAccountSwitchAlert(afterDismissal: Bool) {
        guard app.sync.pendingAccountSwitch != nil, !LaunchMode.isSandboxed else {
            showsAccountSwitch = false
            return
        }
        guard !showsAccountSwitch else { return }
        if app.isShowingSettings {
            app.isShowingSettings = false   // → onChange(of: isCoveredByAppSheet) comes back here
            return
        }
        guard !isCoveredByAppSheet else { return }
        guard afterDismissal else {
            showsAccountSwitch = true
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))   // the sheet's dismissal animation
            if app.sync.pendingAccountSwitch != nil, !isCoveredByAppSheet { showsAccountSwitch = true }
        }
    }

    private static func accountSwitchMessage(_ change: SyncService.AccountSwitch) -> String {
        let previous = change.previousEmail ?? "einem anderen Konto"
        let current = change.newEmail ?? "einem neuen Konto"
        var text = "Auf diesem iPhone liegen \(change.localItemCount) Einträge von \(previous). Du bist jetzt mit \(current) angemeldet. "
        text += "Sollen sie in dieses Konto übernommen oder durch die Daten des Kontos ersetzt werden?"
        if change.unsyncedItemCount > 0 {
            text += " \(change.unsyncedItemCount) Änderungen wurden noch nicht gesichert und gehen beim Ersetzen verloren."
        }
        return text
    }

    /// Pending quick logs (widgets/Siri) and "open add trip" requests from App Intents.
    private func handleExternalRequests() {
        let added = Repository(context: context, app: app).ingestQuickLogs()
        if added > 0 {
            app.showToast("checkmark.circle.fill", added == 1 ? "Fahrt erfasst" : "\(added) Fahrten erfasst", "über Widget oder Siri")
        }
        if AppGroup.defaults.bool(forKey: OpenAddTripIntent.pendingKey) {
            AppGroup.defaults.removeObject(forKey: OpenAddTripIntent.pendingKey)
            app.presentAddTripFromOutside()
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
            app.presentAddTripFromOutside(draft)
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
            .onAppear { LaunchTrace.mark("screen.appear") }
            .task {
                switch screen {
                case "addTrip", "addTripCategory", "addTripLive": // MARK: tripmeta – addTripCategory; live – addTripLive
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
                case "tripEdit": // MARK: trips – "Fahrt bearbeiten": a trip without tariff data keeps its saved price
                    try? await Task.sleep(for: .milliseconds(600))
                    let trips = Repository(context: context, app: app).liveTrips()
                    if let trip = trips.first(where: { $0.fromStationID == nil || $0.toStationID == nil }) ?? trips.first {
                        TripListActions(app: app, context: context).edit(trip)
                    }
                default:
                    break
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        // MARK: Diagnostics
        case "diagnostics":
            NavigationStack { SetDiagnosticsPage() }
        case "onboarding":
            OnboardingFlow()
        case "trips":
            MainTabView().onAppear { app.selectedTab = .trips }
        case "stats", "statsCategories", "statsHonest": // MARK: tripmeta – statsCategories, statsHonest
            MainTabView().onAppear { app.selectedTab = .stats }
        case "ticket":
            MainTabView().onAppear { app.selectedTab = .ticket }
        case "tripEdit": // MARK: trips
            MainTabView().onAppear { app.selectedTab = .trips }
        case "tripDetail":
            NavigationStack {
                if let trip = Repository(context: context, app: app).liveTrips().first {
                    TripDetailView(trip: trip)
                }
            }
        case "favoriteEdit": // MARK: tripmeta
            NavigationStack { FavoritesManagerView() }
        case "achievements":
            NavigationStack { AchievementsView() }
        case "achievementDetail": // MARK: stats – Gipfelbuch with the detail sheet of its highest medal open
            NavigationStack { AchievementsView(opensDetailForScreenshot: true) }
        case "settings":
            NavigationStack { SettingsView() }
        // MARK: polish-settings – lower parts of the long settings list
        case "settings2", "settings3", "settingsEnd":
            NavigationStack { SettingsView(screenshotScreen: screen) }
        // MARK: benefits
        case "benefits", "benefitsHistory", "benefitCatalog", "benefitEditor":
            NavigationStack { PerkBenefitsView() }
                .sheet(isPresented: .constant(screen == "benefitCatalog" || screen == "benefitEditor")) {
                    if screen == "benefitCatalog" {
                        PerkCatalogSheet()
                    } else if let partner = PerkCatalogStore.shared.partner(id: "cat") {
                        NavigationStack { PerkEditorView(mode: .new(partner)) {} }
                    }
                }
        case "passengerRights", "passengerRightsChecklist":
            NavigationStack { PerkPassengerRightsView() }
        case "benefitCard":
            NavigationStack { PerkEntryPreview() }
        case "benefitSettings":
            NavigationStack { PerkSettingsPreview() }
        case "widgets":
            NavigationStack { WidgetGalleryView() }
        // MARK: polish-widgets – lower part of the widget gallery (large + quick log; lock screen + guide)
        case "widgets2":
            NavigationStack { WidgetGalleryView(screenshotSection: .large) }
        case "widgets3":
            NavigationStack { WidgetGalleryView(screenshotSection: .lock) }
        // MARK: work
        case "car", "carDetails", "carSettings", "carSettingsDetails", "carCard", "work", "workDetails", "workSelf",
             "workAssign", "workContribution", "workPDF", "workLogbookPDF":
            WorkScreenshotHost(screen: screen)
        case "liveActivityPreview":  // MARK: live
            NavigationStack { RideActivityPreviewView() }
        case "dashboardLive":  // MARK: live
            MainTabView().onAppear { RideActivityController.shared.showScreenshotRide(context: context, app: app) }
        case "hero":
            DesignSystemPreview()
        case "motionGallery", "motionGallery2", "motionGallery3", "motionCelebration": // MARK: motion – DEBUG builds only
            #if DEBUG
            if screen == "motionCelebration" {
                BreakEvenCelebration(ticketName: "KlimaTicket Ö Klassik", profit: 412) {}
                    .background { AmbientBackground() }
            } else {
                MotionGalleryView(initialSection: screen == "motionGallery2" ? .controls : (screen == "motionGallery3" ? .celebrate : .top))
            }
            #else
            MainTabView()
            #endif
        case "stationSearch":
            // All-stops search QA: waits for the place index, then searches like a user typing.
            ScreenshotStationSearch(query: "warth am arlberg dorf")
        case "stationSearchBus":
            ScreenshotStationSearch(query: "lech post")
        // MARK: reports
        case let reportScreen where RepScreenshotHost.screens.contains(reportScreen):
            RepScreenshotHost(screen: reportScreen)
        // MARK: map
        case _ where screen.hasPrefix("map"):
            AtlasScreenshotScene(screen: screen)
        // MARK: advisor
        case "advisor", "advisorRenewal", "advisorCancel", "advisorCancelChart", "advisorExtras", "advisorFamily",
             "advisorJob", "ticketEdit", "ticketAdvisor":
            AdvScreenshotHost(screen: screen)
        default:
            MainTabView().onAppear { app.selectedTab = .overview }
        }
    }
}

/// CI screenshot: the station picker once the complete place index is attached.
private struct ScreenshotStationSearch: View {
    let query: String
    @State private var isReady = false

    var body: some View {
        NavigationStack {
            if isReady {
                StationPickerView(title: "Von", initialQuery: query) { _ in }
            } else {
                ProgressView()
            }
        }
        .task {
            _ = try? await PlaceIndexLoader.shared.load()
            isReady = true
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
