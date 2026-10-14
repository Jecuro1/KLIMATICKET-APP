import Foundation
import SwiftUI
import KlimaCore

// „Meine Routen“ (docs/ROUTES_ALARMS.md §1): the helpers the route screens share. They read the stored route, the cached
// connections the live refresh wrote, and the app's own estimator and emission factors. None of them makes a request.

/// Opens the planner with a saved route filled in: the same path as a `klimabilanz://plan` link, so the search starts only
/// when both ends are known places, and then uses the live timetable with consent like any search.
@MainActor
enum SavedRouteSearch {
    static func link(for route: FavoriteRouteEntity, at date: Date? = nil) -> PlannerLink {
        PlannerLink(from: route.fromStationID ?? route.fromName,
                    to: route.toStationID ?? route.toName,
                    vias: route.via.map { $0.stationID ?? $0.name },
                    at: date)
    }

    static func open(_ route: FavoriteRouteEntity, app: AppState, at date: Date? = nil) {
        app.selectedTab = .planner
        app.planner.handleDeepLink(link(for: route, at: date))
    }
}

/// The figures of a saved route: the fare and the distance (stored, or estimated from the stations), and CO₂ from the
/// emission factors of the app's catalog.
@MainActor
enum SavedRouteFigures {
    /// Distance of one log of the route (both directions for a return trip).
    static func distanceKm(_ route: FavoriteRouteEntity) -> Double {
        route.distanceKm * (route.isRoundTrip ? 2 : 1)
    }

    /// Fare of one log of the route; nil when no fare is known (the editor fills it from the estimator).
    static func fareEUR(_ route: FavoriteRouteEntity) -> Double? {
        route.fareEUR > 0 ? route.valuePerLog : nil
    }

    static func co2Kg(_ route: FavoriteRouteEntity, app: AppState) -> Double {
        SavedRoutes.co2Kg(distanceKm: distanceKm(route), mode: route.mode, factors: app.catalog.emissions)
    }

    /// Estimate for two stations, the same estimator the planner and the trip editor use. nil without both stations.
    static func estimate(from: Station?, to: Station?, mode: TransportMode, app: AppState) -> (fareEUR: Double, distanceKm: Double)? {
        guard let from, let to else { return nil }
        let estimate = app.estimator.estimate(from: from, to: to, mode: mode)
        return (estimate.fareEUR, estimate.distanceKm)
    }
}

/// The next departures of a saved route: the connections the live refresh cached for it (consent-gated there), never a
/// request of the view itself.
@MainActor
enum SavedRouteDepartures {
    /// Only direct routes have cached connections: a route with via stops or several legs is not asked for.
    static func cached(for route: FavoriteRouteEntity) -> WidgetConnectionCache? {
        guard route.viaRaw.isEmpty, !route.isCombo else { return nil }
        guard let cache = WidgetCache.connections, cache.routes[route.id.uuidString] != nil else { return nil }
        return cache
    }

    static func connections(for route: FavoriteRouteEntity) -> [WidgetConnection] {
        if LaunchMode.useDemoData { return SavedRouteDemo.connections(for: route, now: Date()) }
        return cached(for: route)?.routes[route.id.uuidString] ?? []
    }

    /// Asks for fresh departures of the routes when the live data is allowed and the last refresh is old enough. The
    /// refresh itself checks consent and the request budget.
    static func refresh(_ routes: [FavoriteRouteEntity], app: AppState, force: Bool = false) async {
        await WidgetCacheSync.refreshLive(live: app.live, favorites: routes, stations: app.stations,
                                          homeStationID: app.settings.homeStationID, force: force)
    }

    /// Why no departures are shown, in words; nil when live departures are available.
    static func unavailableText(_ live: LiveDataService) -> String? {
        guard let reason = live.timetableUnavailable else { return nil }
        switch reason {
        case .consentUndecided: return "Live-Abfahrten sind aus. Stimm in den Einstellungen dem Live-Verkehr zu."
        case .declined: return "Live-Abfahrten sind aus, weil du den Live-Daten nicht zugestimmt hast."
        case .switchedOff: return "Live-Abfahrten sind in den Einstellungen ausgeschaltet."
        case .killSwitch(let notice): return notice ?? "Live-Abfragen sind gerade pausiert."
        case .offline: return "Keine Verbindung. Es werden die zuletzt geladenen Abfahrten gezeigt."
        }
    }
}

/// Writes of the route list: order, delete. Both go through the repository, so sync and the widget snapshot see them.
@MainActor
enum SavedRouteStore {
    static func move(_ ordered: [FavoriteRouteEntity], from offsets: IndexSet, to destination: Int, repository: Repository) {
        var changed = false
        for (index, route) in SavedRoutes.moved(ordered, from: offsets, to: destination).enumerated() where route.sortIndex != index {
            route.sortIndex = index
            route.touch()
            changed = true
        }
        if changed { repository.commit() }
    }

    /// Soft delete (sync removes it on the other devices too). Its reminders leave the system with it.
    static func delete(_ route: FavoriteRouteEntity, repository: Repository) {
        let id = route.id.uuidString
        repository.deleteFavorite(route)
        Task { await SavedRouteReminders.removeReminders(routeID: id) }
    }
}
