import SwiftUI
import SwiftData
import KlimaCore

/// Root of the Fahrplan tab (docs/OEBB_LIVE.md §E1/§E3, UX §4.1): search form, „Deine Strecken“, „In der Nähe“, and the
/// departure board. Connections and details are pushed on its stack; the bottom search field is the tab bar's.
struct PlannerRootView: View {
    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]

    var body: some View {
        @Bindable var model = app.planner
        NavigationStack(path: $model.path) {
            PlannerHomeView()
                .navigationDestination(for: PlannerRoute.self) { route in
                    switch route {
                    case .results: PlannerResultsView()
                    case .detail(let id): ConnectionDetailView(rowID: id)
                    }
                }
        }
        .zoomTransitionScope()
        .modifier(PlannerOwnSearchField())
        .sheet(isPresented: $model.showsOptions) { PlannerOptionsSheet() }
        .sheet(isPresented: $model.showsTimeSheet) { PlannerTimeSheet() }
        // Only the visible tab presents the shared Settings sheet (see DashPresentation).
        .sheet(isPresented: Binding(get: { app.isShowingSettings && app.selectedTab == .planner },
                                    set: { app.isShowingSettings = $0 })) { SettingsSheet() }
        .onAppear { configureTicket() }
        .onChange(of: tickets.map(\.id)) { _, _ in configureTicket() }
        .onChange(of: app.settings.selectedTicketID) { _, _ in configureTicket() }
    }

    private func configureTicket() {
        let ticket = Analytics.activeTicket(in: tickets, selectedID: app.settings.selectedTicketID)
        app.planner.configure(ticketProductID: ticket?.productID, ticketName: ticket?.name)
    }
}

/// `PlannerModel.navigationStyle == .plainTab`: the planner shows its own search field (fallback R4).
private struct PlannerOwnSearchField: ViewModifier {
    @Environment(AppState.self) private var app

    func body(content: Content) -> some View {
        @Bindable var model = app.planner
        if PlannerModel.navigationStyle == .plainTab {
            content.searchable(text: $model.query, prompt: Text(model.searchPrompt))
        } else {
            content
        }
    }
}

// MARK: - Home

struct PlannerHomeView: View {
    @Environment(AppState.self) private var app
    @Environment(\.isSearching) private var isSearching
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date, order: .reverse) private var trips: [TripEntity]
    @Query(filter: #Predicate<FavoriteRouteEntity> { $0.deletedAt == nil }, sort: \FavoriteRouteEntity.sortIndex) private var favorites: [FavoriteRouteEntity]

    var body: some View {
        let model = app.planner
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    header(model)
                    modePicker(model)
                    if model.mode == .connections {
                        ConnectionsHome(trips: trips, favorites: favorites)
                    } else {
                        DeparturesView()
                    }
                    PlannerAttribution()
                }
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.top, Theme.Spacing.xxs)
                .padding(.bottom, Theme.Spacing.xxl)
                .motionAnimation(Motion.smooth, value: model.mode)
            }
            .scrollDismissesKeyboard(.interactively)
            .revealScope()
            .opacity(isSearching ? 0 : 1)
            if isSearching {
                PlannerSearchView()
                    .transition(.opacity)
            }
        }
        .ambientBackground(.standard, glow: 0.45)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .motionAnimation(Motion.snappy, value: isSearching)
        .onChange(of: isSearching) { _, searching in
            if !searching { model.isSearchFocused = false }
        }
        .task(id: app.live.generation) {
            await model.loadNearby()
            await model.refreshHereIfAuthorized()
        }
    }

    private func header(_ model: PlannerModel) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Kicker(text: Format.weekdayDayMonth(Date()))
                Text(AppTab.planner.title)
                    .font(Theme.Typography.heroTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.leading, Theme.Spacing.xxs + 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { model.showsOptions = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 46, height: 46)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .overlay(alignment: .topTrailing) {
                if model.activeOptionCount > 0 {
                    Text("\(model.activeOptionCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Theme.dawn, in: .circle)
                        .offset(x: 3, y: -3)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel("Optionen")
            .accessibilityValue(model.activeOptionCount > 0 ? "\(model.activeOptionCount) aktiv" : "")
        }
        .reveal(.focus)
    }

    private func modePicker(_ model: PlannerModel) -> some View {
        @Bindable var model = model
        return GlassSegmentedPicker(selection: $model.mode, options: PlannerModel.Mode.allCases) { mode in
            Label(mode.title, systemImage: mode.symbol)
        }
        .reveal(order: 1)
        .onChange(of: model.mode) { _, mode in
            if mode == .departures { Task { await model.prepareBoardStation() } }
        }
    }
}

/// „Daten: ÖBB-Personenverkehr AG · Preise ohne Gewähr · KlimaBilanz verkauft keine Tickets“.
struct PlannerAttribution: View {
    var body: some View {
        Text("Daten: ÖBB-Personenverkehr AG · Preise ohne Gewähr · KlimaBilanz verkauft keine Tickets")
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.top, Theme.Spacing.xs)
    }
}

