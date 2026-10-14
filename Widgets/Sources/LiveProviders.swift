import WidgetKit
import SwiftUI
import KlimaCore

// Timelines of the live widgets (docs/WIDGETS.md §5–6). They read WidgetCache only: no network, no SwiftData. An entry
// is made at each moment the list changes (a train leaves, the cache turns stale), so the countdowns stay right without a
// reload. The app reloads the timelines when it writes a cache that really changed.

/// What the connection widget shows for one moment.
struct ConnectionEntry: TimelineEntry {
    let date: Date
    /// The favourite's title; nil while no favourite is chosen.
    let title: String?
    let state: WidgetLiveState
    let items: [WidgetConnection]

    var relevance: TimelineEntryRelevance? {
        guard state.hasTimes, let first = items.first else { return nil }
        // The Smart Stack shows it shortly before the train leaves.
        let minutes = first.departureTime.timeIntervalSince(date) / 60
        return TimelineEntryRelevance(score: (-1.0...30.0).contains(minutes) ? 1 : 0.2)
    }
}

/// What the station widget shows for one moment.
struct DepartureEntry: TimelineEntry {
    let date: Date
    /// The station's id (the tap opens its board in the app).
    let stationID: String?
    /// The station's name; nil while no station is available.
    let stationName: String?
    let facilities: [WidgetFacility]
    let state: WidgetLiveState
    let items: [WidgetDeparture]

    var relevance: TimelineEntryRelevance? {
        guard state.hasTimes, let first = items.first else { return nil }
        let minutes = first.departureTime.timeIntervalSince(date) / 60
        return TimelineEntryRelevance(score: (-1.0...20.0).contains(minutes) ? 0.9 : 0.1)
    }
}

/// What the disruption widget shows for one moment.
struct DisruptionEntry: TimelineEntry {
    let date: Date
    let state: WidgetLiveState
    let items: [WidgetDisruption]
    let followedLines: [String]
}

enum LiveTimeline {
    /// Entries at `dates` (sorted, unique, from `now`), each built by `make`. A timeline with one entry asks again later.
    static func timeline<Entry: TimelineEntry>(_ dates: [Date], now: Date, make: (Date) -> Entry) -> Timeline<Entry> {
        let entries = dates.map(make)
        let policy: TimelineReloadPolicy = entries.count > 1 ? .atEnd : .after(now.addingTimeInterval(30 * 60))
        return Timeline(entries: entries, policy: policy)
    }
}

// MARK: - Nächste Verbindung

struct NextConnectionProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ConnectionEntry {
        ConnectionEntry(date: .now, title: "Pendeln", state: .fresh(.now), items: WidSamples.connections(now: .now))
    }

    func snapshot(for configuration: NextConnectionConfigIntent, in context: Context) async -> ConnectionEntry {
        if context.isPreview { return placeholder(in: context) }
        return Self.entries(for: configuration, now: .now).first ?? placeholder(in: context)
    }

    func timeline(for configuration: NextConnectionConfigIntent, in context: Context) async -> Timeline<ConnectionEntry> {
        let now = Date()
        let routeID = configuration.favorite?.id.uuidString
        let dates = Self.dates(routeID: routeID, now: now)
        return LiveTimeline.timeline(dates, now: now) { Self.entry(configuration, routeID: routeID, at: $0) }
    }

    static func entries(for configuration: NextConnectionConfigIntent, now: Date) -> [ConnectionEntry] {
        let routeID = configuration.favorite?.id.uuidString
        return dates(routeID: routeID, now: now).map { entry(configuration, routeID: routeID, at: $0) }
    }

    /// The moments the list changes: built from the whole cached route, not the three shown, so later departures appear too.
    private static func dates(routeID: String?, now: Date) -> [Date] {
        let cache = WidgetCache.connections
        let all = routeID.flatMap { cache?.routes[$0] } ?? []
        return WidgetTimeline.entryDates(for: all, fetchedAt: cache?.fetchedAt, now: now)
    }

    private static func entry(_ configuration: NextConnectionConfigIntent, routeID: String?, at date: Date) -> ConnectionEntry {
        let selection = WidgetSelection.connections(WidgetCache.connections, routeID: routeID, consent: WidgetCache.consent,
                                                    now: date)
        return ConnectionEntry(date: date, title: title(configuration), state: selection.state, items: selection.items)
    }

    /// The favourite's current name from the snapshot (renamed since the choice), else the name the choice carries.
    private static func title(_ configuration: NextConnectionConfigIntent) -> String? {
        guard let favorite = configuration.favorite else { return nil }
        return WidgetSnapshot.load()?.favorites.first { $0.id == favorite.id }?.title ?? favorite.title
    }
}

