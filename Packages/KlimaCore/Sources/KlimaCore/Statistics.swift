import Foundation

public struct MonthBucket: Hashable, Sendable, Identifiable {
    public var month: Date          // first day of month
    public var value: Double
    public var trips: Int
    public var distanceKm: Double
    public var id: Date { month }
}

public struct ModeBucket: Hashable, Sendable, Identifiable {
    public var mode: TransportMode
    public var trips: Int
    public var value: Double
    public var distanceKm: Double
    public var id: String { mode.rawValue }
}

public struct WeekdayBucket: Hashable, Sendable, Identifiable {
    /// 1 = Montag … 7 = Sonntag
    public var weekday: Int
    public var trips: Int
    public var value: Double
    public var id: Int { weekday }

    public var shortName: String { ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"][max(0, min(6, weekday - 1))] }
}

public struct DayActivity: Hashable, Sendable, Identifiable {
    public var day: Date
    public var trips: Int
    public var value: Double
    public var id: Date { day }
}

public struct RouteStat: Hashable, Sendable, Identifiable {
    public var key: String
    public var fromName: String
    public var toName: String
    /// Logged entries on this route (a round trip counts once, like "Fahrten" everywhere else).
    public var trips: Int
    public var value: Double
    public var distanceKm: Double
    /// Directions travelled (a round trip counts twice) – `legs - trips` entries were "Hin & retour".
    public var legs: Int = 0
    public var id: String { key }
}

public struct TravelRecords: Hashable, Sendable {
    public var longestTrip: TripRecord?
    public var mostValuableTrip: TripRecord?
    public var bestMonth: MonthBucket?
    public var currentStreakDays: Int
    public var longestStreakDays: Int
    public var statesVisited: Set<String>
    public var uniqueStations: Int
}

public enum StatsAggregator {
    public static func months(_ trips: [TripRecord], calendar: Calendar = .vienna) -> [MonthBucket] {
        var map: [Date: MonthBucket] = [:]
        var memo = DayMemo(calendar)
        var journeys = JourneyCounter<Date>()
        for t in trips {
            guard let m = memo.startOfMonth(t.date) else { continue }
            var b = map[m] ?? MonthBucket(month: m, value: 0, trips: 0, distanceKm: 0)
            b.value += t.totalValue
            b.trips += journeys.count(t, in: m)
            b.distanceKm += t.totalDistanceKm
            map[m] = b
        }
        return map.values.sorted { $0.month < $1.month }
    }

