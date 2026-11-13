import Foundation

/// Where a trip's ride time comes from, in the order the resolver tries them.
public enum TravelTimeSource: String, CaseIterable, Sendable, Hashable {
    /// „Dauer“ in the trip editor (above 0 and at most a day).
    case entered
    /// Departure and arrival the app already knows: a connection logged from the Fahrplan (planned times) or a ride that
    /// „Fahrten erkennen“ recorded (detected times). Derived on read, nothing is written.
    case timetable
    /// `TravelTimeModel` – average speed by mode and distance. Always labelled as an estimate.
    case estimated

    /// Entered or from departure/arrival – everything that is not the speed model.
    public var isRecorded: Bool { self != .estimated }
}

/// The ride time of one trip entry.
public struct ResolvedTravelTime: Hashable, Sendable {
    /// One direction, minutes.
    public var minutesPerDirection: Double
    public var source: TravelTimeSource
    /// Rides of the entry (a round trip is two; the way back is taken to last as long as the way there).
    public var legs: Int

    public init(minutesPerDirection: Double, source: TravelTimeSource, legs: Int) {
        self.minutesPerDirection = minutesPerDirection
        self.source = source
        self.legs = legs
    }

    /// All rides of the entry, minutes.
    public var minutes: Double { minutesPerDirection * Double(legs) }
}

/// Picks the ride time of a trip (docs/TIME_BALANCE.md §2), in this order:
/// 1. the duration the holder entered (`durationMinutes` from 1 to 1440);
/// 2. arrival minus departure when the app knows both: the departure has a time of day (not exactly midnight, which is
///    how a date without a time is stored) and the difference lies between 1 and 1440 minutes. Legs of a planner journey
///    share the journey's departure as their date, so a later leg starts when the leg before it arrived (its share
///    includes the change); without that arrival the later leg is estimated;
/// 3. the speed model (`TravelTimeModel`).
public enum TravelTimeResolver {
    /// Shortest and longest ride the resolver accepts, minutes.
    public static let validMinutes: ClosedRange<Double> = 1...1440

    /// Where a ride starts.
    public enum LegStart: Hashable, Sendable {
        /// At the trip's own date (a trip of its own, or the first leg of a journey).
        case own
        /// After the previous leg of the same journey, which arrived at `arrival` (nil = unknown).
        case afterLeg(arrival: Date?)
    }

    /// The ride time of `trip`.
    public static func resolve(_ trip: TimeTripInput, start: LegStart = .own, model: TravelTimeModel = .standard,
                               calendar: Calendar = .vienna) -> ResolvedTravelTime {
        let legs = trip.legs
        if let entered = enteredMinutes(trip.durationMinutes) {
            return ResolvedTravelTime(minutesPerDirection: entered, source: .entered, legs: legs)
        }
        if let measured = timetableMinutes(trip, start: start, calendar: calendar) {
            return ResolvedTravelTime(minutesPerDirection: measured, source: .timetable, legs: legs)
        }
        return ResolvedTravelTime(minutesPerDirection: model.minutes(trip.mode, km: trip.distanceKm), source: .estimated, legs: legs)
    }

    /// Every trip of `trips` by id. Legs of a journey are taken in travel order (`legIndex`), so each one knows when the
    /// leg before it arrived; a journey's legs must all be in `trips` for that (they share their date, so a period
    /// filter keeps or drops them together).
    public static func resolveAll(_ trips: [TimeTripInput], model: TravelTimeModel = .standard,
                                  calendar: Calendar = .vienna) -> [UUID: ResolvedTravelTime] {
        var result: [UUID: ResolvedTravelTime] = [:]
        result.reserveCapacity(trips.count)
        var journeys: [UUID: [TimeTripInput]] = [:]
        for trip in trips {
            if let journey = trip.journeyID {
                journeys[journey, default: []].append(trip)
            } else {
                result[trip.id] = resolve(trip, model: model, calendar: calendar)
            }
        }
        for legs in journeys.values {
            let ordered = legs.sorted { ($0.legIndex, $0.date, $0.id.uuidString) < ($1.legIndex, $1.date, $1.id.uuidString) }
            for (position, leg) in ordered.enumerated() {
                let start: LegStart = position == 0 ? .own : .afterLeg(arrival: ordered[position - 1].arrivalAt)
                result[leg.id] = resolve(leg, start: start, model: model, calendar: calendar)
            }
        }
        return result
    }

    /// An entered duration, nil when it is unknown (0) or out of range.
    public static func enteredMinutes(_ minutes: Int) -> Double? {
        let value = Double(minutes)
        return minutes > 0 && validMinutes.contains(value) ? value : nil
    }

    /// Arrival minus departure (rule 2 above), nil when it does not apply.
    public static func timetableMinutes(_ trip: TimeTripInput, start: LegStart = .own, calendar: Calendar = .vienna) -> Double? {
        guard let arrival = trip.arrivalAt, hasTimeOfDay(trip.date, calendar: calendar) else { return nil }
        let departure: Date
        switch start {
        case .own:
            departure = trip.date
        case .afterLeg(let previous):
            // The previous leg's arrival when the legs share the journey's date; a leg with a later date of its own
            // starts there.
            guard let previous else { return nil }
            departure = max(trip.date, previous)
        }
        let minutes = arrival.timeIntervalSince(departure) / 60
        return validMinutes.contains(minutes) ? minutes : nil
    }

    /// False for a date at local midnight (within the first second) – how a day without a time is stored.
    public static func hasTimeOfDay(_ date: Date, calendar: Calendar = .vienna) -> Bool {
        date.timeIntervalSince(calendar.startOfDay(for: date)) >= 1
    }
}

/// The „Dauer“ wheel in the trip editor: hours and minutes in 5-minute steps.
public enum DurationWheel {
    public static let step = 5
    /// Longest value the wheel offers: 23 Std. 55 Min.
    public static let maximumMinutes = 23 * 60 + 55
    public static let hours = Array(0...23)
    public static let minutes = Array(stride(from: 0, through: 55, by: 5))

    /// `minutes` on the wheel: the nearest 5-minute step, at least 5 minutes, at most 23 Std. 55 Min.
    public static func snapped(_ minutes: Double) -> Int {
        guard minutes.isFinite else { return step }
        let steps = (minutes / Double(step)).rounded()
        return min(maximumMinutes, max(step, Int(steps) * step))
    }

    public static func split(_ minutes: Int) -> (hours: Int, minutes: Int) {
        let value = min(maximumMinutes, max(0, minutes))
        return (value / 60, value % 60)
    }

    /// Hours and minutes from the wheel; 0 h 0 min is never a duration (it becomes 5 minutes).
    public static func join(hours: Int, minutes: Int) -> Int {
        let total = min(23, max(0, hours)) * 60 + min(55, max(0, minutes))
        return min(maximumMinutes, max(step, total))
    }
}
