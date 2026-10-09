import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import TipKit
import KlimaCore

/// Fahrten (Tab 2): ticket-year summary, filter chips and the trip history grouped by month.
///
/// Motion (docs/MOTION.md): the summary value counts in once and every figure rolls; filter chips are glass that morphs;
/// rows dip under the finger and zoom into the detail; inserts, deletes and filter results animate as one list diff;
/// a trip that was just logged glows once in its row. Swipe left: Löschen (with "Rückgängig") · Bearbeiten; swipe right:
/// Nochmal · Favorit (KBTips.TripSwipe explains it once); long press: preview card + all actions.
/// A journey ("Reise mit Etappen", docs/JOURNEYS.md) is one row; a tap unfolds its legs and "Reise ansehen".
struct TripsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date, order: .reverse)
    private var trips: [TripEntity]
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }, sort: \TicketEntity.startDate, order: .reverse)
    private var tickets: [TicketEntity]
    @Query(filter: #Predicate<FavoriteRouteEntity> { $0.deletedAt == nil }, sort: \FavoriteRouteEntity.sortIndex)
    private var favorites: [FavoriteRouteEntity]

    @State private var path: [TripListRoute] = []
    /// The trimmed search text the list follows – debounced by TripListSearchField, which owns the live text.
    @State private var query = ""
    @State private var searchResetToken = 0
    @State private var modeFilter: TransportMode?
    @State private var categoryFilter: MetaTripFilter = .all
    @State private var scopeSelection: TripListScope?
    @State private var contentCache = TripListContentCache()
    @State private var selectionTick = 0
    /// Per mode: bumps when its chip gets selected (only that chip's symbol bounces).
    @State private var modeBounces: [TransportMode: Int] = [:]
    /// The trip that was just logged (sheet, "Nochmal", "Duplizieren"): its row glows once.
    @State private var freshTripID: UUID?
    /// KBTips.TripSwipe is eligible (TipKit decides; never in screenshot runs).
    @State private var showsSwipeTip = false
    /// Journeys whose legs are unfolded (row ids).  // MARK: trips
    @State private var expandedJourneys: Set<UUID> = []
    @State private var expandTick = 0

    var body: some View {
        let content = makeContent()
        NavigationStack(path: $path) {
            tripList(content)
                .navigationTitle("Fahrten")
                .navigationBarTitleDisplayMode(.large)
                .modifier(TripListSearchField(query: $query, resetToken: searchResetToken))
                .toolbar { toolbarContent }
                .navigationDestination(for: TripListRoute.self) { route in
                    destination(for: route)
                }
        }
        .zoomTransitionScope()
        .haptic(.selection, trigger: selectionTick)
        .haptic(.tap, trigger: expandTick)
        .onChange(of: trips.count) { oldCount, newCount in
            markFreshTrip(oldCount: oldCount, newCount: newCount)
        }
        .task {
            for await shouldDisplay in KBTips.TripSwipe().shouldDisplayUpdates {
                if shouldDisplay != showsSwipeTip { withMotion(Motion.smooth) { showsSwipeTip = shouldDisplay } }
            }
        }
        .task {
            // CI screenshot "tripsJourney": the demo journey unfolded.
            guard LaunchMode.screenshotScreen == "tripsJourney" else { return }
            try? await Task.sleep(for: .milliseconds(300))
            if let journey = TripListItem.group(trips).first(where: \.isJourney) { expandedJourneys.insert(journey.id) }
        }
    }

    // MARK: List

    private func tripList(_ content: TripListContent) -> some View {
        List {
            if !trips.isEmpty {
                headerSection(content)
                ForEach(content.months) { month in
                    monthSection(month)
                }
            }
        }
        .accessibilityIdentifier("perf.scroll.trips") // MARK: perf – KlimaBilanzPerfTests
        .listStyle(.insetGrouped)
        .listSectionSpacing(Theme.Spacing.m)
        .scrollContentBackground(.hidden)
        // A trip saved in the sheet, a sync or an undo: the rows slide into place instead of popping.
        .motionAnimation(Motion.smooth, value: trips.count)
        .ambientBackground()
        .overlay {
            if trips.isEmpty { emptyState }
        }
    }

    /// Summary, filters, tip and the "nothing here" states as the *header* of a section without rows: an inset-grouped
    /// section draws its rounded card behind every row – also behind clear rows, which showed as a grey band around
    /// the chips and the card's shadow. A header has no background, so the glass and the shadows sit on the sky.
    private func headerSection(_ content: TripListContent) -> some View {
        Section {
        } header: {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                TripListSummaryCard(content: content, tickets: tickets, scope: scopeBinding)
                if showsFilterRow(content) {
                    filterRow(content.modeOptions, counts: content.purposeCounts)
                }
                if showsSwipeTip && !content.months.isEmpty {
                    TipView(KBTips.TripSwipe())
                        .kbTipStyle()
                        .motionTransition(.rise)
                }
                if content.periodTrips.isEmpty {
                    emptyPeriodState(content)
                        .motionTransition(.rise)
                } else if content.months.isEmpty {
                    noResultsState(content)
                        .motionTransition(.rise)
                }
            }
            .textCase(nil)
            .padding(.bottom, Theme.Spacing.xxs)
            .listRowInsets(EdgeInsets(top: Theme.Spacing.xxs, leading: 0, bottom: Theme.Spacing.xs, trailing: 0))
        }
    }

    private func showsFilterRow(_ content: TripListContent) -> Bool {
        content.modeOptions.count > 1 || modeFilter != nil || content.purposeCounts.hasPurposes || categoryFilter.isActive
    }

    /// "✕ · Kategorie ⌄ | Alle · Zug · Bus …" – glass capsules in one container: chips that come and go (the reset chip
    /// while a filter is on, modes of another ticket year) melt in and out instead of popping.
    private func filterRow(_ options: [TransportMode], counts: MetaTripFilterCounts) -> some View {
        let isFiltered = modeFilter != nil || categoryFilter.isActive
        return ScrollView(.horizontal) {
            GlassMorphGroup(spacing: Theme.Spacing.xs) { glass in
                HStack(spacing: Theme.Spacing.xs) {
                    if isFiltered {
                        Button {
                            resetFilters()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Theme.textPrimary)
                                .frame(width: 38, height: 38)
                                .contentShape(.circle)
                        }
                        .buttonStyle(.plain)
                        .morphingGlass(in: .circle, id: "reset", namespace: glass)
                        .accessibilityLabel("Filter zurücksetzen")
                    }
                    if counts.hasPurposes || categoryFilter.isActive {
                        MetaCategoryFilterMenu(selection: categoryFilterBinding, counts: counts, glassNamespace: glass)
                        Capsule()
                            .fill(Theme.separator)
                            .frame(width: 1, height: 22)
                            .padding(.horizontal, 2)
                            .accessibilityHidden(true)
                    }
                    TripListFilterChip(title: "Alle", isSelected: modeFilter == nil, id: "all", namespace: glass) {
                        selectMode(nil)
                    }
                    ForEach(options) { mode in
                        TripListFilterChip(title: mode.displayName, symbol: mode.symbolName, isSelected: modeFilter == mode,
                                           bounce: modeBounces[mode] ?? 0, id: mode.rawValue, namespace: glass) {
                            selectMode(modeFilter == mode ? nil : mode)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Nach Kategorie und Verkehrsmittel filtern")
    }

    private func monthSection(_ month: TripListMonth) -> some View {
        Section {
            ForEach(month.items) { item in
                if item.isJourney {
                    journeyRows(item)
                } else {
                    row(for: item.first)
                }
            }
        } header: {
            TripListMonthHeader(month: month)
        }
    }

    // MARK: trips – a journey: one row, its legs and "Reise ansehen" unfold below it

    @ViewBuilder
    private func journeyRows(_ item: TripListItem) -> some View {
        let isExpanded = expandedJourneys.contains(item.id)
        Button {
            toggle(item)
        } label: {
            TripListJourneyRow(item: item, isExpanded: isExpanded)
        }
        .buttonStyle(.pressableCard)
        .zoomSource(id: item.id, cornerRadius: Theme.Radius.chip)
        .listRowBackground(TripListCardBackground(isHighlighted: item.id == freshTripID))
        .listRowSeparatorTint(Theme.separator)
        .listRowSeparator(isExpanded ? .hidden : .automatic, edges: .bottom)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteJourney(item, viaSwipe: true)
            } label: {
                Label("Löschen", systemImage: "trash")
            }
            Button {
                swipeUsed()
                actions.edit(item.first)
            } label: {
                Label("Bearbeiten", systemImage: "pencil")
            }
            .tint(Theme.dusk)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                swipeUsed()
                withMotion(Motion.smooth) { actions.repeatJourneyToday(item.legs) }
            } label: {
                Label("Nochmal", systemImage: "arrow.clockwise")
            }
            .tint(Theme.accent)
            Button {
                swipeUsed()
                actions.addFavorite(journey: item.legs, favorites: favorites)
            } label: {
                Label("Vorlage", systemImage: "star.fill")
            }
            .tint(Theme.gold)
        }
        .contextMenu {
            journeyContextMenu(item)
        } preview: {
            TripListJourneyPreviewCard(item: item)
        }
        if isExpanded {
            ForEach(Array(item.legs.enumerated()), id: \.element.id) { index, leg in
                Button {
                    path.append(.trip(leg))
                } label: {
                    TripListJourneyLegRow(leg: leg, index: index, count: item.legs.count)
                }
                .buttonStyle(.pressableCard)
                .zoomSource(id: leg.id, cornerRadius: Theme.Radius.chip)
                .listRowBackground(TripListCardBackground())
                .listRowSeparator(.hidden)
            }
            Button {
                path.append(.journey(item.id))
            } label: {
                TripListJourneyDetailLinkRow(item: item)
            }
            .buttonStyle(.pressableCard)
            .listRowBackground(TripListCardBackground())
            .listRowSeparator(.hidden, edges: .top)
            .listRowSeparatorTint(Theme.separator)
        }
    }

    @ViewBuilder
    private func journeyContextMenu(_ item: TripListItem) -> some View {
        Button { path.append(.journey(item.id)) } label: { Label("Reise ansehen", systemImage: "point.3.connected.trianglepath.dotted") }
        Button { actions.edit(item.first) } label: { Label("Bearbeiten", systemImage: "pencil") }
        Button { withMotion(Motion.smooth) { actions.repeatJourneyToday(item.legs) } } label: {
            Label("Heute nochmal fahren", systemImage: "arrow.clockwise")
        }
        Button { withMotion(Motion.smooth) { actions.duplicateJourney(item.legs) } } label: {
            Label("Duplizieren", systemImage: "plus.square.on.square")
        }
        Button { actions.addFavorite(journey: item.legs, favorites: favorites) } label: {
            Label("Als Kombi-Vorlage speichern", systemImage: "star")
        }
        MetaTripPurposeMenu(trip: item.first) { category, isInduced in
            withMotion(Motion.snappy) { actions.setPurpose(journey: item.legs, category: category, isInduced: isInduced) }
            selectionTick += 1
        }
        Divider()
        Button(role: .destructive) { deleteJourney(item, viaSwipe: false) } label: { Label("Reise löschen", systemImage: "trash") }
    }

    private func toggle(_ item: TripListItem) {
        withMotion(Motion.smooth) {
            if expandedJourneys.contains(item.id) { expandedJourneys.remove(item.id) } else { expandedJourneys.insert(item.id) }
        }
        expandTick += 1
    }

    private func deleteJourney(_ item: TripListItem, viaSwipe: Bool) {
        if viaSwipe { swipeUsed() }
        withMotion(Motion.smooth) {
            expandedJourneys.remove(item.id)
            actions.deleteJourney(item.legs)
        }
    }

    private func row(for trip: TripEntity) -> some View {
        Button {
            path.append(.trip(trip))
        } label: {
            TripListRow(trip: trip)
        }
        .buttonStyle(.pressableCard)
        .zoomSource(id: trip.id, cornerRadius: Theme.Radius.chip)
        .listRowBackground(TripListCardBackground(isHighlighted: trip.id == freshTripID))
        .listRowSeparatorTint(Theme.separator)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                delete(trip, viaSwipe: true)
            } label: {
                Label("Löschen", systemImage: "trash")
            }
            Button {
                swipeUsed()
                actions.edit(trip)
            } label: {
                Label("Bearbeiten", systemImage: "pencil")
            }
            .tint(Theme.dusk)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                swipeUsed()
                repeatToday(trip)
            } label: {
                Label("Nochmal", systemImage: "arrow.clockwise")
            }
            .tint(Theme.accent)
            Button {
                swipeUsed()
                favorite(trip)
            } label: {
                Label("Favorit", systemImage: "star.fill")
            }
            .tint(Theme.gold)
        }
        .contextMenu {
            contextMenu(for: trip)
        } preview: {
            TripListPreviewCard(trip: trip)
        }
    }

    @ViewBuilder
    private func contextMenu(for trip: TripEntity) -> some View {
        Button { actions.edit(trip) } label: { Label("Bearbeiten", systemImage: "pencil") }
        Button { repeatToday(trip) } label: { Label("Heute nochmal fahren", systemImage: "arrow.clockwise") }
        Button { duplicate(trip) } label: { Label("Duplizieren", systemImage: "plus.square.on.square") }
        Button { favorite(trip) } label: { Label("Als Favorit speichern", systemImage: "star") }
        MetaTripPurposeMenu(trip: trip) { category, isInduced in
            setPurpose(trip, category: category, isInduced: isInduced)
        }
        Divider()
        Button(role: .destructive) { delete(trip, viaSwipe: false) } label: { Label("Löschen", systemImage: "trash") }
    }

    private func noResultsState(_ content: TripListContent) -> some View {
        ContentUnavailableView {
            Label("Keine Fahrten gefunden", systemImage: "magnifyingglass")
                .foregroundStyle(Theme.textPrimary)
        } description: {
            Text(noResultsMessage(content))
                .foregroundStyle(Theme.textSecondary)
        } actions: {
            Button("Filter zurücksetzen") { resetFilters() }
                .buttonStyle(.glass)
        }
    }

    /// The selected ticket year has no trips yet (e.g. a fresh follow-up ticket) while older trips exist.
    private func emptyPeriodState(_ content: TripListContent) -> some View {
        let lead: String = content.scopeTicket.map { "Im \(TripListFormat.periodLabel($0))" } ?? "In diesem Zeitraum"
        let message = "\(lead) hast du noch keine Fahrt erfasst. Deine \(TripListFormat.tripCount(content.allTripCount)) findest du unter „Alle Fahrten“."
        return ContentUnavailableView {
            Label("Noch keine Fahrten", systemImage: "tram.fill")
                .foregroundStyle(Theme.textPrimary)
        } description: {
            Text(message)
                .foregroundStyle(Theme.textSecondary)
        } actions: {
            Button("Fahrt erfassen") { app.presentAddTrip() }
                .buttonStyle(.glassProminent)
            Button("Alle Fahrten anzeigen") { scopeBinding.wrappedValue = .all }
                .buttonStyle(.glass)
        }
    }

    private var emptyState: some View {
        EmptyStateView(symbol: "tram.fill",
                       title: "Noch keine Fahrten",
                       message: "Erfasse deine erste Fahrt – KlimaBilanz rechnet aus, was sie ohne KlimaTicket gekostet hätte.",
                       actionTitle: "Erste Fahrt erfassen") {
            app.presentAddTrip()
        }
        .padding(.horizontal, Theme.Spacing.screen)
    }

    // MARK: Toolbar & navigation

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Button {
                    path.append(.favorites)
                } label: {
                    Label("Favoriten verwalten", systemImage: "star")
                }
                if !trips.isEmpty {
                    ShareLink(item: TripsCSVExport(container: context.container),
                              subject: Text("KlimaBilanz – Fahrten"), message: Text("Meine Fahrten als CSV-Datei"),
                              preview: SharePreview("KlimaBilanz – Fahrten")) {
                        Label("CSV exportieren", systemImage: "tablecells")
                    }
                }
            } label: {
                Label("Mehr", systemImage: "ellipsis")
            }
            Button {
                app.presentAddTrip()
            } label: {
                Label("Fahrt erfassen", systemImage: "plus")
            }
        }
    }

    @ViewBuilder
    private func destination(for route: TripListRoute) -> some View {
        switch route {
        case .trip(let trip):
            TripDetailView(trip: trip, openJourney: { id in path.append(.journey(id)) })   // MARK: trips
                .zoomDestination(id: trip.id)
        case .journey(let id):   // MARK: trips
            TripJourneyDetailView(journeyID: id) { leg in path.append(.trip(leg)) }
                .zoomDestination(id: id)
        case .favorites:
            FavoritesManagerView()
        }
    }

    // MARK: Derived content

    /// Served from `contentCache` while nothing it depends on changed – haptic ticks, sheets and other re-renders
    /// cost one pass over the trips' `updatedAt` instead of filtering, grouping and the amortisation.
    private func makeContent() -> TripListContent {
        let scope = resolvedScope
        let key = TripListContentCache.Key(
            trips: TripListFingerprint(trips),
            tickets: TripListFingerprint(tickets),
            scope: scope,
            query: query,
            mode: modeFilter,
            purpose: categoryFilter,
            day: TripListFormat.calendar.startOfDay(for: Date()),
            kilometergeld: app.catalog.kilometergeldEUR,
            emissions: app.catalog.emissions)
        return contentCache.content(for: key) { buildContent(scope: scope) }
    }

    private func buildContent(scope: TripListScope) -> TripListContent {
        var scopeTicket: TicketEntity?
        if case .ticket(let id) = scope {
            scopeTicket = tickets.first { $0.id == id }
        }

        let periodTrips: [TripEntity]
        if let scopeTicket {
            let period = scopeTicket.period
            periodTrips = trips.filter { period.contains($0.date) }
        } else {
            periodTrips = trips
        }

        let tokens = TripSearchIndex.tokens(query)
        let mode = modeFilter
        let purpose = categoryFilter
        let isFiltered = mode != nil || purpose.isActive || !tokens.isEmpty
        let index = contentCache.searchIndex
        // MARK: trips – rows are trips and journeys; a journey matches when any leg has the mode and every word appears
        // in one of its legs ("Lech Wien").
        let periodItems = TripListItem.group(periodTrips)
        let visible = !isFiltered ? periodItems : periodItems.filter { item in
            (mode.map { mode in item.legs.contains { $0.mode == mode } } ?? true)
                && item.legs.contains(where: purpose.matches)
                && tokens.allSatisfy { token in item.legs.contains { index.matches($0, tokens: [token]) } }
        }
        // The amortisation only when nothing is filtered (otherwise it would mislead) – memoised by Analytics.
        let summary: SavingsSummary? = isFiltered ? nil : scopeTicket.map {
            Analytics.make(ticket: $0, trips: periodTrips, catalog: app.catalog).summary
        }

        return TripListContent(
            scope: scope,
            scopeTicket: scopeTicket,
            periodTrips: periodTrips,
            periodItemCount: periodItems.count,
            allTripCount: Set(trips.map { $0.journeyID ?? $0.id }).count,
            visibleItems: visible,
            months: TripListMonth.group(visible),
            modeOptions: modeOptions(for: periodTrips),
            summary: summary,
            stats: summary.map { TripListStats(count: $0.tripCount, distanceKm: $0.distanceKm, value: $0.totalValue) }
                ?? TripListStats(items: visible),
            // Stays visible on "Alle Fahrten" too – otherwise a single-ticket user could never switch back.
            showsScopePicker: !tickets.isEmpty && (tickets.count > 1 || scope == .all || periodTrips.count < trips.count),
            isFiltered: isFiltered,
            query: query,
            purposeCounts: MetaTripFilterCounts(trips: periodTrips)
        )
    }

    /// Modes present in the period, most used first (the active filter always stays selectable).
    private func modeOptions(for periodTrips: [TripEntity]) -> [TransportMode] {
        var counts: [TransportMode: Int] = [:]
        for trip in periodTrips { counts[trip.mode, default: 0] += 1 }
        let order = TransportMode.allCases
        var options = order.filter { counts[$0] != nil }.sorted { lhs, rhs in
            let left = counts[lhs] ?? 0
            let right = counts[rhs] ?? 0
            if left != right { return left > right }
            return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
        }
        if let modeFilter, !options.contains(modeFilter) { options.append(modeFilter) }
        return options
    }

    /// User choice → otherwise the active ticket (selection → valid today → latest) → otherwise all trips.
    private var resolvedScope: TripListScope {
        switch scopeSelection {
        case .some(.all):
            return .all
        case .some(.ticket(let id)) where tickets.contains(where: { $0.id == id }):
            return .ticket(id)
        default:
            if let active = Analytics.activeTicket(in: tickets, selectedID: app.settings.selectedTicketID) {
                return .ticket(active.id)
            }
            return .all
        }
    }

    private var scopeBinding: Binding<TripListScope> {
        Binding(
            get: { resolvedScope },
            set: { newValue in
                withMotion(Motion.smooth) { scopeSelection = newValue }
                selectionTick += 1
            }
        )
    }

    private func noResultsMessage(_ content: TripListContent) -> String {
        let modeText = (modeFilter.map { " mit \($0.displayName)" } ?? "") + categoryFilter.resultPhrase
        if !content.query.isEmpty {
            return "Für „\(content.query)“ gibt es keine Fahrt\(modeText) in diesem Zeitraum."
        }
        return "In diesem Zeitraum gibt es keine Fahrten\(modeText)."
    }

    // MARK: Actions

    private var actions: TripListActions { TripListActions(app: app, context: context) }

    private func selectMode(_ mode: TransportMode?) {
        guard mode != modeFilter else { return }
        if let mode { modeBounces[mode, default: 0] += 1 }
        withMotion(Motion.snappy) { modeFilter = mode }
        selectionTick += 1
    }

    private func resetFilters() {
        withMotion(Motion.smooth) {
            query = ""
            modeFilter = nil
            categoryFilter = .all
        }
        searchResetToken += 1
        selectionTick += 1
    }

    private var categoryFilterBinding: Binding<MetaTripFilter> {
        Binding(
            get: { categoryFilter },
            set: { newValue in
                guard newValue != categoryFilter else { return }
                withMotion(Motion.snappy) { categoryFilter = newValue }
                selectionTick += 1
            }
        )
    }

    private func setPurpose(_ trip: TripEntity, category: TripCategory?, isInduced: Bool) {
        withMotion(Motion.snappy) {
            Repository(context: context, app: app).metaSetPurpose(trip, category: category, isInduced: isInduced)
        }
        selectionTick += 1
    }

    // The toasts these actions show play their haptic (success, or warning for "gelöscht") – none here (MOTION.md §6).

    private func delete(_ trip: TripEntity, viaSwipe: Bool) {
        if viaSwipe { swipeUsed() }
        withMotion(Motion.smooth) { actions.delete(trip) }
    }

    private func repeatToday(_ trip: TripEntity) {
        withMotion(Motion.smooth) { actions.repeatToday(trip) }
    }

    private func duplicate(_ trip: TripEntity) {
        withMotion(Motion.smooth) { actions.duplicate(trip) }
    }

    private func favorite(_ trip: TripEntity) {
        actions.addFavorite(trip, favorites: favorites)
    }

    /// A swipe action was used: the swipe tip has done its job.
    private func swipeUsed() {
        KBTips.used(KBTips.TripSwipe())
    }

    /// A new trip (count went up, created moments ago – not an undo or a sync of old trips) glows once in its row.
    private func markFreshTrip(oldCount: Int, newCount: Int) {
        guard newCount > oldCount, !MotionPolicy.isStatic,
              let newest = trips.max(by: { $0.createdAt < $1.createdAt }),
              Date().timeIntervalSince(newest.createdAt) < 8 else { return }
        let id = newest.journeyID ?? newest.id   // MARK: trips – a journey's row glows as a whole
        freshTripID = id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            guard freshTripID == id else { return }
            withMotion(Motion.gentle) { freshTripID = nil }
        }
    }
}

