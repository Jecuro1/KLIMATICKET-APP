import SwiftUI
import SwiftData
import KlimaCore

/// Fahrten (Tab 2): ticket-year summary, search, mode chips and the trip history grouped by month.
struct TripsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date, order: .reverse)
    private var trips: [TripEntity]
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }, sort: \TicketEntity.startDate, order: .reverse)
    private var tickets: [TicketEntity]
    @Query(filter: #Predicate<FavoriteRouteEntity> { $0.deletedAt == nil }, sort: \FavoriteRouteEntity.sortIndex)
    private var favorites: [FavoriteRouteEntity]

    @State private var path: [TripListRoute] = []
    @State private var searchText = ""
    @State private var modeFilter: TransportMode?
    @State private var categoryFilter: MetaTripFilter = .all
    @State private var scopeSelection: TripListScope?
    @State private var csvURL: URL?
    @State private var successTick = 0
    @State private var warningTick = 0
    @State private var selectionTick = 0
    @Namespace private var zoomNamespace

    var body: some View {
        let content = makeContent()
        NavigationStack(path: $path) {
            tripList(content)
                .navigationTitle("Fahrten")
                .navigationBarTitleDisplayMode(.large)
                .searchable(text: $searchText, prompt: Text("Bahnhof, Notiz oder Kategorie"))
                .toolbar { toolbarContent }
                .navigationDestination(for: TripListRoute.self) { route in
                    destination(for: route)
                }
        }
        .task(id: csvStamp) { prepareCSV() }
        .sensoryFeedback(.success, trigger: successTick, condition: { _, _ in hapticsEnabled })
        .sensoryFeedback(.warning, trigger: warningTick, condition: { _, _ in hapticsEnabled })
        .sensoryFeedback(.selection, trigger: selectionTick, condition: { _, _ in hapticsEnabled })
    }

    // MARK: List

    private func tripList(_ content: TripListContent) -> some View {
        List {
            if !trips.isEmpty {
                headerSection(content)
                if content.periodTrips.isEmpty {
                    emptyPeriodSection(content)
                } else if content.months.isEmpty {
                    noResultsSection(content)
                } else {
                    ForEach(content.months) { month in
                        monthSection(month)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Theme.Spacing.m)
        .scrollContentBackground(.hidden)
        .ambientBackground()
        .overlay {
            if trips.isEmpty { emptyState }
        }
    }

    private func headerSection(_ content: TripListContent) -> some View {
        Section {
            TripListSummaryCard(content: content, tickets: tickets, scope: scopeBinding)
                .listRowInsets(EdgeInsets(top: Theme.Spacing.xxs, leading: 0, bottom: Theme.Spacing.xs, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            if content.modeOptions.count > 1 || modeFilter != nil || content.purposeCounts.hasPurposes || categoryFilter.isActive {
                modeChips(content.modeOptions, counts: content.purposeCounts)
                    .listRowInsets(EdgeInsets(top: Theme.Spacing.xxs, leading: 0, bottom: Theme.Spacing.xxs, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
    }

    private func modeChips(_ options: [TransportMode], counts: MetaTripFilterCounts) -> some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    if counts.hasPurposes || categoryFilter.isActive {
                        MetaCategoryFilterMenu(selection: categoryFilterBinding, counts: counts)
                        Capsule()
                            .fill(Theme.separator)
                            .frame(width: 1, height: 22)
                            .padding(.horizontal, 2)
                            .accessibilityHidden(true)
                    }
                    Chip(title: "Alle", isSelected: modeFilter == nil, tint: Theme.accentText) {
                        selectMode(nil)
                    }
                    ForEach(options) { mode in
                        Chip(title: mode.displayName, symbol: mode.symbolName, isSelected: modeFilter == mode, tint: Theme.accentText) {
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
            ForEach(month.trips) { trip in
                row(for: trip)
            }
        } header: {
            TripListMonthHeader(month: month)
        }
    }

    private func row(for trip: TripEntity) -> some View {
        Button {
            path.append(.trip(trip))
        } label: {
            TripListRow(trip: trip)
        }
        .matchedTransitionSource(id: trip.id, in: zoomNamespace)
        .listRowBackground(TripListCardBackground())
        .listRowSeparatorTint(Theme.separator)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                delete(trip)
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                repeatToday(trip)
            } label: {
                Label("Nochmal", systemImage: "arrow.clockwise")
            }
            .tint(Theme.accent)
            Button {
                favorite(trip)
            } label: {
                Label("Favorit", systemImage: "star.fill")
            }
            .tint(Theme.gold)
        }
        .contextMenu { contextMenu(for: trip) }
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
        Button(role: .destructive) { delete(trip) } label: { Label("Löschen", systemImage: "trash") }
    }

    private func noResultsSection(_ content: TripListContent) -> some View {
        Section {
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
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    /// The selected ticket year has no trips yet (e.g. a fresh follow-up ticket) while older trips exist.
    private func emptyPeriodSection(_ content: TripListContent) -> some View {
        let lead: String = content.scopeTicket.map { "Im \(TripListFormat.periodLabel($0))" } ?? "In diesem Zeitraum"
        let message = "\(lead) hast du noch keine Fahrt erfasst. Deine \(TripListFormat.tripCount(trips.count)) findest du unter „Alle Fahrten“."
        return Section {
            ContentUnavailableView {
                Label("Noch keine Fahrten", systemImage: "tram.fill")
                    .foregroundStyle(Theme.textPrimary)
            } description: {
                Text(message)
                    .foregroundStyle(Theme.textSecondary)
            } actions: {
                Button("Alle Fahrten anzeigen") { scopeBinding.wrappedValue = .all }
                    .buttonStyle(.glass)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
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
                if let csvURL {
                    ShareLink(item: csvURL, subject: Text("KlimaBilanz – Fahrten"), message: Text("Meine Fahrten als CSV-Datei")) {
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
            TripDetailView(trip: trip)
                .navigationTransition(.zoom(sourceID: trip.id, in: zoomNamespace))
        case .favorites:
            FavoritesManagerView()
        }
    }

    // MARK: Derived content

    private func makeContent() -> TripListContent {
        let scope = resolvedScope
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

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = modeFilter
        let purpose = categoryFilter
        let visible = periodTrips.filter { trip in
            (mode.map { trip.mode == $0 } ?? true) && purpose.matches(trip) && TripListFormat.matches(trip, query: query)
        }

        return TripListContent(
            scope: scope,
            scopeTicket: scopeTicket,
            periodTrips: periodTrips,
            visibleTrips: visible,
            months: TripListMonth.group(visible),
            modeOptions: modeOptions(for: periodTrips),
            snapshot: scopeTicket.map { Analytics.make(ticket: $0, trips: trips, catalog: app.catalog) },
            // Stays visible on "Alle Fahrten" too – otherwise a single-ticket user could never switch back.
            showsScopePicker: !tickets.isEmpty && (tickets.count > 1 || scope == .all || periodTrips.count < trips.count),
            isFiltered: mode != nil || purpose.isActive || !query.isEmpty,
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
                withAnimation(listAnimation) { scopeSelection = newValue }
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
    private var hapticsEnabled: Bool { app.settings.hapticsEnabled }
    /// Crossfade-free, instant list updates with Reduce Motion.
    private var listAnimation: Animation? { reduceMotion ? nil : Animation.snappy }

    private func selectMode(_ mode: TransportMode?) {
        guard mode != modeFilter else { return }
        withAnimation(listAnimation) { modeFilter = mode }
        selectionTick += 1
    }

    private func resetFilters() {
        withAnimation(listAnimation) {
            searchText = ""
            modeFilter = nil
            categoryFilter = .all
        }
        selectionTick += 1
    }

    private var categoryFilterBinding: Binding<MetaTripFilter> {
        Binding(
            get: { categoryFilter },
            set: { newValue in
                guard newValue != categoryFilter else { return }
                withAnimation(listAnimation) { categoryFilter = newValue }
                selectionTick += 1
            }
        )
    }

    private func setPurpose(_ trip: TripEntity, category: TripCategory?, isInduced: Bool) {
        withAnimation(listAnimation) {
            Repository(context: context, app: app).metaSetPurpose(trip, category: category, isInduced: isInduced)
        }
        selectionTick += 1
    }

    private func delete(_ trip: TripEntity) {
        withAnimation(listAnimation) { actions.delete(trip) }
        warningTick += 1
    }

    private func repeatToday(_ trip: TripEntity) {
        withAnimation(listAnimation) { actions.repeatToday(trip) }
        successTick += 1
    }

    private func duplicate(_ trip: TripEntity) {
        withAnimation(listAnimation) { actions.duplicate(trip) }
        successTick += 1
    }

    private func favorite(_ trip: TripEntity) {
        actions.addFavorite(trip, favorites: favorites)
        successTick += 1
    }

    // MARK: CSV export

    /// Changes whenever a trip is added, deleted or edited – regenerates the CSV file for the share sheet.
    private var csvStamp: String {
        let latest = trips.map(\.updatedAt).max() ?? .distantPast
        return "\(trips.count)-\(Int(latest.timeIntervalSince1970))"
    }

    private func prepareCSV() {
        guard !trips.isEmpty else {
            csvURL = nil
            return
        }
        do {
            let data = try Backup.csv(context: context)
            csvURL = try Backup.temporaryFile(named: "\(Backup.timestampedName)-Fahrten.csv", data: data)
        } catch {
            csvURL = nil
        }
    }
}

// MARK: - Model types

private enum TripListScope: Hashable {
    case all
    case ticket(UUID)
}

private enum TripListRoute: Hashable {
    case trip(TripEntity)
    case favorites
}

/// One month section of the list (trips arrive sorted newest first).
private struct TripListMonth: Identifiable {
    let id: Date
    var trips: [TripEntity]

    var value: Double { trips.reduce(0) { $0 + $1.totalValue } }

    /// "Oktober 2026" – formatted mid-month so time-zone offsets never shift it into the previous month.
    var title: String { Format.monthYear(id.addingTimeInterval(14 * 86_400)) }

    static func group(_ trips: [TripEntity]) -> [TripListMonth] {
        let calendar = Calendar.vienna
        var result: [TripListMonth] = []
        for trip in trips {
            let month = calendar.date(from: calendar.dateComponents([.year, .month], from: trip.date)) ?? trip.date
            if let last = result.indices.last, result[last].id == month {
                result[last].trips.append(trip)
            } else {
                result.append(TripListMonth(id: month, trips: [trip]))
            }
        }
        return result
    }
}

/// Everything the list renders, computed once per body evaluation.
private struct TripListContent {
    var scope: TripListScope
    var scopeTicket: TicketEntity?
    var periodTrips: [TripEntity]
    var visibleTrips: [TripEntity]
    var months: [TripListMonth]
    var modeOptions: [TransportMode]
    var snapshot: AnalyticsSnapshot?
    var showsScopePicker: Bool
    var isFiltered: Bool
    var query: String
    var purposeCounts: MetaTripFilterCounts
}

// MARK: - Summary card

/// "TICKETJAHR 2026/27 ⌄" · big value numeral · route-gradient rail to the summit · Fahrten / km / Ø.
private struct TripListSummaryCard: View {
    let content: TripListContent
    let tickets: [TicketEntity]
    @Binding var scope: TripListScope

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal: Double = LaunchMode.isScreenshot ? 1 : 0

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
            guard reveal < 1 else { return }
            if reduceMotion {
                reveal = 1
            } else {
                withAnimation(.smooth(duration: 1.0).delay(0.1)) { reveal = 1 }
            }
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
            Text(title)
                .monospacedDigit()
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
                Text(Format.number(stats.value))
                    .font(Theme.Typography.priceNumeral)
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText(value: stats.value))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text(subline)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(.snappy, value: stats.value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wert der Fahrten")
        .accessibilityValue("\(Format.euro(stats.value)), \(subline)")
    }

    private func rail(_ summary: SavingsSummary) -> some View {
        ProgressRail(progress: summary.progressClamped * reveal,
                     leadingLabel: summary.isPaidOff
                        ? "+ \(SummitFigures.euro(summary.shownProfitEuro)) im Plus"
                        : "Noch \(SummitFigures.euro(summary.shownRemainingEuro)) bis zum Gipfel",
                     trailingLabel: "Gipfel \(Format.euro(summary.ticketPrice))",
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
        miniStat(value: Format.number(Double(stats.count)), unit: nil,
                 label: stats.count == 1 ? "Fahrt" : "Fahrten", symbol: "train.side.front.car", color: Theme.accent)
    }

    private var distanceStat: some View {
        miniStat(value: Format.number(stats.distanceKm), unit: "km",
                 label: "Strecke", symbol: "point.topleft.down.to.point.bottomright.curvepath", color: Theme.accentSecondary)
    }

    private var averageStat: some View {
        miniStat(value: stats.count > 0 ? Format.euroPrecise(stats.value / Double(stats.count)) : "–", unit: nil,
                 label: "Ø pro Fahrt", symbol: "eurosign", color: Theme.summit)
    }

    private func miniStat(value: String, unit: String?, label: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(Theme.Typography.numberSmall)
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
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
    private var amortization: SavingsSummary? {
        content.isFiltered ? nil : content.snapshot?.summary
    }

    private var stats: (count: Int, distanceKm: Double, value: Double) {
        if !content.isFiltered, let summary = content.snapshot?.summary {
            return (summary.tripCount, summary.distanceKm, summary.totalValue)
        }
        let visible = content.visibleTrips
        return (visible.count,
                visible.reduce(0) { $0 + $1.totalDistanceKm },
                visible.reduce(0) { $0 + $1.totalValue })
    }

    private var scopeTitle: String {
        switch content.scope {
        case .all: return "Alle Fahrten"
        case .ticket: return content.scopeTicket.map { TripListFormat.periodLabel($0) } ?? "Ticketjahr"
        }
    }

    private var subline: String {
        if content.isFiltered {
            return "\(Format.number(Double(content.visibleTrips.count))) von \(TripListFormat.tripCount(content.periodTrips.count)) · gefiltert"
        }
        if let ticket = content.scopeTicket {
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
            Text(TripListFormat.tripCount(month.trips.count))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            Text(Format.euro(month.value, decimals: 0))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
        }
        .textCase(nil)
        .padding(.top, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