    /// All months of a ticket period (including empty ones) – keeps bar charts aligned.
    public static func months(_ trips: [TripRecord], in ticket: TicketPeriod, calendar: Calendar = .vienna) -> [MonthBucket] {
        let filled = Dictionary(uniqueKeysWithValues: months(trips.filter { ticket.contains($0.date) }, calendar: calendar).map { ($0.month, $0) })
        var result: [MonthBucket] = []
        guard var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: ticket.start)) else { return [] }
        while cursor <= ticket.end {
            result.append(filled[cursor] ?? MonthBucket(month: cursor, value: 0, trips: 0, distanceKm: 0))
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    public static func modes(_ trips: [TripRecord]) -> [ModeBucket] {
        var map: [TransportMode: ModeBucket] = [:]
        for t in trips {
            var b = map[t.mode] ?? ModeBucket(mode: t.mode, trips: 0, value: 0, distanceKm: 0)
            b.trips += 1
            b.value += t.totalValue
            b.distanceKm += t.totalDistanceKm
            map[t.mode] = b
        }
        return map.values.sorted { $0.value > $1.value }
    }

    public static func weekdays(_ trips: [TripRecord], calendar: Calendar = .vienna) -> [WeekdayBucket] {
        var buckets = (1...7).map { WeekdayBucket(weekday: $0, trips: 0, value: 0) }
        var memo = DayMemo(calendar)
        var journeys = JourneyCounter<Int>()
        for t in trips {
            // Calendar weekday: 1 = Sunday … 7 = Saturday → convert to Monday-first.
            let wd = memo.weekday(t.date)
            let idx = (wd + 5) % 7
            buckets[idx].trips += journeys.count(t, in: idx)
            buckets[idx].value += t.totalValue
        }
        return buckets
    }

    public static func days(_ trips: [TripRecord], calendar: Calendar = .vienna) -> [DayActivity] {
        var map: [Date: DayActivity] = [:]
        var memo = DayMemo(calendar)
        var journeys = JourneyCounter<Date>()
        for t in trips {
            let d = memo.startOfDay(t.date)
            var a = map[d] ?? DayActivity(day: d, trips: 0, value: 0)
            a.trips += journeys.count(t, in: d)
            a.value += t.totalValue
            map[d] = a
        }
        return map.values.sorted { $0.day < $1.day }
    }

    public static func topRoutes(_ trips: [TripRecord], limit: Int = 5) -> [RouteStat] {
        var map: [String: RouteStat] = [:]
        // A journey is one route, start of its first leg → end of its last (docs/JOURNEYS.md).
        for t in JourneySummary.collapsed(trips) {
            var r = map[t.routeKey] ?? RouteStat(key: t.routeKey, fromName: t.fromName, toName: t.toName, trips: 0, value: 0, distanceKm: 0)
            r.trips += 1
            r.legs += t.legs
            r.value += t.totalValue
            r.distanceKm += t.totalDistanceKm
            map[t.routeKey] = r
        }
        // Key as the last tie-breaker: a stable order on every render (dictionary order is not).
        return Array(map.values.sorted { ($0.trips, $0.value, $1.key) > ($1.trips, $1.value, $0.key) }.prefix(limit))
    }

    public static func records(_ trips: [TripRecord], now: Date = Date(), calendar: Calendar = .vienna) -> TravelRecords {
        var memo = DayMemo(calendar)
        let dayList = Set(trips.map { memo.startOfDay($0.date) }).sorted()
        var longest = 0, run = 0
        var previous: Date?
        for d in dayList {
            if let p = previous, calendar.dateComponents([.day], from: p, to: d).day == 1 { run += 1 } else { run = 1 }
            longest = max(longest, run)
            previous = d
        }
        // Current streak: consecutive days ending today or yesterday.
        var current = 0
        let today = calendar.startOfDay(for: now)
        let daySet = Set(dayList)
        var cursor = daySet.contains(today) ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        while daySet.contains(cursor) {
            current += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        var stations = Set<String>()
        var states = Set<String>()
        for t in trips {
            stations.insert(t.fromStationID ?? t.fromName.lowercased())
            stations.insert(t.toStationID ?? t.toName.lowercased())
            states.formUnion(t.states)
        }
        // Records are about whole journeys; stations and states above count every leg.
        let journeys = trips.contains(where: \.isJourneyLeg) ? JourneySummary.collapsed(trips) : trips
        return TravelRecords(
            longestTrip: journeys.max { $0.distanceKm < $1.distanceKm },
            mostValuableTrip: journeys.max { $0.totalValue < $1.totalValue },
            bestMonth: months(trips, calendar: calendar).max { $0.value < $1.value },
            currentStreakDays: current,
            longestStreakDays: longest,
            statesVisited: states.subtracting([FederalState.foreign.rawValue]),
            uniqueStations: stations.count
        )
    }
}

/// Counts a "Fahrt" once per bucket: a plain trip always, a journey's legs only the first time their journey shows up in
/// the bucket (docs/JOURNEYS.md).
struct JourneyCounter<Bucket: Hashable> {
    private var seen: [Bucket: Set<UUID>] = [:]

    mutating func count(_ trip: TripRecord, in bucket: Bucket) -> Int {
        guard let journey = trip.journeyID else { return 1 }
        return seen[bucket, default: []].insert(journey).inserted ? 1 : 0
    }
}