// MARK: - Filter chip

/// Mode chip of the filter row: interactive glass that morphs with its neighbours (GlassMorphGroup), tinted while
/// selected; the symbol bounces when the chip is picked.
private struct TripListFilterChip: View {
    let title: String
    var symbol: String? = nil
    let isSelected: Bool
    var bounce: Int = 0
    let id: String
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.subheadline.weight(.semibold))
                        .symbolBounce(on: bounce)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? Theme.accentText : Theme.textPrimary)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .morphingGlass(isSelected ? .regular.tint(Theme.accentText.opacity(0.22)).interactive() : .regular.interactive(),
                       in: .capsule, id: id, namespace: namespace)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Search field

/// The search field owns the live text, so a keystroke re-renders only this modifier. The list follows the trimmed text
/// once typing pauses (150 ms) – right away when the field is cleared. `resetToken` empties the field ("Filter zurücksetzen").
private struct TripListSearchField: ViewModifier {
    @Binding var query: String
    var resetToken: Int

    @State private var text = ""

    func body(content: Content) -> some View {
        content
            .searchable(text: $text, prompt: Text("Bahnhof, Notiz oder Kategorie"))
            .task(id: text) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && trimmed != query {
                    try? await Task.sleep(for: .milliseconds(150))
                    if Task.isCancelled { return }
                }
                // The results slide into place (one list diff) instead of jumping.
                if query != trimmed { withMotion(Motion.snappy) { query = trimmed } }
            }
            .onChange(of: resetToken) { _, _ in text = "" }
    }
}

