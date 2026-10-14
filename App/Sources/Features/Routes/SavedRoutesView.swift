import SwiftUI
import SwiftData
import KlimaCore

// „Meine Routen“ (docs/ROUTES_ALARMS.md §1): every saved route in one list, in the order the user sets. Opened from the
// Planner header. Routes are the existing favourites (`FavoriteRouteEntity`), so the Trips tab and the widgets see the same ones.

struct SavedRoutesView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<FavoriteRouteEntity> { $0.deletedAt == nil }, sort: \FavoriteRouteEntity.sortIndex)
    private var routes: [FavoriteRouteEntity]
    @State private var editor: RouteEditorTarget?
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            List {
                if routes.isEmpty {
                    Section {
                        EmptyStateView(symbol: "bookmark.fill", title: "Noch keine Route",
                                       message: "Speicher eine Verbindung oder eine Strecke von A nach B – mit Zwischenhalt und Zeitplan.",
                                       actionTitle: "Route anlegen") {
                            editor = RouteEditorTarget(route: nil)
                        }
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(routes) { route in
                            NavigationLink {
                                SavedRouteDetailView(route: route, onSearch: { dismiss() })
                            } label: {
                                SavedRouteRow(route: route)
                            }
                            .listRowBackground(Theme.surface)
                        }
                        .onMove(perform: move)
                        .onDelete(perform: delete)
                    } footer: {
                        Text(footerText)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.sheetBackground)
            .navigationTitle("Meine Routen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if !routes.isEmpty { EditButton() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { editor = RouteEditorTarget(route: nil) } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Route anlegen")
                }
            }
            .sheet(item: $editor) { target in
                NavigationStack {
                    SavedRouteEditView(route: target.route)
                }
            }
            .task { await refresh() }
            .refreshable { await refresh(force: true) }
        }
    }

    /// The live line under the list: why there are no departures, or when they were fetched.
    private var footerText: String {
        if let text = SavedRouteDepartures.unavailableText(app.live) { return text }
        if isRefreshing { return "Abfahrten werden geladen …" }
        if let fetched = WidgetCache.connections?.fetchedAt {
            return "Abfahrten Stand \(Format.time(fetched)). Ziehen zum Aktualisieren."
        }
        return "Ziehen zum Laden der nächsten Abfahrten."
    }

    private func refresh(force: Bool = false) async {
        isRefreshing = true
        await SavedRouteDepartures.refresh(routes, app: app, force: force)
        isRefreshing = false
    }

    private func move(from offsets: IndexSet, to destination: Int) {
        SavedRouteStore.move(routes, from: offsets, to: destination, repository: Repository(context: context, app: app))
    }

    private func delete(at offsets: IndexSet) {
        let repository = Repository(context: context, app: app)
        let doomed = offsets.map { routes[$0] }
        for route in doomed { SavedRouteStore.delete(route, repository: repository) }
        app.showToast("trash.fill", doomed.count == 1 ? "Route gelöscht" : "\(doomed.count) Routen gelöscht")
    }
}

/// What the route editor opens with: nil for a new route.
struct RouteEditorTarget: Identifiable {
    let id = UUID()
    let route: FavoriteRouteEntity?
}