// MARK: - Verbindungen

struct ConnectionsHome: View {
    var trips: [TripEntity]
    var favorites: [FavoriteRouteEntity]

    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let model = app.planner
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            if let reason = app.live.timetableUnavailable, reason != .offline {
                PlannerUnavailableView(reason: reason) { app.isShowingSettings = true }
                    .reveal(order: 2)
            }
            RouteSlotsCard(origin: slot(model, "origin", "Von", model.origin, placeholder: "Von wo?"),
                           vias: model.vias.enumerated().map { slot(model, "via-\($0.offset)", "Über", $0.element, placeholder: "") },
                           destination: slot(model, "destination", "Nach", model.destination, placeholder: "Wohin?"),
                           onTap: { tap($0, model) }, onSwap: { model.swap() },
                           onRemoveVia: { id in if let i = Int(id.dropFirst(4)) { model.removeVia(at: i) } },
                           onAddVia: model.hasBoth || model.destination != nil ? { model.addVia() } : nil) {
                PlannerTimeRow()
            }
            .reveal(order: 2)
            if model.hasBoth {
                Button { model.startSearch() } label: {
                    Text("Verbindungen suchen").font(.headline).frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.prominentTint)
                .disabled(app.live.timetable == nil)
                .motionTransition(.rise)
            }
            if !model.routes.isEmpty {
                YourRoutesSection(routes: model.routes)
                    .reveal(order: 3)
            }
            if let nearby = model.nearby {
                NearbySection(nearby: nearby)
                    .reveal(order: 4)
            }
        }
        .task(id: routesKey) { await loadRoutes() }
        .task(id: app.live.generation) { await refreshLoop() }
    }

    private var routesKey: String { "\(trips.count)|\(favorites.count)|\(app.live.generation)" }

    private func loadRoutes() async {
        let relations = app.planner.screenshotRoutes ?? YourRoutes.relations(trips: trips, favorites: favorites, stations: app.stations)
        await app.planner.loadRoutes(relations)
    }

    /// 60 s while the Fahrplan is on screen; paused in the background and in Low Power Mode.
    private func refreshLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, scenePhase == .active, !ProcessInfo.processInfo.isLowPowerModeEnabled else { continue }
            await loadRoutes()
        }
    }

    private func tap(_ id: String, _ model: PlannerModel) {
        switch id {
        case "origin": model.beginSearch(.origin)
        case "destination": model.beginSearch(.destination)
        default:
            if id.hasPrefix("via-"), let i = Int(id.dropFirst(4)) { model.beginSearch(.via(i)) }
        }
    }

    private func slot(_ model: PlannerModel, _ id: String, _ caption: String, _ place: PlannerPlace?, placeholder: String) -> RouteSlot {
        guard let place else { return RouteSlot(id: id, caption: caption, title: placeholder, subtitle: nil, isPlaceholder: true) }
        if case .currentLocation = place {
            var subtitle: String?
            if let here = model.hereStop {
                subtitle = DisplayNames.name(here.location.name) + (here.distanceMeters.map { " · \($0) m" } ?? "")
            } else if model.live.timetable != nil {
                subtitle = "Nächste Haltestelle wird beim Suchen ermittelt"
            }
            return RouteSlot(id: id, caption: caption, title: place.title, subtitle: subtitle, isPlaceholder: false, showsLocationArrow: model.hereStop != nil)
        }
        return RouteSlot(id: id, caption: caption, title: place.title, subtitle: place.subtitle, isPlaceholder: false)
    }
}