// MARK: - CSV export

/// "CSV exportieren" (same file as Einstellungen › Daten: CSV v2 with notes). Built only when the share sheet asks for
/// it – from a background context, off the main actor – instead of after every change while the list is open.
struct TripsCSVExport: Transferable {
    let container: ModelContainer

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            let url = try await Task.detached(priority: .userInitiated) { try export.writeFile() }.value
            return SentTransferredFile(url)
        }
    }

    private func writeFile() throws -> URL {
        let context = ModelContext(container)
        let trips = try context.fetch(FetchDescriptor<TripEntity>(predicate: #Predicate { $0.deletedAt == nil }))
        var notes: [UUID: String] = [:]
        for trip in trips where !trip.note.isEmpty { notes[trip.id] = trip.note }
        let data = Data(TripCSVExport.trips(trips.map(\.record), notes: notes).utf8)
        let day = Calendar.vienna.dateComponents([.year, .month, .day], from: Date())
        let name = String(format: "KlimaBilanz-%04d-%02d-%02d-Fahrten.csv", day.year ?? 0, day.month ?? 0, day.day ?? 0)
        let url = FileManager.default.temporaryDirectory.appending(path: name)
        try data.write(to: url, options: .atomic)
        return url
    }
}

// MARK: - Model types

private enum TripListScope: Hashable {
    case all
    case ticket(UUID)
}

private enum TripListRoute: Hashable {
    case trip(TripEntity)
    /// MARK: trips – the journey detail (docs/JOURNEYS.md)
    case journey(UUID)
    case favorites
}

/// One month section of the list (rows arrive sorted newest first; a journey is one row).
private struct TripListMonth: Identifiable {
    let id: Date
    var items: [TripListItem]

    var value: Double { items.reduce(0) { $0 + $1.totalValue } }

    /// "Oktober 2026" – formatted mid-month so time-zone offsets never shift it into the previous month.
    var title: String { Format.monthYear(id.addingTimeInterval(14 * 86_400)) }

    static func group(_ items: [TripListItem]) -> [TripListMonth] {
        let calendar = Calendar.vienna
        var result: [TripListMonth] = []
        for item in items {
            let month = calendar.date(from: calendar.dateComponents([.year, .month], from: item.date)) ?? item.date
            if let last = result.indices.last, result[last].id == month {
                result[last].items.append(item)
            } else {
                result.append(TripListMonth(id: month, items: [item]))
            }
        }
        return result
    }
}

/// Everything the list renders (cached in TripListContentCache).
private struct TripListContent {
    var scope: TripListScope
    var scopeTicket: TicketEntity?
    var periodTrips: [TripEntity]
    /// Rows of the period (a journey counts once) and of every ticket year.  // MARK: trips
    var periodItemCount: Int
    var allTripCount: Int
    var visibleItems: [TripListItem]
    var months: [TripListMonth]
    var modeOptions: [TransportMode]
    /// Amortisation of the scope ticket – nil while filtering (it would mislead) and for "Alle Fahrten".
    var summary: SavingsSummary?
    /// Fahrten / km / value of the card: the ticket year's summary, or what the filter shows.
    var stats: TripListStats
    var showsScopePicker: Bool
    var isFiltered: Bool
    var query: String
    var purposeCounts: MetaTripFilterCounts
}

private struct TripListStats {
    var count: Int
    var distanceKm: Double
    var value: Double

    init(count: Int, distanceKm: Double, value: Double) {
        self.count = count
        self.distanceKm = distanceKm
        self.value = value
    }

    /// What the filter shows: a journey is one "Fahrt", its legs add km and value.
    init(items: [TripListItem]) {
        var distance = 0.0, value = 0.0
        for item in items {
            distance += item.totalDistanceKm
            value += item.totalValue
        }
        self.init(count: items.count, distanceKm: distance, value: value)
    }
}

/// Count + hash of the rows' `updatedAt` in query order: every edit stamps `updatedAt` (`touch()`, the invariant sync
/// and AnalyticsMemo rely on too), inserts and deletes change the count, a new date changes the order.
private struct TripListFingerprint: Equatable {
    var count: Int
    var hash: Int

    init(_ trips: [TripEntity]) {
        var hasher = Hasher()
        for trip in trips { hasher.combine(trip.updatedAt) }
        count = trips.count
        hash = hasher.finalize()
    }

    init(_ tickets: [TicketEntity]) {
        var hasher = Hasher()
        for ticket in tickets {
            hasher.combine(ticket.id)
            hasher.combine(ticket.updatedAt)
        }
        count = tickets.count
        hash = hasher.finalize()
    }
}

/// Last list content and the inputs it was built from (a plain reference in @State: reading or refilling it never
/// triggers a re-render). Also owns the search keys, which outlive single queries.
@MainActor
private final class TripListContentCache {
    struct Key: Equatable {
        var trips: TripListFingerprint
        var tickets: TripListFingerprint
        var scope: TripListScope
        var query: String
        var mode: TransportMode?
        var purpose: MetaTripFilter
        var day: Date
        var kilometergeld: Double
        var emissions: EmissionFactors
    }

    let searchIndex = TripSearchIndex()
    private var key: Key?
    private var value: TripListContent?

    func content(for key: Key, build: () -> TripListContent) -> TripListContent {
        if let value, self.key == key { return value }
        let built = build()
        self.key = key
        value = built
        return built
    }
}

// MARK: - Summary card

/// "TICKETJAHR 2026/27 ⌄" · big value numeral · route-gradient rail to the summit · Fahrten / km / Ø.
/// The numeral counts in once (the screen's one hero value), the rail draws to its position once; after that every
/// figure rolls to its new value (filters, scope, a new trip).
private struct TripListSummaryCard: View {
    let content: TripListContent
    let tickets: [TicketEntity]
    @Binding var scope: TripListScope

    /// 0 → 1 once on first appearance: the rail grows from the start to today's progress.
    @State private var railShown: Double = MotionPolicy.isStatic ? 1 : 0

    var body: some View {
        GlassCard(padding: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                topRow
                valueBlock
                if let summary = amortization {
                    rail(summary)
                }
                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: 1)
                    .padding(.vertical, 2)
                statsRow
            }
        }
        .onAppear {
            guard railShown < 1 else { return }
            withMotion(Motion.gentle.delay(0.12)) { railShown = 1 }
        }
    }

    // MARK: Pieces

    private var topRow: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xs) {
            if content.showsScopePicker {
                scopeMenu
            } else {
                Kicker(text: scopeTitle)
            }
            Spacer(minLength: Theme.Spacing.xs)
            if let summary = amortization {
                statusPill(summary)
            }
        }
    }

    private var scopeMenu: some View {
        Menu {
            Picker("Zeitraum", selection: $scope) {
                Text("Alle Fahrten").tag(TripListScope.all)
                ForEach(tickets) { ticket in
                    Text(TripListFormat.periodTitle(ticket, among: tickets))
                        .tag(TripListScope.ticket(ticket.id))
                }
            }
        } label: {
            HStack(spacing: 5) {
                Kicker(text: scopeTitle, color: Theme.accentText)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.accentText)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .accessibilityLabel("Zeitraum")
        .accessibilityValue(scopeTitle)
    }

    private func statusPill(_ summary: SavingsSummary) -> some View {
        let title: String = summary.isPaidOff ? "Rentiert" : Format.percent(summary.amortizedFraction)
        let spokenLabel: String = summary.isPaidOff ? "Ticket hat sich rentiert" : "Amortisiert"
        let fill: Color = summary.isPaidOff ? Theme.positive.opacity(0.16) : Theme.surfaceSecondary
        return HStack(spacing: 4) {
            Image(systemName: summary.isPaidOff ? "checkmark.seal.fill" : "mountain.2.fill")
                .symbolReplaceTransition()
            Text(title)
                .monospacedDigit()
                .numericValue(summary.amortizedFraction)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(summary.isPaidOff ? Theme.positiveText : Theme.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(fill, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityValue(Format.percent(summary.amortizedFraction))
    }

    private var valueBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("€")
                    .font(.system(.title2, design: .rounded, weight: .light))
                    .foregroundStyle(Theme.textSecondary)
                CountUpText(value: shownValue) { Format.number($0) }
                    .font(Theme.Typography.priceNumeral)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text(subline)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wert der Fahrten")
        .accessibilityValue("\(Format.euro(stats.value)), \(subline)")
    }

    private func rail(_ summary: SavingsSummary) -> some View {
        ProgressRail(progress: summary.progressClamped * railShown,
                     leadingLabel: summary.isPaidOff
                        ? "+ \(SummitFigures.euro(summary.shownProfitEuro)) im Plus"
                        : "Noch \(SummitFigures.euro(summary.shownRemainingEuro)) bis zum Gipfel",
                     trailingLabel: "Gipfel \(SummitFigures.euro(summary.ticketPrice.rounded()))",
                     height: 8)
            .padding(.top, Theme.Spacing.xxs)
            .accessibilityLabel("Fortschritt bis zum Break-even")
    }

    private var statsRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                countStat
                Spacer(minLength: 0)
                distanceStat
                Spacer(minLength: 0)
                averageStat
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                countStat
                distanceStat
                averageStat
            }
        }
    }

    private var countStat: some View {
        miniStat(value: Format.number(Double(stats.count)), numeric: Double(stats.count), unit: nil,
                 label: stats.count == 1 ? "Fahrt" : "Fahrten", symbol: "train.side.front.car", color: Theme.accent)
    }

    private var distanceStat: some View {
        miniStat(value: Format.number(stats.distanceKm), numeric: stats.distanceKm.rounded(), unit: "km",
                 label: "Strecke", symbol: "point.topleft.down.to.point.bottomright.curvepath", color: Theme.accentSecondary)
    }

    private var averageStat: some View {
        let average = stats.count > 0 ? stats.value / Double(stats.count) : 0
        return miniStat(value: stats.count > 0 ? Format.euroPrecise(average) : "–", numeric: average, unit: nil,
                 label: "Ø pro Fahrt", symbol: "eurosign", color: Theme.summit)
    }

    private func miniStat(value: String, numeric: Double, unit: String?, label: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(Theme.Typography.numberSmall)
                    .foregroundStyle(Theme.textPrimary)
                    .numericValue(numeric)
                if let unit {
                    Text(unit)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    // MARK: Derived

    /// Amortisation of the selected ticket – only when the list is not filtered (otherwise it would mislead).
    private var amortization: SavingsSummary? { content.summary }

    private var stats: TripListStats { content.stats }

    /// The big numeral in whole euros – never the summit before it is reached (SummitFigures, as on the dashboard).
    private var shownValue: Double {
        guard let summary = amortization else { return stats.value.rounded() }
        return SummitFigures.shownTotal(value: summary.totalValue, price: summary.ticketPrice, isPaidOff: summary.isPaidOff)
    }

    private var scopeTitle: String {
        switch content.scope {
        case .all: return "Alle Fahrten"
        case .ticket: return content.scopeTicket.map { TripListFormat.periodLabel($0) } ?? "Ticketjahr"
        }
    }

    private var subline: String {
        if content.isFiltered {
            return "\(Format.number(Double(content.visibleItems.count))) von \(TripListFormat.tripCount(content.periodItemCount)) · gefiltert"
        }
        if let ticket = content.scopeTicket {
            // The summit is the own share (price + add-ons − employer contribution) – name it when it differs.
            let share = ticket.ownShare
            if abs(share - ticket.price) >= 0.005 { return "Normalpreis-Wert · Eigenanteil \(Format.euro(share))" }
            return "Normalpreis-Wert · Ticket \(Format.euro(ticket.price))"
        }
        return "Normalpreis-Wert aller Fahrten"
    }
}

// MARK: - Month header

/// "Oktober 2026 ··· 12 Fahrten  € 186"
private struct TripListMonthHeader: View {
    let month: TripListMonth

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Text(month.title)
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: Theme.Spacing.xs)
            Text(TripListFormat.tripCount(month.items.count))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .numericValue(Double(month.items.count))
            Text(Format.euro(month.value, decimals: 0))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .numericValue(month.value.rounded())
        }
        .textCase(nil)
        .padding(.top, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
