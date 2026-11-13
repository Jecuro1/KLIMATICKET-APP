import Foundation

// Pendel-Modus (docs/COMMUTE.md §2): finds the route someone rides again and again in the trips they logged. Pure: the caller
// passes the trips, the clock and the calendar; nothing is stored and nothing leaves the device.
//
// Rules (the plan's numbers, nothing tuned on real histories – the owner's device checklist covers that):
// - only rides of the last 56 days count, both directions of a pair together;
// - a pair qualifies with at least 6 rides (a round trip counts twice) on at least 3 different weeks and 2 different weekdays;
// - it is a confident guess when it qualifies and has clearly more rides than any other qualifying pair (1.5×), else „medium“;
// - clock times are used only when they can mean something: not all midnight (imported dates) and not one capture cluster
//   (both directions logged at the same evening minute) – the two directions must sit at least two hours apart.

/// What the detector believes the commute is.
public struct CommuteGuess: Hashable, Sendable {
    public enum Confidence: String, Sendable, Hashable {
        /// Clearly the most ridden pair: the Übersicht may ask „Ist das dein Arbeitsweg?“.
        case high
        /// Qualifies, but another pair is close (or tied): only offered as a suggestion in Einstellungen.
        case medium
    }

    /// Where the commute starts (home), and where it goes.
    public var origin: CommuteEndpoint
    public var destination: CommuteEndpoint
    /// Rides in the window (a round trip counts as two).
    public var rides: Int
    public var days: Int
    public var weeks: Int
    public var weekdays: Set<RouteWeekday>
    /// Median departure from the origin (rounded to 5 minutes), nil when the logged times say nothing.
    public var outboundMinute: Int?
    /// Median departure back from the destination, nil when the logged times say nothing.
    public var returnMinute: Int?
    /// Most rides of the pair were logged as „Hin und retour“.
    public var mostlyRoundTrips: Bool
    public var confidence: Confidence

    /// Direction-free identity of the pair (remembering a „Nein“).
    public var pairKey: String { CommuteDetector.pairKey(origin, destination) }
}

public enum CommuteDetector {
    public static let windowDays = 56
    public static let minRides = 6
    public static let minWeeks = 3
    public static let minWeekdays = 2
    /// The leading pair needs this many times the rides of the runner-up to be a confident guess.
    public static let leadFactor = 1.5
    /// The two directions' median times must be at least this far apart to count (else: one capture cluster).
    public static let minDirectionGapMinutes = 120
    /// The times of one direction may scatter at most this much (median absolute deviation) to mean a clock time.
    public static let maxSpreadMinutes = 90

    /// The best guess, or nil when no pair qualifies.
    public static func guess(trips: [TripRecord], now: Date, calendar: Calendar = .vienna, homeStationID: String? = nil) -> CommuteGuess? {
        candidates(trips: trips, now: now, calendar: calendar, homeStationID: homeStationID).first
    }

    /// Every qualifying pair, most ridden first. Only the first can be `.high`.
    public static func candidates(trips: [TripRecord], now: Date, calendar: Calendar = .vienna,
                                  homeStationID: String? = nil) -> [CommuteGuess] {
        let start = calendar.date(byAdding: .day, value: -windowDays, to: now) ?? now.addingTimeInterval(-Double(windowDays) * 86_400)
        let rides = collapse(trips.filter { $0.date >= start && $0.date <= now })
        var tallies: [String: Tally] = [:]
        var order: [String] = []
        for ride in rides.sorted(by: { $0.date < $1.date }) {
            let key = pairKey(ride.from, ride.to)
            if tallies[key] == nil { tallies[key] = Tally(first: ride.from, second: ride.to); order.append(key) }
            tallies[key]?.add(ride, calendar: calendar)
        }
        var qualified = order.compactMap { tallies[$0] }.filter(\.qualifies)
        qualified.sort { a, b in
            if a.rides != b.rides { return a.rides > b.rides }
            if a.weeks.count != b.weeks.count { return a.weeks.count > b.weeks.count }
            if a.days.count != b.days.count { return a.days.count > b.days.count }
            return a.key < b.key
        }
        return qualified.enumerated().map { index, tally in
            let confident: Bool
            if index == 0 {
                if qualified.count > 1 { confident = Double(tally.rides) >= leadFactor * Double(qualified[1].rides) } else { confident = true }
            } else {
                confident = false
            }
            return tally.guess(confidence: confident ? .high : .medium, homeStationID: homeStationID)
        }
    }

    /// The same key for A→B and B→A.
    public static func pairKey(_ a: CommuteEndpoint, _ b: CommuteEndpoint) -> String {
        let keys = [a.key, b.key].sorted()
        return keys[0] + "|" + keys[1]
    }

    // MARK: Rides

    struct Ride {
        var from: CommuteEndpoint
        var to: CommuteEndpoint
        var date: Date
        var isRoundTrip: Bool
    }

