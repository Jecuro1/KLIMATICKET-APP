import SwiftUI
import UIKit
import CoreLocation
import KlimaCore

/// Searchable station list: "In der Nähe" (location requested lazily via "Standort verwenden"),
/// "Zuletzt" (RecentStations) and popular stations; results show the kind icon and Bundesland.
/// When nothing matches exactly and `customName` is provided, the query can be used as a custom place.
///
/// Works both pushed (Settings → Heimatbahnhof) and as the root of a sheet (trip editor); it dismisses itself
/// after a choice. It does not add its own NavigationStack.
struct StationPickerView: View {
    let title: String
    let selection: (Station) -> Void
    let customName: ((String) -> Void)?

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var query = ""
    @State private var results: [Station] = []
    /// The (trimmed) query `results` belong to – avoids flashing "Keine Treffer" while a search is running.
    @State private var resultsQuery = ""
    @State private var nearby: TripEdNearby = .idle
    @State private var nearPoint: GeoPoint?
    @State private var locator: LocationService?
    @State private var recents: [Station] = []
    @State private var popular: [Station] = []

    init(title: String, initialQuery: String = "", selection: @escaping (Station) -> Void, customName: ((String) -> Void)? = nil) {
        self.title = title
        self.selection = selection
        self.customName = customName
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        List {
            if trimmedQuery.isEmpty {
                browseSections
            } else {
                resultSections
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background { Theme.sheetBackground.ignoresSafeArea() }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Bahnhof oder Haltestelle"))
        .autocorrectionDisabled()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: prepare)
        .task {
            if TripEdLocationAccess.current == .granted, case .idle = nearby {
                await loadNearby()
            }
        }
        .task(id: trimmedQuery) {
            await search()
        }
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: Browse (empty query)

    @ViewBuilder
    private var browseSections: some View {
        Section {
            nearbyContent
        } header: {
            Text("In der Nähe")
        }
        if !recents.isEmpty {
            Section {
                ForEach(recents) { station in
                    stationButton(station)
                }
            } header: {
                Text("Zuletzt")
            }
        }
        if !popularWithoutRecents.isEmpty {
            Section {
                ForEach(popularWithoutRecents) { station in
                    stationButton(station)
                }
            } header: {
                Text("Beliebte Bahnhöfe")
            }
        }
    }

    private var popularWithoutRecents: [Station] {
        let recentIDs = Set(recents.map(\.id))
        return popular.filter { !recentIDs.contains($0.id) }
    }

    @ViewBuilder
    private var nearbyContent: some View {
        switch nearby {
        case .idle:
            Button {
                Task { await loadNearby() }
            } label: {
                TripEdPickerActionRow(symbol: "location.fill", tint: Theme.accent, title: "Standort verwenden",
                                      subtitle: "Haltestellen in deiner Nähe vorschlagen")
            }
            .listRowBackground(Theme.surface)
        case .loading:
            HStack(spacing: Theme.Spacing.s) {
                ProgressView()
                    .frame(width: 34, height: 34)
                Text("Suche Haltestellen in der Nähe …")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surface)
        case .denied:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                TripEdPickerActionRow(symbol: "location.slash.fill", tint: Theme.textSecondary,
                                      title: "Standort nicht freigegeben", subtitle: "In den Einstellungen erlauben")
            }
            .listRowBackground(Theme.surface)
        case .empty:
            Button {
                Task { await loadNearby() }
            } label: {
                TripEdPickerActionRow(symbol: "location.magnifyingglass", tint: Theme.textSecondary,
                                      title: "Keine Haltestelle in der Nähe", subtitle: "Erneut versuchen")
            }
            .listRowBackground(Theme.surface)
        case .loaded(let items):
            ForEach(items) { item in
                stationButton(item.station, distanceKm: item.distanceKm)
            }
        }
    }

    // MARK: Search results

    @ViewBuilder
    private var resultSections: some View {
        let q = trimmedQuery
        if !results.isEmpty {
            Section {
                ForEach(results) { station in
                    stationButton(station)
                }
            } header: {
                Text("Treffer")
            }
        }
        if customName != nil && !hasExactMatch {
            Section {
                Button {
                    useCustomName(q)
                } label: {
                    TripEdPickerActionRow(symbol: "mappin.and.ellipse", tint: Theme.dawn,
                                          title: "„\(q)“ als eigenen Ort verwenden",
                                          subtitle: "Den Normalpreis trägst du danach selbst ein")
                }
                .listRowBackground(Theme.surface)
            }
        } else if results.isEmpty && resultsQuery == q {
            Section {
                Label("Keine Haltestelle gefunden", systemImage: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .listRowBackground(Theme.surface)
            }
        }
    }

    private var hasExactMatch: Bool {
        let key = StationIndex.normalize(trimmedQuery)
        return results.contains { StationIndex.normalize($0.name) == key }
    }

    // MARK: Rows

    private func stationButton(_ station: Station, distanceKm: Double? = nil) -> some View {
        Button {
            choose(station)
        } label: {
            TripEdStationRow(station: station, distanceKm: distanceKm)
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: Actions

    private func choose(_ station: Station) {
        RecentStations.remember(station.id)
        selection(station)
        dismiss()
    }

    private func useCustomName(_ name: String) {
        guard !name.isEmpty else { return }
        customName?(name)
        dismiss()
    }

    private func prepare() {
        if recents.isEmpty {
            recents = Array(RecentStations.load().compactMap { app.stations.station(id: $0) }.prefix(6))
        }
        if popular.isEmpty {
            popular = app.stations.search("", limit: 10, near: nil)
        }
    }

    private func search() async {
        let q = trimmedQuery
        guard !q.isEmpty else {
            results = []
            resultsQuery = ""
            return
        }
        try? await Task.sleep(for: .milliseconds(80))   // light debounce while typing
        if Task.isCancelled { return }
        let index = app.stations
        let near = nearPoint
        let found = await Task.detached(priority: .userInitiated) {
            index.search(q, limit: 40, near: near)
        }.value
        if Task.isCancelled { return }
        results = found
        resultsQuery = q
    }

    /// Asks for "when in use" permission only now (lazily) and lists the nearest stations.
    private func loadNearby() async {
        withAnimation(.snappy(duration: 0.25)) { nearby = .loading }
        let service = locator ?? LocationService()
        locator = service
        let wasUndetermined = TripEdLocationAccess.current == .undetermined
        var found = await service.nearestStations(in: app.stations, limit: 4)
        if found.isEmpty && wasUndetermined {
            // The permission prompt may still be open – wait for the answer, then try once more.
            var waited = 0
            while TripEdLocationAccess.current == .undetermined && waited < 120 && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                waited += 1
            }
            if TripEdLocationAccess.current == .granted {
                found = await service.nearestStations(in: app.stations, limit: 4)
            }
        }
        let access = TripEdLocationAccess.current
        withAnimation(.snappy(duration: 0.3)) {
            if let first = found.first {
                nearPoint = first.station.location
                nearby = .loaded(found.map { TripEdNearbyStation(station: $0.station, distanceKm: $0.distanceKm) })
            } else if access == .denied {
                nearby = .denied
            } else {
                nearby = .empty
            }
        }
    }
}

// MARK: - Supporting types

private enum TripEdNearby {
    case idle
    case loading
    case denied
    case empty
    case loaded([TripEdNearbyStation])
}

private struct TripEdNearbyStation: Identifiable {
    let station: Station
    let distanceKm: Double
    var id: String { station.id }
}

/// Current location authorisation, read without prompting.
@MainActor
private enum TripEdLocationAccess {
    case undetermined, granted, denied

    private static let probe = CLLocationManager()

    static var current: TripEdLocationAccess {
        switch probe.authorizationStatus {
        case .notDetermined:
            return .undetermined
        case .authorizedAlways, .authorizedWhenInUse:
            return .granted
        default:
            return .denied
        }
    }
}

/// Station result: coloured kind icon · name · "Bahnhof · Tirol" · optional distance.
private struct TripEdStationRow: View {
    let station: Station
    var distanceKm: Double?

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ModeIcon(mode: station.primaryMode, size: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(TripEdFormat.stationSubtitle(station))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.xs)
            if let distanceKm {
                Text(Format.km(distanceKm))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Action row ("Standort verwenden", "„Lech Post“ als eigenen Ort verwenden").
private struct TripEdPickerActionRow: View {
    var symbol: String
    var tint: Color
    var title: String
    var subtitle: String? = nil

    private static let size: CGFloat = 34

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: Self.size, height: Self.size)
                .background(tint.opacity(0.14), in: .rect(cornerRadius: Self.size * 0.31, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
