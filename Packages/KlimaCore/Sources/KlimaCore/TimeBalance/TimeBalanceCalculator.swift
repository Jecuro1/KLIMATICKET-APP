import Foundation

// MARK: - „Zeitbilanz“: how long you travelled, what the car would have taken, what delays cost (docs/TIME_BALANCE.md)

/// How the ride time compares with driving the same trips. The car figure is `CarComparisonResult.drivingHours` – the
/// one the Auto-Vergleich shows; both sides are rough, so a small gap counts as „about equal“.
public enum TimeBalanceCarVerdict: Hashable, Sendable {
    /// No car figure (no trips or no kilometres).
    case unavailable
    /// Longer than driving: „Mehrzeit im Öffi“ – never „Zeit gespart“.
    case transitLonger(extraMinutes: Double)
    /// Within the tolerance.
    case aboutEqual
    /// Shorter than driving: „Zeit gewonnen“.
    case transitShorter(gainedMinutes: Double)

    /// A gap up to 5 minutes or 5 % of the car time (whichever is larger) is „about equal“: both figures are averages.
    public static func tolerance(carMinutes: Double) -> Double { max(5, 0.05 * max(0, carMinutes)) }

    public static func compare(transitMinutes: Double, carMinutes: Double) -> TimeBalanceCarVerdict {
        guard carMinutes > 0, carMinutes.isFinite, transitMinutes.isFinite else { return .unavailable }
        let gap = transitMinutes - carMinutes
        if abs(gap) <= tolerance(carMinutes: carMinutes) { return .aboutEqual }
        return gap > 0 ? .transitLonger(extraMinutes: gap) : .transitShorter(gainedMinutes: -gap)
    }
}

/// One week of the chart (Monday to Monday, Vienna).
public struct TimeBalanceWeek: Hashable, Sendable, Identifiable {
    public var start: Date
    public var end: Date
    /// Ride time of the week's trips (up to now), minutes.
    public var minutes: Double
    /// The part that was entered or comes from departure and arrival.
    public var recordedMinutes: Double
    /// The week overlaps the chosen period (others are drawn faint).
    public var isInRange: Bool
    /// The week holds the reference day (today, or the period's end).
    public var isCurrent: Bool

    public var id: Date { start }
    public var estimatedMinutes: Double { max(0, minutes - recordedMinutes) }
}

public struct TimeBalanceModeShare: Hashable, Sendable, Identifiable {
    public var mode: TransportMode
    public var minutes: Double
    /// Share of the period's ride time (0…1).
    public var share: Double
    public var id: TransportMode { mode }
}

/// The longest single trip of the period: a journey counts as one trip, a round trip by one direction.
public struct TimeBalanceLongestTrip: Hashable, Sendable {
    public var fromName: String
    public var toName: String
    public var date: Date
    /// One direction, minutes.
    public var minutes: Double
    /// At least one ride of it comes from the speed model.
    public var isEstimated: Bool
    public var legCount: Int
}

/// Recorded arrival delays of the period (trips without a recorded delay are not counted at all).
public struct TimeBalanceDelays: Hashable, Sendable {
    public var totalMinutes: Double
    /// Trips with a recorded delay (0 included).
    public var recordedTrips: Int
    /// Of those, arrived at least a minute late.
    public var delayedTrips: Int
    public var longestMinutes: Int
}

public struct TimeBalance: Hashable, Sendable {
    public var rangeStart: Date
    public var rangeEnd: Date
    /// min(now, end of the period): the last day that counts.
    public var reference: Date
    /// „Fahrten“ in the period up to now (a journey counts once).
    public var tripCount: Int
    /// Rides (a round trip is two, every leg of a journey one).
    public var rideCount: Int
    /// Trips with at least one estimated ride.
    public var estimatedTripCount: Int
    public var enteredMinutes: Double
    public var timetableMinutes: Double
    public var estimatedMinutes: Double
    /// Hours behind the wheel for the same trips (`CarComparison`, the Auto-Vergleich's figure), minutes.
    public var carMinutes: Double
    public var carVerdict: TimeBalanceCarVerdict
    /// nil when no trip of the period has a recorded delay.
    public var delays: TimeBalanceDelays?
    /// Oldest first, `weekCount` weeks ending with the reference week.
    public var weeks: [TimeBalanceWeek]
    /// Largest first.
    public var modes: [TimeBalanceModeShare]
    public var longest: TimeBalanceLongestTrip?
    /// Weeks from the period's start to the reference day (at least 1 once the period has begun).
    public var weeksElapsed: Double