    /// One ride per trip; the legs of one journey (docs/JOURNEYS.md) become one ride from the first start to the last stop.
    static func collapse(_ trips: [TripRecord]) -> [Ride] {
        var out: [Ride] = []
        var journeys: [UUID: [TripRecord]] = [:]
        for trip in trips {
            if let journeyID = trip.journeyID { journeys[journeyID, default: []].append(trip) } else { out.append(ride(trip, last: trip)) }
        }
        for legs in journeys.values {
            let ordered = legs.sorted { $0.legIndex != $1.legIndex ? $0.legIndex < $1.legIndex : $0.date < $1.date }
            guard let first = ordered.first, let last = ordered.last else { continue }
            out.append(ride(first, last: last))
        }
        return out.filter { $0.from.key != $0.to.key }
    }

    private static func ride(_ first: TripRecord, last: TripRecord) -> Ride {
        Ride(from: CommuteEndpoint(stationID: first.fromStationID, name: first.fromName),
             to: CommuteEndpoint(stationID: last.toStationID, name: last.toName),
             date: first.date, isRoundTrip: first.isRoundTrip)
    }

    // MARK: Tally

    struct Tally {
        /// The pair in the order of its first ride (a deterministic fallback for the direction).
        var first: CommuteEndpoint
        var second: CommuteEndpoint
        var rides = 0
        var roundTrips = 0
        var entries = 0
        var days: Set<Date> = []
        var weeks: Set<String> = []
        var weekdays: Set<RouteWeekday> = []
        /// Departures (minute of day) from `first` and from `second`; round trips add their start only.
        var minutesFromFirst: [Int] = []
        var minutesFromSecond: [Int] = []
        /// How often each end was the start of an entry (round trips twice: they say where home is).
        var startsAtFirst = 0
        var startsAtSecond = 0

        init(first: CommuteEndpoint, second: CommuteEndpoint) {
            self.first = first
            self.second = second
        }

        var key: String { CommuteDetector.pairKey(first, second) }

        var qualifies: Bool {
            rides >= CommuteDetector.minRides && weeks.count >= CommuteDetector.minWeeks && weekdays.count >= CommuteDetector.minWeekdays
        }

        mutating func add(_ ride: Ride, calendar: Calendar) {
            let fromFirst = ride.from.key == first.key
            // The newest names win (a renamed station shows its current name).
            if fromFirst { first = ride.from; second = ride.to } else { second = ride.from; first = ride.to }
            entries += 1
            rides += ride.isRoundTrip ? 2 : 1
            if ride.isRoundTrip { roundTrips += 1 }
            days.insert(calendar.startOfDay(for: ride.date))
            let week = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: ride.date)
            weeks.insert("\(week.yearForWeekOfYear ?? 0)-\(week.weekOfYear ?? 0)")
            if let day = RouteWeekday(calendarWeekday: calendar.component(.weekday, from: ride.date)) { weekdays.insert(day) }
            let parts = calendar.dateComponents([.hour, .minute], from: ride.date)
            let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            if fromFirst { minutesFromFirst.append(minute) } else { minutesFromSecond.append(minute) }
            let weight = ride.isRoundTrip ? 2 : 1
            if fromFirst { startsAtFirst += weight } else { startsAtSecond += weight }
        }

        func guess(confidence: CommuteGuess.Confidence, homeStationID: String?) -> CommuteGuess {
            let times = CommuteDetector.clockTimes(fromFirst: minutesFromFirst, fromSecond: minutesFromSecond)
            let firstIsOrigin: Bool
            if let times {
                firstIsOrigin = times.first <= times.second
            } else if let home = homeStationID, first.stationID == home || second.stationID == home {
                firstIsOrigin = first.stationID == home
            } else {
                firstIsOrigin = startsAtFirst >= startsAtSecond
            }
            let origin = firstIsOrigin ? first : second
            let destination = firstIsOrigin ? second : first
            return CommuteGuess(origin: origin, destination: destination, rides: rides, days: days.count, weeks: weeks.count,
                                weekdays: weekdays,
                                outboundMinute: times.map { firstIsOrigin ? $0.first : $0.second },
                                returnMinute: times.map { firstIsOrigin ? $0.second : $0.first },
                                mostlyRoundTrips: roundTrips * 2 > entries, confidence: confidence)
        }
    }

    // MARK: Clock times

    /// The two directions' typical departures (rounded to 5 minutes), or nil when the logged times cannot mean departures:
    /// all at midnight (dates without a time), one direction only, scattered times, or both directions in one cluster.
    static func clockTimes(fromFirst: [Int], fromSecond: [Int]) -> (first: Int, second: Int)? {
        let a = fromFirst.filter { $0 != 0 }, b = fromSecond.filter { $0 != 0 }
        guard a.count >= 2, b.count >= 2 else { return nil }
        let ma = median(a), mb = median(b)
        guard abs(ma - mb) >= minDirectionGapMinutes else { return nil }
        guard spread(a, around: ma) <= maxSpreadMinutes, spread(b, around: mb) <= maxSpreadMinutes else { return nil }
        return (roundTo5(ma), roundTo5(mb))
    }

    static func median(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    /// Median absolute deviation in minutes.
    static func spread(_ values: [Int], around center: Int) -> Int {
        median(values.map { abs($0 - center) })
    }

    static func roundTo5(_ minute: Int) -> Int {
        CommutePlan.clamp(Int((Double(minute) / 5).rounded()) * 5)
    }
}
