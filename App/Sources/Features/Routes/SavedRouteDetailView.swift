import SwiftUI
import SwiftData
import AppIntents
import KlimaCore

// „Meine Routen“ detail (docs/ROUTES_ALARMS.md §1.5): the stops, the figures, the next cached departures and the actions
// „Suchen“, „Als Widget“, „Als Siri-Befehl“, the schedule, edit and delete.

struct SavedRouteDetailView: View {
    let route: FavoriteRouteEntity
    /// Called after „Suchen“ opened the planner, so the routes sheet closes and the planner shows the search.
    var onSearch: () -> Void = {}

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showsEditor = false
    @State private var showsWidgetHelp = false
    @State private var showsDeleteConfirm = false
    @State private var showsSiriTip = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                hero
                figures
                departures
                actions
                siri
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m)
        }
        .background(Theme.sheetBackground)
        .navigationTitle(route.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showsEditor = true } label: { Label("Bearbeiten", systemImage: "pencil") }
                    Button(role: .destructive) { showsDeleteConfirm = true } label: { Label("Löschen", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Weitere Aktionen")
            }
        }
        .sheet(isPresented: $showsEditor) {
            NavigationStack { SavedRouteEditView(route: route) }
        }
        .sheet(isPresented: $showsWidgetHelp) {
            RouteWidgetHelpSheet(routeTitle: route.displayTitle)
        }
        .confirmationDialog("Route löschen?", isPresented: $showsDeleteConfirm, titleVisibility: .visible) {
            Button("Route löschen", role: .destructive) {
                SavedRouteStore.delete(route, repository: Repository(context: context, app: app))
                app.showToast("trash.fill", "Route gelöscht")
                dismiss()
            }
        } message: {
            Text("Die Erinnerungen dieser Route werden auch entfernt. Die gespeicherten Fahrten bleiben.")
        }
    }

    // MARK: Sections

    private var stops: [String] {
        [route.fromName] + route.via.map(\.name) + [route.toName]
    }

    private var hero: some View {
        GlassCard(padding: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Kicker(text: route.schedule.map { "Zeitplan · \($0.summary)" } ?? "Gespeicherte Route")
                ForEach(Array(stops.enumerated()), id: \.offset) { index, name in
                    HStack(spacing: Theme.Spacing.s) {
                        Circle()
                            .fill(index == 0 ? Theme.glacier : (index == stops.count - 1 ? Theme.dawn : Theme.dusk))
                            .frame(width: 10, height: 10)
                        Text(name)
                            .font(index == 0 || index == stops.count - 1 ? .headline : .subheadline)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                    }
                }
                if route.isRoundTrip {
                    Label("Hin und zurück", systemImage: "arrow.left.arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The figures: side by side, stacked at the accessibility sizes. The fare and CO₂ say "hin & retour" for a return trip,
    /// as the fare and the CO₂ of a log do (`valuePerLog`, the doubled distance).
    private var figures: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.s))
        return layout {
            StatTile(value: SavedRouteFigures.fareEUR(route).map { Format.euroPrecise($0) } ?? "offen",
                     label: route.isRoundTrip ? "Preis hin & retour" : "Preis je Fahrt", symbol: "eurosign.circle.fill", color: Theme.glacier)
            StatTile(value: Format.number(SavedRouteFigures.co2Kg(route, app: app), decimals: 1), unit: "kg",
                     label: route.isRoundTrip ? "CO₂ hin & retour" : "CO₂ je Fahrt", symbol: "leaf.fill", color: Theme.pine)
            StatTile(value: Format.number(SavedRouteFigures.distanceKm(route)), unit: "km",
                     label: route.isRoundTrip ? "Hin & retour" : "Strecke", symbol: "point.topleft.down.to.point.bottomright.curvepath.fill",
                     color: Theme.dusk)
        }
    }

    @ViewBuilder private var departures: some View {
        // One read of the cache for this render (see SavedRouteDepartures.currentCache).
        let cache = SavedRouteDepartures.currentCache()
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(title: "Nächste Abfahrten")
            GlassCard(padding: Theme.Spacing.m) {
                if !route.viaRaw.isEmpty || route.isCombo {
                    departureNote("Für Strecken mit Zwischenhalt oder mehreren Teilstrecken holen wir keine Live-Abfahrten.")
                } else {
                    let upcoming = SavedRouteDepartures.connections(for: route, in: cache)
                        .filter { ($0.realtime ?? $0.planned) >= Date().addingTimeInterval(-60) }
                        .prefix(4)
                    if upcoming.isEmpty {
                        departureNote(SavedRouteDepartures.unavailableText(app.live)
                                      ?? "Noch keine Abfahrt geladen. Ziehe die Liste der Routen nach unten, um sie zu holen.")
                    } else {
                        VStack(spacing: Theme.Spacing.s) {
                            ForEach(Array(upcoming)) { connection in
                                departureRow(connection)
                            }
                        }
                    }
                }
            }
            // The times are the ones of the last live refresh: say when that was.
            if let fetched = cache?.fetchedAt, !route.isCombo, route.viaRaw.isEmpty {
                Text("Stand \(Format.time(fetched)) · vom letzten Abruf")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func departureNote(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func departureRow(_ connection: WidgetConnection) -> some View {
        let time = connection.realtime ?? connection.planned
        return HStack(spacing: Theme.Spacing.s) {
            Text(Format.time(time))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(connection.isCancelled ? Theme.alpenglow : Theme.textPrimary)
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.lineName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(connection.isCancelled ? "fällt aus" : (connection.direction.map { "Richtung \($0)" } ?? connection.fromName))
                    .font(.caption)
                    .foregroundStyle(connection.isCancelled ? Theme.alpenglow : Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let platform = connection.platform {
                Text(platform)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(connection.platformChanged ? Theme.summitText : Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Button {
                SavedRouteSearch.open(route, app: app)
                onSearch()
            } label: {
                Label("Suchen", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            let pair = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s))
                : AnyLayout(HStackLayout(spacing: Theme.Spacing.s))
            pair {
                Button { showsWidgetHelp = true } label: {
                    Label("Als Widget", systemImage: "square.grid.2x2")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                Button { showsEditor = true } label: {
                    Label(route.schedule == nil ? "Zeitplan" : "Zeitplan ändern", systemImage: "alarm")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
        }
    }

    @ViewBuilder private var siri: some View {
        if showsSiriTip {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                SectionHeader(title: "Als Siri-Befehl")
                SiriTipView(intent: SavedRouteSearchIntent(route: FavoriteRouteAppEntity(id: route.id, title: route.displayTitle)),
                            isVisible: $showsSiriTip)
                Text("Sag Siri den Namen der Route: dann öffnet KlimaBilanz die Suche auf dieser Strecke.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// „Als Widget“: the widget picks a route from the saved favourites, and iOS adds widgets only from the Home Screen. So the
/// sheet says what to do there, and does not claim to add it.
struct RouteWidgetHelpSheet: View {
    let routeTitle: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Ein Widget kannst du nur auf dem Home-Bildschirm anlegen. KlimaBilanz kann es dort nicht für dich hinzufügen.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                Section("So geht’s") {
                    Label("Home-Bildschirm lange drücken und oben auf „+“ tippen.", systemImage: "1.circle")
                    Label("„KlimaBilanz“ und dann „Nächste Verbindung“ wählen.", systemImage: "2.circle")
                    Label("Bei „Lieblingsfahrt“ „\(routeTitle)“ auswählen.", systemImage: "3.circle")
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.sheetBackground)
            .navigationTitle("Als Widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
