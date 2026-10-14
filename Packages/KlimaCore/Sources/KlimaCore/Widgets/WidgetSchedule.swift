import Foundation

/// How old a live cache may be before a widget says so (docs/WIDGETS.md §6): the widget then shows "Stand HH:mm · App
/// öffnen für aktuelle Zeiten" instead of times it cannot vouch for.
public enum WidgetFreshness: Equatable, Sendable {
    /// Fetched recently enough to show its times.
    case fresh
    /// Fetched, but older than `maxAge`.
    case stale
    /// Never fetched (or the user has not granted live data).
    case none

    public static let maxAge: TimeInterval = 2 * 3600

    public static func of(fetchedAt: Date?, now: Date, maxAge: TimeInterval = WidgetFreshness.maxAge) -> WidgetFreshness {
        guard let fetchedAt else { return .none }
        // A cache from the future (clock change) is taken as fresh, never as a reason to hide it.
        return now.timeIntervalSince(fetchedAt) > maxAge ? .stale : .fresh
    }
}

/// Filtering of the cached lists for the widgets.
public enum WidgetFilter {
    /// Items still ahead of `now`. A departure within `grace` seconds counts as ahead (the train is still at the platform).
    /// Ordered by due time, at most `limit`.
    public static func upcoming<T: WidgetTimed>(_ items: [T], now: Date, limit: Int, grace: TimeInterval = 60) -> [T] {
        guard limit > 0 else { return [] }
        return items
            .filter { $0.departureTime.timeIntervalSince(now) >= -grace }
            .sorted { $0.departureTime < $1.departureTime }
            .prefix(limit)
            .map { $0 }
    }

    /// The items still ahead that are not cancelled, first `limit`: the "Nächste Abfahrt" of the small widgets.
    public static func nextRunning<T: WidgetTimed>(_ items: [T], now: Date, limit: Int = 1) -> [T] {
        upcoming(items.filter { !$0.isCancelled }, now: now, limit: limit)
    }
}

/// Timeline entries for the widgets that show live times. The system counts down by itself (`Text(_:style: .relative)`),
/// so entries are needed only where the list changes: when a listed departure leaves, and when the cache turns stale.
public enum WidgetTimeline {
    /// Entry dates from `now` on, sorted and unique, at most `limit`: `now`, one minute before each due time, and the moment
    /// the cache becomes stale.
    public static func entryDates<T: WidgetTimed>(for items: [T], fetchedAt: Date?, now: Date, limit: Int = 12,
                                                    maxAge: TimeInterval = WidgetFreshness.maxAge) -> [Date] {
        var dates: [Date] = [now]
        for item in items {
            // One minute before the train goes: the row moves to the next departure before the platform is empty.
            let due = item.departureTime.addingTimeInterval(-60)
            if due > now { dates.append(due) }
        }
        if let fetchedAt {
            let stale = fetchedAt.addingTimeInterval(maxAge)
            if stale > now { dates.append(stale) }
        }
        var unique: [Date] = []
        for date in dates.sorted() where unique.last != date { unique.append(date) }
        return Array(unique.prefix(max(1, limit)))
    }
}
