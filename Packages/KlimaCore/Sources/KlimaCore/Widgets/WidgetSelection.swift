import Foundation

/// What a live widget may say about its cache (docs/WIDGETS.md §6). The widgets never fetch; they show what the app cached
/// and how old it is.
public enum WidgetLiveState: Equatable, Sendable {
    /// The user has not granted live data (or has withdrawn it): no times are shown.
    case off
    /// Granted, but this cache was never written.
    case empty
    /// Written at this time and still recent enough to show its times.
    case fresh(Date)
    /// Written at this time, older than the freshness limit: the widget shows the hint to open the app.
    case stale(Date)

    public static func make(consent: WidgetConsent, fetchedAt: Date?, now: Date) -> WidgetLiveState {
        guard consent == .granted else { return .off }
        guard let fetchedAt else { return .empty }
        switch WidgetFreshness.of(fetchedAt: fetchedAt, now: now) {
        case .fresh: return .fresh(fetchedAt)
        case .stale: return .stale(fetchedAt)
        case .none: return .empty
        }
    }

    /// Whether the cache's times may be shown at all.
    public var hasTimes: Bool {
        switch self {
        case .fresh, .stale: true
        case .off, .empty: false
        }
    }

    /// Delays are the state of the last fetch: only shown while the cache is fresh.
    public var showsDelays: Bool {
        if case .fresh = self { return true }
        return false
    }

    /// When the cache was written, nil when nothing was.
    public var fetchedAt: Date? {
        switch self {
        case .fresh(let date), .stale(let date): date
        case .off, .empty: nil
        }
    }
}

/// Picks what one widget entry shows from the cache, for one moment. Pure: the timeline builder calls it for each entry.
public enum WidgetSelection {
    /// The next connections of one favourite route (`routeID` = the favourite's id as `uuidString`). A route the cache holds
    /// no list for was never fetched (not granted, failed, or not asked for): that is `.off` or `.empty`, never a fresh
    /// "no connection", because the cache's time stamp only covers the routes it holds.
    public static func connections(_ cache: WidgetConnectionCache?, routeID: String?, consent: WidgetConsent, now: Date,
                                   limit: Int = 3) -> (state: WidgetLiveState, items: [WidgetConnection]) {
        guard let routeID, let list = cache?.routes[routeID] else {
            return (WidgetLiveState.make(consent: consent, fetchedAt: nil, now: now), [])
        }
        let state = WidgetLiveState.make(consent: consent, fetchedAt: cache?.fetchedAt, now: now)
        guard state.hasTimes else { return (state, []) }
        return (state, WidgetFilter.upcoming(list, now: now, limit: limit))
    }

    /// The next departures of one station. A station without a board in the cache is `.off` or `.empty`, as for connections.
    public static func departures(_ cache: WidgetDepartureCache?, stationID: String?, consent: WidgetConsent, now: Date,
                                  limit: Int = 5) -> (state: WidgetLiveState, items: [WidgetDeparture]) {
        guard let stationID, let list = cache?.stations[stationID] else {
            return (WidgetLiveState.make(consent: consent, fetchedAt: nil, now: now), [])
        }
        let state = WidgetLiveState.make(consent: consent, fetchedAt: cache?.fetchedAt, now: now)
        guard state.hasTimes else { return (state, []) }
        return (state, WidgetFilter.upcoming(list, now: now, limit: limit))
    }

    /// The disruptions of the followed lines, as cached (a disruption is shown while its validity lasts).
    public static func disruptions(_ cache: WidgetDisruptionCache?, consent: WidgetConsent, now: Date,
                                   limit: Int = 3) -> (state: WidgetLiveState, items: [WidgetDisruption]) {
        let state = WidgetLiveState.make(consent: consent, fetchedAt: cache?.fetchedAt, now: now)
        guard state.hasTimes, let cache else { return (state, []) }
        let valid = cache.items.filter { item in item.validUntil.map { $0 >= now } ?? true }
        return (state, Array(valid.prefix(max(0, limit))))
    }
}