// MARK: - Abfahrten

struct DepartureProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DepartureEntry {
        DepartureEntry(date: .now, stationID: nil, stationName: "Innsbruck Hbf", facilities: [.bikeRide, .barrierFree], state: .fresh(.now),
                       items: WidSamples.departures(now: .now))
    }

    func snapshot(for configuration: DeparturesConfigIntent, in context: Context) async -> DepartureEntry {
        if context.isPreview { return placeholder(in: context) }
        return Self.entries(for: configuration, now: .now).first ?? placeholder(in: context)
    }

    func timeline(for configuration: DeparturesConfigIntent, in context: Context) async -> Timeline<DepartureEntry> {
        let now = Date()
        let stationID = Self.stationID(configuration)
        let dates = Self.dates(stationID: stationID, now: now)
        return LiveTimeline.timeline(dates, now: now) { Self.entry(configuration, stationID: stationID, at: $0) }
    }

    static func entries(for configuration: DeparturesConfigIntent, now: Date) -> [DepartureEntry] {
        let stationID = stationID(configuration)
        return dates(stationID: stationID, now: now).map { entry(configuration, stationID: stationID, at: $0) }
    }

    /// The chosen station, else the home station of the app's list.
    private static func stationID(_ configuration: DeparturesConfigIntent) -> String? {
        if let station = configuration.station { return station.id }
        return WidgetCache.stations?.stations.first(where: \.isHome)?.id
    }

    private static func dates(stationID: String?, now: Date) -> [Date] {
        let cache = WidgetCache.departures
        let all = stationID.flatMap { cache?.stations[$0] } ?? []
        return WidgetTimeline.entryDates(for: all, fetchedAt: cache?.fetchedAt, now: now)
    }

    private static func entry(_ configuration: DeparturesConfigIntent, stationID: String?, at date: Date) -> DepartureEntry {
        let selection = WidgetSelection.departures(WidgetCache.departures, stationID: stationID, consent: WidgetCache.consent,
                                                   now: date)
        let station = WidgetCache.stations?.stations.first { $0.id == stationID }
        let name = configuration.station?.name ?? station?.name
        return DepartureEntry(date: date, stationID: stationID, stationName: name, facilities: station?.facilities ?? [],
                              state: selection.state, items: selection.items)
    }
}

// MARK: - Störungen auf meinen Linien

struct DisruptionProvider: TimelineProvider {
    func placeholder(in context: Context) -> DisruptionEntry {
        DisruptionEntry(date: .now, state: .fresh(.now), items: WidSamples.disruptions, followedLines: ["S 4"])
    }

    func getSnapshot(in context: Context, completion: @escaping (DisruptionEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DisruptionEntry>) -> Void) {
        let now = Date()
        let cache = WidgetCache.disruptions
        // Moments that change the list: a disruption ends, or the cache turns stale.
        var dates = [now]
        for item in cache?.items ?? [] {
            if let until = item.validUntil, until > now { dates.append(until) }
        }
        if let fetched = cache?.fetchedAt {
            let stale = fetched.addingTimeInterval(WidgetFreshness.maxAge)
            if stale > now { dates.append(stale) }
        }
        let unique = Array(Set(dates)).sorted().prefix(12)
        completion(LiveTimeline.timeline(Array(unique), now: now) { entry(at: $0) })
    }

    private func entry(at date: Date) -> DisruptionEntry {
        let selection = WidgetSelection.disruptions(WidgetCache.disruptions, consent: WidgetCache.consent, now: date)
        return DisruptionEntry(date: date, state: selection.state, items: selection.items,
                               followedLines: WidgetCache.disruptions?.lines ?? [])
    }
}
