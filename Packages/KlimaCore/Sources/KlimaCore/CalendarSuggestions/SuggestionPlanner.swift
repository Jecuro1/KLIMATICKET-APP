import Foundation

// MARK: calendarsuggestions – which events become a card on the Übersicht (docs/CALENDAR_SUGGESTIONS.md §3): the next 14 days, no
// all-day events, the next occurrence of a series only, no event that has started or whose arrival has passed, nothing dismissed or
// snoozed, nothing already covered by a logged trip, nothing in the town you start from, one card per station and day, at most three.

/// One card: the event, the station it points to and the proposed arrival.
public struct CalendarSuggestion: Hashable, Sendable, Identifiable {
    /// `CalendarEventKey` of the event: what "Kein Zug", "Später" and the follow-up remember.
    public var key: String
    public var eventID: String
    public var title: String
    public var start: Date
    public var end: Date
    public var match: CalendarPlaceMatch
    public var bufferMinutes: Int

    public var id: String { key }
    /// Arrive by: start − buffer.
    public var arrival: Date { CalendarBuffer.arrival(eventStart: start, bufferMinutes: bufferMinutes) }
}

public enum CalendarSuggestionPlanner {
    public static let windowDays = 14
    public static let maxSuggestions = 3

    /// - Parameters:
    ///   - events: what the selected calendars hold around now (the source may return more; everything is filtered here).
    ///   - trips: logged trips (any order) – an event day with a trip to the station needs no card.
    ///   - origin: where trips usually start (home station, else the most frequent origin): a town match there needs no card.
    public static func plan(events: [CalendarEventInput], matcher: CalendarTripMatcher, prefs: CalendarSuggestionPrefs,
                            trips: [TripRecord], origin: Station?, now: Date, calendar: Calendar = .vienna,
                            limit: Int = maxSuggestions) -> [CalendarSuggestion] {
        let horizon = now.addingTimeInterval(Double(windowDays) * 86_400)
        let selected = Set(prefs.calendarIDs)
        let candidates = events
            .filter { !$0.isAllDay && $0.start > now && $0.start <= horizon && selected.contains($0.calendarID) && $0.end >= $0.start }
            .sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }

        var seenSeries: Set<String> = []
        var seenStationDays: Set<String> = []
        var out: [CalendarSuggestion] = []
        let tripIndex = TripDayIndex(trips: trips, calendar: calendar)
        // Calendars repeat their places (series, the same office, the same station): each location is read once per plan.
        var matches: [String: CalendarPlaceMatch?] = [:]
        for event in candidates {
            // An occurrence whose arrival has passed is no "next" one any more.
            let arrival = CalendarBuffer.arrival(eventStart: event.start, bufferMinutes: prefs.bufferMinutes)
            guard arrival > now else { continue }
            // A series counts once: its next occurrence (dismissing it hides that occurrence, the one after comes back later).
            if let series = event.seriesID, !seenSeries.insert(series).inserted { continue }
            guard let location = event.location else { continue }
            let found: CalendarPlaceMatch?
            if let cached = matches[location] {
                found = cached
            } else {
                found = matcher.match(location: location)
                matches[location] = found
            }
            guard let match = found else { continue }
            if let origin, isAtOrigin(match, origin: origin) { continue }
            let stationDay = match.station.id + "|" + String(Int(calendar.startOfDay(for: event.start).timeIntervalSince1970))
            // Around midnight the arrival is on the day before the event (00:10 − 20 min): a trip on either day covers it.
            guard !seenStationDays.contains(stationDay), !tripIndex.covers(match, on: event.start),
                  calendar.isDate(arrival, inSameDayAs: event.start) || !tripIndex.covers(match, on: arrival) else { continue }
            let key = event.key
            guard !prefs.isHidden(key: key, now: now) else { continue }
            seenStationDays.insert(stationDay)
            out.append(CalendarSuggestion(key: key, eventID: event.id, title: event.title, start: event.start, end: event.end,
                                          match: match, bufferMinutes: prefs.bufferMinutes))
            if out.count == limit { break }
        }
        return out
    }

    /// The next moment the cards change by the clock alone, while the app stays open on the Übersicht: a card's arrival passes (it
    /// goes), a „Später“ runs out (it comes back), or midnight in Vienna („Morgen“ becomes „Heute“, a follow-up's day begins).
    /// Never earlier than a minute from now.
    public static func nextChange(suggestions: [CalendarSuggestion], prefs: CalendarSuggestionPrefs, now: Date,
                                  calendar: Calendar = .vienna) -> Date {
        let today = calendar.startOfDay(for: now)
        var next = calendar.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(86_400)
        for s in suggestions where s.arrival > now { next = min(next, s.arrival) }
        for until in prefs.snoozed.values where until > now { next = min(next, until) }
        return max(next, now.addingTimeInterval(60))
    }

    /// The matched station is where you start, or – for a town match – the town you start in (Wien Meidling and "1060 Wien").
    static func isAtOrigin(_ match: CalendarPlaceMatch, origin: Station) -> Bool {
        if match.station.id == origin.id { return true }
        guard match.precision == .town else { return false }
        let town = CalendarStationCatalog.key(match.placeText)
        let from = CalendarStationCatalog.key(origin.name)
        if from == town || from.hasPrefix(town + " ") { return true }
        return origin.location.distanceKm(to: match.station.location) < 4
    }
}

