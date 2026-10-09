import SwiftUI
import SwiftData
import KlimaCore

/// Opening state for screenshots / deep entry points.
enum AtlasLaunchFocus {
    case none
    /// Selects the most travelled route (route sheet open).
    case topRoute
    /// Opens the details sheet.
    case details
}

/// Sheets of the map screen. All route sheets share one identity, so tapping another route updates the open sheet
/// in place instead of dismissing and re-presenting it.
enum AtlasSheet: Identifiable, Equatable {
    case route(String)
    case details

    var id: String {
        switch self {
        case .route: "route"
        case .details: "details"
        }
    }

    var routeID: String? {
        if case .route(let id) = self { return id }
        return nil
    }
}

/// "Meine Österreich-Karte": every route of the ticket year as an arc across Austria, stations as glass dots,
/// the nine federal states, extreme points and the trips without coordinates. Filter by mode and ticket year;
/// tap a route for its trips and value.
struct AtlasView: View {
    var initialTicketID: UUID? = nil
    var launchFocus: AtlasLaunchFocus = .none

    @Environment(AppState.self) private var app

    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }, sort: \TicketEntity.startDate, order: .reverse)
    private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date, order: .reverse)
    private var trips: [TripEntity]

    @AppStorage("atlas.mapLook") private var lookRaw = AtlasMapLook.standard.rawValue
    @State private var pickedScope: AtlasScope?
    @State private var mode: TransportMode?
    @State private var summary: AtlasSummary = .empty
    @State private var modes: [TransportMode] = []
    @State private var sheet: AtlasSheet?
    @State private var framing = AtlasFraming()
    @State private var highlightedPlaceID: String?
    @State private var selectionTick = 0
    @State private var didLaunch = false

    private var look: AtlasMapLook { AtlasMapLook(rawValue: lookRaw) ?? .standard }

    private var scope: AtlasScope {
        pickedScope ?? AtlasData.defaultScope(tickets: tickets, preferred: initialTicketID, selected: app.settings.selectedTicketID)
    }

    private var scopeLabel: String { AtlasData.scopeLabel(scope, tickets: tickets) }

    var body: some View {
        AtlasMapCanvas(summary: summary, look: look, selectedRouteID: sheet?.routeID,
                       highlightedPlaceID: highlightedPlaceID, framing: framing) { id in
            select(id)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if modes.count > 1 {
                AtlasModeBar(modes: modes, selection: $mode)
                    .padding(.top, Theme.Spacing.xxs)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomOverlay
        }
        .navigationTitle("Österreich-Karte")
        .navigationSubtitle(scopeLabel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar { toolbarContent }
        .sheet(item: $sheet, onDismiss: sheetDismissed) { item in
            sheetContent(item)
        }
        .onChange(of: dataKey, initial: true) {
            recompute()
        }
        .task { await launch() }
        .sensoryFeedback(.selection, trigger: mode) { _, _ in app.settings.hapticsEnabled }
        .sensoryFeedback(.selection, trigger: pickedScope) { _, _ in app.settings.hapticsEnabled }
        .sensoryFeedback(.impact(weight: .light), trigger: selectionTick) { _, _ in app.settings.hapticsEnabled }
    }

    // MARK: Overlays

    private var bottomOverlay: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
            Button {
                showOverview()
            } label: {
                Image(systemName: "scope")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Alle Strecken zeigen")
            AtlasPanel(summary: summary, scopeLabel: scopeLabel, modeName: mode?.displayName) {
                sheet = .details
            }
        }
        .padding(.horizontal, Theme.Spacing.cardGutter)
        .padding(.bottom, Theme.Spacing.xs)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if !tickets.isEmpty {
                Menu {
                    Picker("Zeitraum", selection: scopeBinding) {
                        ForEach(tickets) { ticket in
                            Text("Ticketjahr \(AtlasFormat.ticketYear(ticket.period)) · \(ticket.name)")
                                .tag(AtlasScope.ticket(ticket.id))
                        }
                        Text("Alle Ticketjahre").tag(AtlasScope.allYears)
                    }
                } label: {
                    Label("Zeitraum wählen", systemImage: "calendar")
                }
                .accessibilityValue(scopeLabel)
            }
            Button {
                withAnimation(.smooth) { lookRaw = (look == .standard ? AtlasMapLook.satellite : .standard).rawValue }
            } label: {
                Label(look == .standard ? "Satellit" : "Karte",
                      systemImage: look == .standard ? AtlasMapLook.satellite.symbol : AtlasMapLook.standard.symbol)
            }
            .accessibilityLabel(look == .standard ? "Satellitenansicht" : "Kartenansicht")
        }
    }

    private var scopeBinding: Binding<AtlasScope> {
        Binding(get: { scope }, set: { pickedScope = $0 })
    }

    @ViewBuilder
    private func sheetContent(_ item: AtlasSheet) -> some View {
        switch item {
        case .route(let id):
            if let route = summary.route(id: id) {
                AtlasRouteSheet(route: route, trips: trips(for: route.tripIDs),
                                ticketPrice: AtlasData.ticket(for: scope, in: tickets)?.period.price,
                                routeCount: summary.routes.count)
            }
        case .details:
            AtlasDetailsSheet(summary: summary, scopeLabel: scopeLabel,
                              onSelectRoute: { id in select(id) },
                              onFocusPlace: { place in focus(place) })
        }
    }

    // MARK: Actions

    private func select(_ id: String?) {
        guard let id else {
            if sheet?.routeID != nil { sheet = nil }
            if highlightedPlaceID != nil {
                highlightedPlaceID = nil
            }
            return
        }
        highlightedPlaceID = nil
        sheet = .route(id)
        framing = AtlasFraming(target: .route(id), revision: framing.revision + 1, coveredBottomFraction: 0.52)
        selectionTick += 1
    }

    private func focus(_ place: AtlasPlace) {
        sheet = nil
        highlightedPlaceID = place.id
        framing = AtlasFraming(target: .place(place.id), revision: framing.revision + 1)
        selectionTick += 1
    }

    private func showOverview() {
        highlightedPlaceID = nil
        framing = AtlasFraming(target: .overview, revision: framing.revision + 1)
    }

    private func sheetDismissed() {
        // Back to the whole map unless something else (a focused station) took over the camera.
        if sheet == nil, highlightedPlaceID == nil, framing.target != .overview {
            showOverview()
        }
    }

    // MARK: Data

    /// Changes whenever the shown trips could change (selection, filter, edits, sync).
    private var dataKey: String {
        let latest = trips.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0
        return "\(scope)|\(mode?.rawValue ?? "alle")|\(trips.count)|\(latest)|\(tickets.count)"
    }

    private func recompute() {
        let records = AtlasData.records(for: scope, trips: trips, tickets: tickets)
        modes = AtlasData.modes(in: records)
        let effectiveMode = mode.flatMap { modes.contains($0) ? $0 : nil }
        if effectiveMode != mode { mode = effectiveMode }
        summary = AtlasData.summary(records, mode: effectiveMode, stations: app.stations)
        if let id = sheet?.routeID, summary.route(id: id) == nil { sheet = nil }
        if let id = highlightedPlaceID, summary.place(id: id) == nil { highlightedPlaceID = nil }
        framing = AtlasFraming(target: .overview, revision: framing.revision + 1)
    }

    private func trips(for ids: [UUID]) -> [TripEntity] {
        let wanted = Set(ids)
        return trips.filter { wanted.contains($0.id) }
    }

    private func launch() async {
        guard !didLaunch else { return }
        didLaunch = true
        guard launchFocus != .none else { return }
        try? await Task.sleep(for: .milliseconds(900))
        switch launchFocus {
        case .topRoute:
            if let id = summary.topRoute?.id { select(id) }
        case .details:
            sheet = .details
        case .none:
            break
        }
    }
}
