import Foundation
import WidgetKit
import KlimaCore

/// The app's side of the widget cache (docs/WIDGETS.md §5–6). It mirrors the live consent, writes the station list and the
/// live caches (connections of the favourite routes, departures of the stations, disruptions of the lines the user rides)
/// into the App Group, and reloads only the widgets whose content changed.
///
/// Nothing live leaves the app without consent: `refreshLive` returns before any request unless the user granted live data.
/// Widgets never call this code; they read what it wrote.
@MainActor
enum WidgetCacheSync {
    /// Live data is refreshed at most this often (while the app is active, or on an explicit refresh).
    static let minimumInterval: TimeInterval = 15 * 60
    /// The number of favourite routes and stations asked for per refresh (the request budget stays small).
    static let routeLimit = 4
    static let boardLimit = 4

    private static var lastLiveRefresh: Date?

    // MARK: Consent

    /// Mirrors the app's consent. Anything but "granted" empties the live caches at once and reloads the widgets.
    static func consentDidChange(_ consent: LiveDataService.Consent) {
        let mirrored = WidgetConsent(rawValue: consent.rawValue) ?? .undecided
        WidgetCache.setConsent(mirrored)
        guard mirrored != .granted else { return }
        lastLiveRefresh = nil
        if WidgetCache.clearLive() { reloadLive() }
    }

    // MARK: Stations (offline data: no consent needed)

    /// Writes the stations the widgets can choose from: the home station first, then the stations of the favourites (at most
    /// `WidgetStationList.maxCount`), with the equipment the place data delivers. Reloads the departures only when it changed.
    static func stationsDidChange(favorites: [FavoriteRouteEntity], homeStationID: String?, stations: StationIndex) {
        var ids: [String] = []
        for id in [homeStationID].compactMap({ $0 }) + favorites.flatMap({ [$0.fromStationID, $0.toStationID] }).compactMap({ $0 }) {
            if !ids.contains(id) { ids.append(id) }
        }
        let index = PlaceIndexLoader.shared.current
        let list: [WidgetStation] = ids.compactMap { id in
            guard let station = stations.station(id: id) else { return nil }
            var marks: [StopMark] = []
            if let tags = index?.details(for: id)?.tags { marks = PlaceMarkSelection.detailMarks(tags: tags) }
            return WidgetStation(id: id, name: station.name, isHome: id == homeStationID,
                                 facilities: WidgetCacheBuilder.facilities(marks))
        }
        let value = WidgetStationList(updatedAt: Date(), stations: list)
        let previous = WidgetCache.stations
        guard previous?.stations != value.stations else { return }
        WidgetCache.write(value, key: WidgetCacheKey.stations)
        WidgetCenter.shared.reloadTimelines(ofKind: WidKind.departures)
    }

    // MARK: Live caches

    /// Refreshes the live caches when the user granted live data, the last refresh is older than `minimumInterval` (or `force`)
    /// and the planner's service is available. A failed request keeps the previous cache, which then ages to "stale".
    static func refreshLive(live: LiveDataService, favorites: [FavoriteRouteEntity], stations: StationIndex,
                            homeStationID: String?, force: Bool = false) async {
        guard WidgetCache.isLiveAllowed, let timetable = live.timetable else { return }
        let now = Date()
        if !force, let last = lastLiveRefresh, now.timeIntervalSince(last) < minimumInterval { return }
        lastLiveRefresh = now

        // Connections of the direct favourite routes (via routes are not asked for: their stops would need a plan).
        let routes = favorites
            .filter { $0.viaRaw.isEmpty && $0.fromStationID != nil && $0.toStationID != nil }
            .prefix(routeLimit)
        var pairs: [(favorite: FavoriteRouteEntity, query: JourneyQuery)] = []
        for favorite in routes {
            guard let from = favorite.fromStationID.flatMap(stations.station(id:)),
                  let to = favorite.toStationID.flatMap(stations.station(id:)) else { continue }
            guard let origin = try? await live.linker.hafasLocation(for: from),
                  let destination = try? await live.linker.hafasLocation(for: to) else { continue }
            pairs.append((favorite, JourneyQuery(origin: origin, destination: destination, date: now, products: .all,
                                                 results: 4, includeStopovers: false)))
        }
        var lines: [String] = []
        if !pairs.isEmpty, let results = try? await timetable.journeys(batch: pairs.map(\.query)) {
            writeRoutes(pairs: pairs, results: results, now: now, lines: &lines)
        }
        await refreshDepartures(timetable: timetable, live: live, stations: stations, homeStationID: homeStationID,
                                favorites: Array(routes), now: now)
        await refreshDisruptions(timetable: timetable, lines: lines, now: now)
    }

