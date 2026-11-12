import Foundation

// The one optional timetable lookup of a candidate (docs/TRIP_DETECTION.md §5): "does a train run between these two
// stations at about this time?". Only with the user's consent for live data, only station ids and times go out (never
// a coordinate), at most once per candidate, through the same throttled client as the planner. The matching of the answer
// is pure and lives here.

/// A connection of the timetable between two stations.
public struct TimetableConnection: Codable, Hashable, Sendable {
    public var departure: Date
    public var arrival: Date
    /// "RJX 662", "REX 5429" – when the timetable names the train.
    public var line: String?

    public init(departure: Date, arrival: Date, line: String? = nil) {
        self.departure = departure
        self.arrival = arrival
        self.line = line
    }

    /// "RJX 662 um 08:12" in Vienna time – the line the card shows.
    public var summary: String {
        let c = Calendar.vienna.dateComponents([.hour, .minute], from: departure)
        let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        if let line, !line.isEmpty { return "\(line) fährt um \(time)" }
        return "Zug um \(time) zwischen beiden Bahnhöfen"
    }
}

/// Asks a timetable for the connections between two stations around a time. Returns nil when no answer can be had
/// (no consent, offline, throttled) – never an empty list for "unknown".
public protocol TimetableLookup: Sendable {
    func connections(fromStationID: String, toStationID: String, around: Date) async -> [TimetableConnection]?
}

public enum TimetableConfirmation {
    /// The ride's departure may differ from the train's by this much (boarding, waiting on the platform, delays) …
    public static let departureTolerance: TimeInterval = 15 * 60
    /// … and its arrival (delays, walking out of the station area).
    public static let arrivalTolerance: TimeInterval = 25 * 60

    /// The connection that fits the ride best, or `.noMatch`; `.unavailable` for a nil answer.
    public static func verdict(departure: Date, arrival: Date, connections: [TimetableConnection]?) -> TimetableVerdict {
        guard let connections else { return .unavailable }
        let fitting = connections.filter {
            abs($0.departure.timeIntervalSince(departure)) <= departureTolerance && abs($0.arrival.timeIntervalSince(arrival)) <= arrivalTolerance
        }
        guard let best = fitting.min(by: { distance($0, departure, arrival) < distance($1, departure, arrival) }) else { return .noMatch }
        return .confirmed(best)
    }

    private static func distance(_ c: TimetableConnection, _ departure: Date, _ arrival: Date) -> TimeInterval {
        abs(c.departure.timeIntervalSince(departure)) + abs(c.arrival.timeIntervalSince(arrival))
    }
}
