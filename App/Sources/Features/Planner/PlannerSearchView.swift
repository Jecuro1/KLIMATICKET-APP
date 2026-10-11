import SwiftUI
import KlimaCore

/// Place suggestions while the Fahrplan search field is active (docs/OEBB_LIVE.md §E3 „Root / search“): the offline station
/// index answers instantly; live Scotty suggestions (addresses, POIs, stops the index lacks) are merged in after 250 ms,
/// only with live data on, and only when there are fewer than three local hits or the query has a digit.
struct PlannerSearchView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismissSearch) private var dismissSearch

    @State private var local: [Station] = []
    @State private var liveHits: [PlannerPlace] = []
    @State private var isSearchingLive = false
    @State private var recents: [PlannerPlace] = []

    var body: some View {
        let model = app.planner
        let text = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
        List {
            if text.isEmpty {
                browse(model)
            } else {
                results(model, text: text)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background { SetBackdrop(skyOpacity: 0.5, fadeEnd: 0.45) }
        .task(id: model.query) { await search(text) }
        .onAppear { recents = PlannerRecents.load(stations: app.stations) }
        .accessibilityElement(children: .contain)
    }

    // MARK: Browse

    @ViewBuilder
    private func browse(_ model: PlannerModel) -> some View {
        if model.searchTarget != .board {
            Section {
                Button { pick(.currentLocation) } label: {
                    PlannerPlaceRow(place: .currentLocation, subtitleOverride: "Nächste Haltestelle als Start oder Ziel")
                }
                .listRowBackground(Theme.surface)
            }
        }
        if !recents.isEmpty {
            Section {
                ForEach(recents) { place in
                    Button { pick(place) } label: { PlannerPlaceRow(place: place) }
                        .listRowBackground(Theme.surface)
                }
            } header: {
                SetSectionHeader(title: "Zuletzt")
            }
        } else {
            Section {
                Label("Tippe einen Bahnhof, eine Haltestelle oder eine Adresse.", systemImage: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .listRowBackground(Theme.surface)
            }
        }
    }

    // MARK: Results

    @ViewBuilder
    private func results(_ model: PlannerModel, text: String) -> some View {
        if !local.isEmpty {
            Section {
                ForEach(local) { station in
                    Button { pick(.station(station)) } label: { PlannerPlaceRow(place: .station(station)) }
                        .listRowBackground(Theme.surface)
                }
            }
        }
        if !liveHits.isEmpty {
            Section {
                ForEach(liveHits) { place in
                    Button { pick(place) } label: { PlannerPlaceRow(place: place) }
                        .listRowBackground(Theme.surface)
                }
            } header: {
                SetSectionHeader(title: "Weitere Orte · live")
            }
        }
        if isSearchingLive && liveHits.isEmpty {
            Section {
                HStack(spacing: Theme.Spacing.s) {
                    ProgressView()
                    Text("Suche live …").font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surface)
            }
        }
        if local.isEmpty && liveHits.isEmpty && !isSearchingLive {
            Section {
                Label("Nichts gefunden", systemImage: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .listRowBackground(Theme.surface)
            }
        }
        if text.count >= 3, app.live.consent == .undecided {
            Section {
                LiveConsentCard(style: .inline).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            } footer: {
                SetFooter(text: "Adressen und weitere Orte findest du mit Live-Daten.")
            }
        }
    }

    // MARK: Actions

    private func pick(_ place: PlannerPlace) {
        app.planner.choose(place)
        dismissSearch()
    }

    private func search(_ text: String) async {
        guard !text.isEmpty else {
            local = []
            liveHits = []
            isSearchingLive = false
            return
        }
        let index = app.stations
        let found = await Task.detached(priority: .userInitiated) { index.search(text, limit: 8) }.value
        if Task.isCancelled { return }
        local = found
        liveHits = []
        // Live suggestions: debounced, only with live data, only where the offline index is thin.
        guard text.count >= 2, let timetable = app.live.timetable, found.count < 3 || text.contains(where: \.isNumber) else {
            isSearchingLive = false
            return
        }
        isSearchingLive = true
        try? await Task.sleep(for: .milliseconds(250))
        if Task.isCancelled { return }
        defer { isSearchingLive = false }
        guard let locations = try? await timetable.locations(text, types: .all, maxResults: 8), !Task.isCancelled else { return }
        var seen = Set(found.map(\.id))
        var merged: [PlannerPlace] = []
        for location in locations {
            if location.kind == .station, let station = StationLinker.appStation(for: location, in: index) {
                if seen.insert(station.id).inserted && !found.contains(where: { $0.id == station.id }) { merged.append(.station(station)) }
            } else {
                merged.append(.live(location))
            }
        }
        // A station the index returned first stays first; live additions follow.
        liveHits = merged.filter { place in
            if case .station(let s) = place { return !found.contains(where: { $0.id == s.id }) }
            return true
        }
    }
}

/// One place: icon tile, name, „Bahnhof · Tirol“.
struct PlannerPlaceRow: View {
    var place: PlannerPlace
    var subtitleOverride: String? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(place.title).font(.body.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(2)
                if let subtitle = subtitleOverride ?? place.subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var icon: some View {
        if let mode = place.mode {
            ModeIcon(mode: mode, size: 34).accessibilityHidden(true)
        } else {
            SetIconTile(symbol: place.symbol, tint: place.isCurrentLocation ? Theme.accent : Theme.textSecondary, size: 34)
        }
    }
}

extension PlannerPlace {
    var isCurrentLocation: Bool { if case .currentLocation = self { return true } else { return false } }
}