    /// Maps the batch answers to the connection cache and collects the lines the user rides (for the disruptions).
    private static func writeRoutes(pairs: [(favorite: FavoriteRouteEntity, query: JourneyQuery)],
                                    results: [Result<JourneyPage, LiveError>], now: Date, lines: inout [String]) {
        var connectionRoutes: [String: [WidgetConnection]] = [:]
        for (pair, result) in zip(pairs, results) {
            guard case .success(let page) = result else { continue }
            connectionRoutes[pair.favorite.id.uuidString] = WidgetCacheBuilder.connections(from: page, now: now)
            for journey in page.journeys.prefix(4) {
                for line in journey.rideLegs.compactMap(\.line?.name) where !lines.contains(line) { lines.append(line) }
            }
        }
        writeConnections(routes: connectionRoutes, now: now)
    }

    private static func writeConnections(routes: [String: [WidgetConnection]], now: Date) {
        let previous = WidgetCache.connections
        let changed = previous?.routes != routes
        WidgetCache.write(WidgetConnectionCache(fetchedAt: now, routes: routes), key: WidgetCacheKey.connections)
        if changed { WidgetCenter.shared.reloadTimelines(ofKind: WidKind.nextConnection) }
    }

    private static func refreshDepartures(timetable: any TimetableService, live: LiveDataService, stations: StationIndex,
                                          homeStationID: String?, favorites: [FavoriteRouteEntity], now: Date) async {
        var ids: [String] = []
        for id in [homeStationID].compactMap({ $0 }) + favorites.compactMap(\.fromStationID) where !ids.contains(id) {
            ids.append(id)
        }
        var boards: [String: [WidgetDeparture]] = [:]
        for id in ids.prefix(boardLimit) {
            guard let station = stations.station(id: id),
                  let location = try? await live.linker.hafasLocation(for: station),
                  let board = try? await timetable.board(BoardQuery(station: location, kind: .departures, date: now,
                                                                    durationMinutes: 120, maxResults: 30)) else { continue }
            boards[id] = WidgetCacheBuilder.departures(from: board, now: now, limit: 8)
        }
        guard !boards.isEmpty else { return }
        let previous = WidgetCache.departures
        // Stations that were not asked this time keep their last list.
        let merged = (previous?.stations ?? [:]).merging(boards) { _, new in new }
        let changed = previous?.stations != merged
        WidgetCache.write(WidgetDepartureCache(fetchedAt: now, stations: merged), key: WidgetCacheKey.departures)
        if changed { WidgetCenter.shared.reloadTimelines(ofKind: WidKind.departures) }
    }

    private static func refreshDisruptions(timetable: any TimetableService, lines: [String], now: Date) async {
        let filter = DisruptionFilter()
        let items: [WidgetDisruption]
        if lines.isEmpty {
            items = []
        } else {
            guard let remarks = try? await timetable.remarks(filter.query(now: now)) else { return }
            items = WidgetCacheBuilder.disruptions(filter.apply(remarks, now: now), followedLines: lines, now: now)
        }
        let previous = WidgetCache.disruptions
        let changed = previous?.items != items || previous?.lines != lines
        WidgetCache.write(WidgetDisruptionCache(fetchedAt: now, lines: lines, items: items), key: WidgetCacheKey.disruptions)
        if changed { WidgetCenter.shared.reloadTimelines(ofKind: WidKind.disruptions) }
    }

    // MARK: Live follow (Live verfolgen control)

    /// Mirrors the followed train into the App Group and refreshes the control's state.
    static func liveFollowDidChange(active: Bool) {
        WidgetCache.setLiveFollowActive(active)
        ControlCenter.shared.reloadControls(ofKind: WidKind.liveFollowControl)
    }

    /// Takes a request of the control: "stop" ends the follow; "start" opens the Zug-Radar to choose a train.
    static func consumeLiveFollowRequest(app: AppState) {
        guard let request = WidgetCache.takeLiveFollowRequest() else { return }
        if request {
            if LiveFollowTracker.shared.target == nil {
                app.selectedTab = .planner
                app.planner.radarRequested = true
            }
        } else {
            LiveFollowTracker.shared.stop()
        }
        // The control showed the optimistic state; the truth is whether a train is followed now (a radar that was closed
        // without a choice leaves the toggle off).
        liveFollowDidChange(active: LiveFollowTracker.shared.target != nil)
    }

    // MARK: Reloads

    /// Settings „Live-Cache leeren“: the widgets' live caches are removed with the app's own.
    static func liveCachesDidReset() {
        lastLiveRefresh = nil
        if WidgetCache.clearLive() { reloadLive() }
    }

    static func reloadLive() {
        WidgetCenter.shared.reloadTimelines(ofKind: WidKind.nextConnection)
        WidgetCenter.shared.reloadTimelines(ofKind: WidKind.departures)
        WidgetCenter.shared.reloadTimelines(ofKind: WidKind.disruptions)
    }
}