/// Logged trips by Vienna day, for "already covered".
struct TripDayIndex {
    /// Day → (station id, station name key) of both ends of each trip that day.
    private var byDay: [Date: [(id: String?, key: String)]] = [:]
    private let calendar: Calendar

    init(trips: [TripRecord], calendar: Calendar) {
        self.calendar = calendar
        for trip in trips {
            let day = calendar.startOfDay(for: trip.date)
            byDay[day, default: []].append((trip.toStationID, CalendarStationCatalog.key(trip.toName)))
            // A trip that starts there that day means you were there too (only the way home was logged, or a „Hin und retour“
            // written from the far end).
            byDay[day, default: []].append((trip.fromStationID, CalendarStationCatalog.key(trip.fromName)))
        }
    }

    /// A trip that day ends or starts at the station (same id or name) – for a town match anywhere in the town ("Salzburg Süd" for
    /// "Salzburg").
    func covers(_ match: CalendarPlaceMatch, on date: Date) -> Bool {
        covers(stationID: match.station.id, stationName: match.station.name,
               town: match.precision == .town ? CalendarStationCatalog.key(match.placeText) : nil, on: date)
    }

    func covers(stationID: String, stationName: String, town: String?, on date: Date) -> Bool {
        guard let trips = byDay[calendar.startOfDay(for: date)] else { return false }
        let name = CalendarStationCatalog.key(stationName)
        return trips.contains { trip in
            if let id = trip.id, id == stationID { return true }
            let key = trip.key
            if key == name { return true }
            if let town, key == town || key.hasPrefix(town + " ") { return true }
            return false
        }
    }
}

/// Where trips usually start: the most frequent origin of the newest trips (ties → the one used last).
public enum CalendarOrigin {
    public static func mostFrequent(trips: [TripRecord], limit: Int = 30) -> (stationID: String, name: String)? {
        let newest = trips.sorted { $0.date > $1.date }.prefix(limit)
        var counts: [String: (count: Int, lastIndex: Int, name: String)] = [:]
        for (index, trip) in newest.enumerated() {
            guard let id = trip.fromStationID, !id.isEmpty else { continue }
            if var entry = counts[id] {
                entry.count += 1
                counts[id] = entry
            } else {
                counts[id] = (1, index, trip.fromName)
            }
        }
        guard let best = counts.max(by: { a, b in
            a.value.count != b.value.count ? a.value.count < b.value.count : a.value.lastIndex > b.value.lastIndex
        }) else { return nil }
        return (best.key, best.value.name)
    }
}

/// "Warst du gefahren? Salzburg Hbf": the day after a suggested event (and the day after that), when no trip to its station was
/// logged on the event's day and the card was not answered.
public enum CalendarFollowUpPlanner {
    /// Asked on the first and second day after the event, then forgotten.
    public static let askDays = 2
    public static let maxCards = 2

    public struct FollowUp: Hashable, Sendable, Identifiable {
        public var key: String
        public var entry: CalendarFollowUpEntry
        public var id: String { key }
    }

    public static func pending(prefs: CalendarSuggestionPrefs, trips: [TripRecord], now: Date,
                               calendar: Calendar = .vienna) -> [FollowUp] {
        let today = calendar.startOfDay(for: now)
        guard let first = calendar.date(byAdding: .day, value: -askDays, to: today) else { return [] }
        let index = TripDayIndex(trips: trips, calendar: calendar)
        var out: [FollowUp] = []
        for (key, entry) in prefs.followUps where prefs.dismissed[key] == nil {
            let day = calendar.startOfDay(for: entry.day)
            guard day < today, day >= first else { continue }
            // A trip on the event's day or on the arrival's (the evening before an event just after midnight) answers it.
            if index.covers(stationID: entry.stationID, stationName: entry.stationName, town: nil, on: entry.day)
                || index.covers(stationID: entry.stationID, stationName: entry.stationName, town: nil, on: entry.arrival) { continue }
            out.append(FollowUp(key: key, entry: entry))
        }
        out.sort { a, b in a.entry.day == b.entry.day ? a.key < b.key : a.entry.day > b.entry.day }
        return Array(out.prefix(maxCards))
    }

    /// Where the app starts reading the calendar so that every event a follow-up may still ask about is seen (`keepFollowUps`):
    /// the start of the day `askDays + 1` days ago.
    public static func readStart(now: Date, calendar: Calendar = .vienna) -> Date {
        calendar.date(byAdding: .day, value: -(askDays + 1), to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(-3 * 86_400)
    }
}
