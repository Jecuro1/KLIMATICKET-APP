import SwiftUI
import KlimaCore

// MARK: radar2-radarmine – choosing the stop of „Wo bleibt mein Bus?“ (docs/RADAR_MINE.md §4): a search in the app's own station index (no request),
// the stop nearest the map's centre, the one nearest your fix (only after „In meiner Nähe zeigen“) and the last five. Choosing one is what sends it:
// the next free slot of the radar links it, the one after asks its board.

struct RadarMineStopPicker: View {
    var mine: RadarMineModel
    var context: RadarMineContext

    @State private var query = ""
    @State private var results: [Station] = []
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(RadarMineText.chooseStop)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            searchField
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                if results.isEmpty {
                    Text(RadarMineText.stopSearchEmpty).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                ForEach(results, id: \.id) { station in
                    row(station.name, detail: station.kindLabel, symbol: "magnifyingglass") { choose(station) }
                }
            } else {
                if let centre = centreStation {
                    row(RadarMineText.mapCentre(centre.name), detail: centre.kindLabel, symbol: "scope") { choose(centre) }
                }
                if let near = nearStation {
                    row(RadarMineText.nearYou(near.name), detail: near.kindLabel, symbol: "location.fill") { choose(near) }
                }
                let recent = mine.file.stops
                if !recent.isEmpty {
                    Text(RadarMineText.recent)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .textCase(.uppercase)
                        .padding(.top, Theme.Spacing.xxs)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(recent) { stop in
                        row(stop.name, detail: nil, symbol: "clock.arrow.circlepath") { choose(station(for: stop)) }
                    }
                }
            }
        }
        .task(id: query) {
            let text = query.trimmingCharacters(in: .whitespaces)
            guard text.count >= 2 else {
                results = []
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            results = Array(context.stations.search(text, limit: 6, near: context.mapCentre).prefix(6))
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
            TextField(RadarMineText.stopSearch, text: $query)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary) }
                    .accessibilityLabel("Suche löschen")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(Theme.surfaceSecondary, in: .capsule)
    }

    private func row(_ title: String, detail: String?, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// The stop nearest the map's centre (within a kilometre). Demo and screenshot launches: the invented stop when the map is near it.
    private var centreStation: Station? {
        if isDemo, context.mapCentre.distanceKm(to: RadarMineDemo.stop.location) < 2 { return RadarMineDemo.stop }
        return context.stations.nearest(to: context.mapCentre, limit: 1, maxKm: 1).first?.station
    }

    /// The stop nearest your fix, only after the tap of „In der Nähe“.
    private var nearStation: Station? {
        guard let fix = mine.fix else { return nil }
        if isDemo, fix.distanceKm(to: RadarMineDemo.stop.location) < 2 { return RadarMineDemo.stop }
        return context.stations.nearest(to: fix, limit: 1, maxKm: 1).first?.station
    }

    private var isDemo: Bool { LaunchMode.isSandboxed || LaunchMode.useDemoData }

    /// A recent stop as a station: the index's own entry when it has one, else what was kept of it.
    private func station(for stop: RadarMineStop) -> Station {
        if stop.id == RadarMineDemo.stop.id { return RadarMineDemo.stop }
        return context.stations.station(id: stop.id)
            ?? Station(id: stop.id, name: stop.name, lat: stop.coordinate.latitude, lon: stop.coordinate.longitude, state: "", kind: .stop)
    }

    private func choose(_ station: Station) {
        searchFocused = false
        query = ""
        withMotion(Motion.smooth) { mine.choose(station) }
        context.focus(station.location, 0.03)
    }
}