    public var totalMinutes: Double { enteredMinutes + timetableMinutes + estimatedMinutes }
    public var recordedMinutes: Double { enteredMinutes + timetableMinutes }
    /// Share of the ride time that was not estimated (0…1).
    public var recordedShare: Double { totalMinutes > 0 ? recordedMinutes / totalMinutes : 0 }
    public var averageMinutesPerWeek: Double { weeksElapsed > 0 ? totalMinutes / weeksElapsed : 0 }
    public var isEmpty: Bool { rideCount == 0 }
}

public enum TimeBalanceCalculator {
    /// Minutes behind the wheel for `trip` – exactly the per-trip term of `CarComparison.compare` (road km per leg ×
    /// legs at the car's average speed), so the sum over the same trips equals the Auto-Vergleich.
    public static func carMinutes(_ trip: TimeTripInput, profile: CarProfile) -> Double {
        Double(trip.legs) * CarComparison.drivingHours(roadKmPerLeg: profile.roadKm(railKm: trip.distanceKm)) * 60
    }

    /// The time balance of `range` (both ends included, like `TicketPeriod.contains`).
    /// - Parameters:
    ///   - trips: every trip that may matter – the chart's weeks can reach before the period (they are drawn faint), the
    ///     totals use only trips inside `range` and up to `now` (like the Auto-Vergleich).
    ///   - carProfile: the holder's car settings (road-distance factor).
    public static func compute(trips: [TimeTripInput], range: ClosedRange<Date>, now: Date, carProfile: CarProfile,
                               model: TravelTimeModel = .standard, calendar: Calendar = .vienna,
                               weekCount: Int = 12) -> TimeBalance {
        let past = trips.filter { $0.date <= now }
        let resolved = TravelTimeResolver.resolveAll(past, model: model, calendar: calendar)
        let inRange = past.filter { range.contains($0.date) }
        let reference = min(now, range.upperBound)

        var entered = 0.0, timetable = 0.0, estimated = 0.0, car = 0.0
        var rides = 0
        var byMode: [TransportMode: Double] = [:]
        var delayTotal = 0.0, delayRecorded = 0, delayLate = 0, delayLongest = 0
        var groups: [UUID: [TimeTripInput]] = [:]
        var order: [UUID] = []
        for trip in inRange {
            guard let time = resolved[trip.id] else { continue }
            switch time.source {
            case .entered: entered += time.minutes
            case .timetable: timetable += time.minutes
            case .estimated: estimated += time.minutes
            }
            rides += trip.legs
            byMode[trip.mode, default: 0] += time.minutes
            car += carMinutes(trip, profile: carProfile)
            if let delay = trip.recordedDelayMinutes {
                delayRecorded += 1
                delayTotal += Double(delay)
                if delay >= 1 { delayLate += 1 }
                delayLongest = max(delayLongest, delay)
            }
            let key = trip.journeyID ?? trip.id
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(trip)
        }

        // Trips (a journey once) and the longest of them by one direction.
        var longest: TimeBalanceLongestTrip?
        var estimatedTrips = 0
        for key in order {
            guard let legs = groups[key]?.sorted(by: { ($0.legIndex, $0.date) < ($1.legIndex, $1.date) }),
                  let first = legs.first, let last = legs.last else { continue }
            let times = legs.compactMap { resolved[$0.id] }
            let isEstimated = times.contains { $0.source == .estimated }
            if isEstimated { estimatedTrips += 1 }
            let minutes = times.reduce(0) { $0 + $1.minutesPerDirection }
            let candidate = TimeBalanceLongestTrip(fromName: first.fromName, toName: last.toName, date: first.date, minutes: minutes,
                                                   isEstimated: isEstimated, legCount: legs.count)
            if let current = longest {
                if minutes > current.minutes + 1e-9 || (abs(minutes - current.minutes) <= 1e-9 && first.date < current.date) {
                    longest = candidate
                }
            } else {
                longest = candidate
            }
        }

        let total = entered + timetable + estimated
        let modes = byMode.filter { $0.value > 0 }
            .map { TimeBalanceModeShare(mode: $0.key, minutes: $0.value, share: total > 0 ? $0.value / total : 0) }
            .sorted { lhs, rhs in
                if abs(lhs.minutes - rhs.minutes) > 1e-9 { return lhs.minutes > rhs.minutes }
                return modeOrder(lhs.mode) < modeOrder(rhs.mode)
            }

        let delays = delayRecorded > 0
            ? TimeBalanceDelays(totalMinutes: delayTotal, recordedTrips: delayRecorded, delayedTrips: delayLate, longestMinutes: delayLongest)
            : nil

        return TimeBalance(
            rangeStart: range.lowerBound, rangeEnd: range.upperBound, reference: reference,
            tripCount: order.count, rideCount: rides, estimatedTripCount: estimatedTrips,
            enteredMinutes: entered, timetableMinutes: timetable, estimatedMinutes: estimated,
            carMinutes: car, carVerdict: .compare(transitMinutes: total, carMinutes: car),
            delays: delays,
            weeks: weeks(past, resolved: resolved, range: range, reference: reference, count: weekCount, calendar: calendar),
            modes: modes, longest: longest,
            weeksElapsed: weeksElapsed(range: range, reference: reference, calendar: calendar))
    }

