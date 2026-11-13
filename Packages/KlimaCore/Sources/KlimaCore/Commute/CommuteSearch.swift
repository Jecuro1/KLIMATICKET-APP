import Foundation

// Pendel-Modus (docs/COMMUTE.md §7): the one door from the commute card to the timetable. The app hands over
// `LiveDataService.timetable`, which is nil unless live data is granted, switched on, not killed and online – so without
// consent this throws `consentRequired` before anything else happens and no request is made. The request itself goes
// through the shared HAFAS client and its `RequestThrottle` (40 requests per minute app-wide, 0,3 s apart).

public enum CommuteLiveError: Error, Equatable, Sendable {
    /// Live data is not available (no consent, switched off, kill switch or offline): nothing was requested.
    case consentRequired
}

public enum CommuteSearch {
    /// Connections asked per search: the card shows three, the advisor looks at the rest for an alternative.
    public static let results = 6
    /// The card refreshes at most this often while it is on screen.
    public static let minRefreshInterval: TimeInterval = 60

    /// One TripSearch from `origin` to `destination` departing at `date`: no stopovers, no polyline (list views never need them).
    public static func query(origin: Location, destination: Location, at date: Date) -> JourneyQuery {
        JourneyQuery(origin: origin, destination: destination, date: date, products: .all, results: results,
                     includeStopovers: false, includePolyline: false)
    }

    /// Throws `consentRequired` without touching `resolve` or the timetable when `timetable` is nil.
    public static func connections(timetable: (any TimetableService)?, at date: Date,
                                   resolve: @Sendable () async throws -> (origin: Location, destination: Location)) async throws -> JourneyPage {
        guard let timetable else { throw CommuteLiveError.consentRequired }
        let ends = try await resolve()
        return try await timetable.journeys(query(origin: ends.origin, destination: ends.destination, at: date))
    }

    /// Whether a refresh may run now: never twice within `minRefreshInterval` (pull-to-refresh included).
    public static func mayRefresh(lastFetch: Date?, now: Date) -> Bool {
        guard let lastFetch else { return true }
        return now.timeIntervalSince(lastFetch) >= minRefreshInterval
    }
}