/// „Abfahrt ⌄ · Jetzt · Heute, 11:58 ›“ – the time row of the search card.
struct PlannerTimeRow: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let model = app.planner
        HStack(spacing: Theme.Spacing.xs) {
            Menu {
                Picker("Zeit", selection: Binding(get: { model.isArrival },
                                                  set: { model.setWhen($0 ? (model.when ?? Date()) : model.when, arrival: $0) })) {
                    Text("Abfahrt").tag(false)
                    Text("Ankunft").tag(true)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "clock").font(.system(size: 15, weight: .semibold))
                    Text(model.isArrival ? "Ankunft" : "Abfahrt").font(.system(size: 16, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.surfaceSecondary, in: .capsule)
            }
            Button { model.setWhen(nil, arrival: false) } label: {
                Text("Jetzt")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(model.when == nil ? Theme.accentText : Theme.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(model.when == nil ? Theme.accent.opacity(0.16) : Color.clear, in: .capsule)
            }
            .buttonStyle(.plain)
            Button { model.showsTimeSheet = true } label: {
                HStack(spacing: 6) {
                    Text(PlannerTimeText.chip(model.when ?? Date()))
                        .font(.system(size: 16, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.textTertiary)
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.surfaceSecondary, in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zeit wählen")
            .accessibilityValue(PlannerTimeText.chip(model.when ?? Date()))
            Spacer(minLength: 0)
        }
        .haptic(.selection, trigger: model.isArrival)
        .lineLimit(1)
    }
}

enum PlannerTimeText {
    /// „Heute, 11:58“, „Morgen, 06:30“, „Fr., 9. Okt., 11:58“.
    static func chip(_ date: Date) -> String {
        let cal = Calendar.vienna
        let day: String
        if cal.isDateInToday(date) { day = "Heute" } else if cal.isDateInTomorrow(date) { day = "Morgen" } else { day = Format.relativeDay(date) }
        return "\(day), \(Format.time(date))"
    }
}

// MARK: - Deine Strecken

struct YourRoutesSection: View {
    var routes: [PlannerModel.RouteSuggestion]
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Deine Strecken").font(Theme.Typography.sectionTitle).foregroundStyle(Theme.textPrimary).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("aus deinen Fahrten").font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, Theme.Spacing.xxs)
            VStack(spacing: 0) {
                ForEach(Array(routes.enumerated()), id: \.element.id) { index, route in
                    Button {
                        let model = app.planner
                        model.origin = .station(route.from)
                        model.destination = .station(route.to)
                        model.vias = []
                        model.startSearch()
                    } label: {
                        RouteSuggestionRow(route: route)
                    }
                    .buttonStyle(.pressableCard)
                    if index < routes.count - 1 {
                        Divider().overlay(Theme.separator).padding(.leading, 68)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.xxs)
            .frostedCard(cornerRadius: Theme.Radius.card)
        }
    }
}

struct RouteSuggestionRow: View {
    var route: PlannerModel.RouteSuggestion

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ModeIcon(mode: route.journey.map(JourneyMetrics.dominantMode) ?? .train, size: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(TripRow.short(route.from.name)) → \(TripRow.short(route.to.name))")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                detail
            }
            Spacer(minLength: 4)
            if let minutes = minutesUntil {
                VStack(alignment: .trailing, spacing: -1) {
                    Text("IN").font(.system(size: 11, weight: .bold)).tracking(0.8).foregroundStyle(Theme.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(minutes)").font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                            .contentTransition(.numericText())
                        Text("min").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                    }
                }
            } else {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.vertical, 12)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint("Sucht Verbindungen")
    }

    @ViewBuilder
    private var detail: some View {
        if let summary = route.summary {
            HStack(spacing: 6) {
                LiveDot(state: summary.departure.state, size: 7)
                Text(summary.plannedDeparture.map(Format.time) ?? "")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PlannerRealtimeStyle.text(summary.departure.state))
                ForEach(Array(route.badges.prefix(2).enumerated()), id: \.offset) { index, badge in
                    if index > 0 { Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textTertiary) }
                    LinePlate(badge, size: .s)
                }
                Text(trailingText(summary))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        } else {
            Text("Nächste Abfahrt antippen").font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
        }
    }

    private func trailingText(_ s: ConnectionSummary) -> String {
        if route.badges.count > 1, let arrival = s.plannedArrival { return "an \(Format.time(arrival))" }
        var parts: [String] = []
        if let platform = s.departurePlatform { parts.append(platform.text) }
        // „pünktlich“ is already the green dot; only a delay or a cancellation is worth the room.
        if s.departure.state == .late || s.departure.state == .veryLate || s.departure.state == .cancelled, let text = s.departure.text { parts.append(text) }
        return parts.joined(separator: " · ")
    }

    private var minutesUntil: Int? {
        guard let summary = route.summary, let planned = summary.plannedDeparture else { return nil }
        let when = planned.addingTimeInterval(Double(summary.departure.delayMinutes ?? 0) * 60)
        return max(0, Int(when.timeIntervalSinceNow / 60))
    }

    private var spoken: String {
        guard let s = route.summary else { return "\(route.from.name) nach \(route.to.name)" }
        let time = s.plannedDeparture.map(RealtimePresentation.time) ?? ""
        return "\(route.from.name) nach \(route.to.name), nächste Abfahrt \(time)" + (minutesUntil.map { ", in \($0) Minuten" } ?? "")
    }
}

// MARK: - In der Nähe

struct NearbySection: View {
    var nearby: PlannerModel.NearbyBoard
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("In der Nähe").font(Theme.Typography.sectionTitle).foregroundStyle(Theme.textPrimary).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Abfahrten") {
                    let model = app.planner
                    model.boardStation = .station(nearby.station)
                    model.boardDate = nil
                    withMotion(Motion.snappy) { model.mode = .departures }
                    Task { await model.loadBoard() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accentText)
            }
            .padding(.horizontal, Theme.Spacing.xxs)
            VStack(spacing: 0) {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "mappin.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.accent).frame(width: 34)
                    Text(DisplayNames.name(nearby.station.name)).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Spacer(minLength: 4)
                    if let meters = nearby.distanceMeters {
                        HStack(spacing: 5) {
                            Text("\(meters) m · \(max(1, Int((Double(meters) / 80).rounded()))) min")
                            Image(systemName: "figure.walk")
                        }
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.vertical, 12)
                ForEach(nearby.rows) { row in
                    Divider().overlay(Theme.separator)
                    DepartureRow(row: row)
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .frostedCard(cornerRadius: Theme.Radius.card)
        }
    }
}