    /// `count` weeks ending with the week of `reference`, each with the ride time of its trips.
    static func weeks(_ trips: [TimeTripInput], resolved: [UUID: ResolvedTravelTime], range: ClosedRange<Date>, reference: Date,
                      count: Int, calendar: Calendar) -> [TimeBalanceWeek] {
        guard count > 0, let current = calendar.dateInterval(of: .weekOfYear, for: reference) else { return [] }
        var intervals: [DateInterval] = []
        for offset in stride(from: count - 1, through: 0, by: -1) {
            // Step back from the current week's Monday; the calendar gives each week its own length (DST weeks have 167 or
            // 169 hours).
            guard let day = calendar.date(byAdding: .weekOfYear, value: -offset, to: current.start),
                  let week = calendar.dateInterval(of: .weekOfYear, for: day) else { continue }
            intervals.append(week)
        }
        guard let first = intervals.first, let last = intervals.last else { return [] }
        var minutes = [Date: Double](), recorded = [Date: Double]()
        for trip in trips where trip.date >= first.start && trip.date < last.end {
            guard let time = resolved[trip.id], let week = calendar.dateInterval(of: .weekOfYear, for: trip.date) else { continue }
            minutes[week.start, default: 0] += time.minutes
            if time.source.isRecorded { recorded[week.start, default: 0] += time.minutes }
        }
        return intervals.map { week in
            TimeBalanceWeek(start: week.start, end: week.end, minutes: minutes[week.start] ?? 0, recordedMinutes: recorded[week.start] ?? 0,
                            isInRange: week.start <= range.upperBound && week.end > range.lowerBound,
                            isCurrent: week.start == current.start)
        }
    }

    /// Days from the start of the period to the reference day (both included) ÷ 7, at least one week; 0 before it began.
    static func weeksElapsed(range: ClosedRange<Date>, reference: Date, calendar: Calendar) -> Double {
        guard reference >= range.lowerBound else { return 0 }
        let first = calendar.startOfDay(for: range.lowerBound), last = calendar.startOfDay(for: reference)
        let days = (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1
        return max(1, Double(days) / 7)
    }

    private static func modeOrder(_ mode: TransportMode) -> Int {
        TransportMode.allCases.firstIndex(of: mode) ?? TransportMode.allCases.count
    }
}
