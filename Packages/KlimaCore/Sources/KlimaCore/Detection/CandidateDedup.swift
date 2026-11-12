import Foundation

// Never twice the same ride: a detected ride may already be in the trip list (entered by hand, saved by "Live verfolgen",
// the quick log) or already waiting in the inbox (detected again with more points). Pure and tested.

/// What the dedup needs to know about a ride that is already entered.
public struct ExistingRide: Hashable, Sendable {
    public var date: Date
    public var fromStationID: String?
    public var toStationID: String?
    public var fromName: String
    public var toName: String
    /// "Hin & Retour": the entry stands for the ride in both directions.
    public var isRoundTrip: Bool

    public init(date: Date, fromStationID: String? = nil, toStationID: String? = nil, fromName: String, toName: String, isRoundTrip: Bool = false) {
        self.date = date
        self.fromStationID = fromStationID
        self.toStationID = toStationID
        self.fromName = fromName
        self.toName = toName
        self.isRoundTrip = isRoundTrip
    }

    func connects(_ from: Station, _ to: Station) -> Direction? {
        let sameFrom = Self.same(fromStationID, fromName, from), sameTo = Self.same(toStationID, toName, to)
        if sameFrom && sameTo { return .forward }
        let reverseFrom = Self.same(fromStationID, fromName, to), reverseTo = Self.same(toStationID, toName, from)
        if reverseFrom && reverseTo { return .backward }
        return nil
    }

    enum Direction { case forward, backward }

    private static func same(_ id: String?, _ name: String, _ station: Station) -> Bool {
        if let id, !id.isEmpty { if id == station.id { return true } }
        let a = StationIndex.normalize(name), b = StationIndex.normalize(station.name)
        return !a.isEmpty && a == b
    }
}

/// A candidate that is already in the inbox (or was decided) – enough to recognise a re-detection.
public struct KnownCandidate: Hashable, Sendable {
    public var fromStationID: String
    public var toStationID: String
    public var departure: Date
    public var arrival: Date
    /// Still waiting for a decision: only these can be replaced by a longer ride.
    public var isPending: Bool

    public init(fromStationID: String, toStationID: String, departure: Date, arrival: Date, isPending: Bool) {
        self.fromStationID = fromStationID
        self.toStationID = toStationID
        self.departure = departure
        self.arrival = arrival
        self.isPending = isPending
    }
}

public enum CandidateDedup {
    /// An entered ride covers a detected one when it is the same pair of stations in the same direction (a round trip
    /// covers both directions) within `window` of the ride or on the calendar day it started (Europe/Vienna) – manual entries carry
    /// the time they were typed in, not the time of the ride. Every entered ride covers only as many detected rides as it
    /// has legs: a commuter who rides A → B twice a day and entered one of them still gets the other proposed.
    public static let window: TimeInterval = 90 * 60

    /// The candidates of `detected` that no entered ride covers, and the ones that are covered (to log them).
    public static func split(_ detected: [DetectedCandidate], rides: [ExistingRide], calendar: Calendar = .vienna)
        -> (fresh: [DetectedCandidate], covered: [(candidate: DetectedCandidate, ride: ExistingRide)]) {
        var capacity: [Int: (forward: Int, backward: Int)] = [:]
        var fresh: [DetectedCandidate] = [], covered: [(DetectedCandidate, ExistingRide)] = []
        for candidate in detected.sorted(by: { $0.departure < $1.departure }) {
            var match: Int?
            for (index, ride) in rides.enumerated() where isNear(ride.date, candidate, calendar: calendar) {
                guard let direction = ride.connects(candidate.from.station, candidate.to.station) else { continue }
                // A round trip is one entry in the direction of its first leg; the other leg is the way back.
                var left = capacity[index] ?? (forward: 1, backward: ride.isRoundTrip ? 1 : 0)
                let available = direction == .forward ? left.forward : left.backward
                guard available > 0 else { continue }
                if direction == .forward { left.forward -= 1 } else { left.backward -= 1 }
                capacity[index] = left
                match = index
                break
            }
            if let match { covered.append((candidate, rides[match])) } else { fresh.append(candidate) }
        }
        return (fresh, covered)
    }

    private static func isNear(_ date: Date, _ candidate: DetectedCandidate, calendar: Calendar) -> Bool {
        if date >= candidate.departure.addingTimeInterval(-window) && date <= candidate.arrival.addingTimeInterval(window) { return true }
        return calendar.isDate(date, inSameDayAs: candidate.departure)
    }

    /// What to do with a detected ride against the inbox.
    public enum Reconcile: Hashable, Sendable {
        /// New: insert it.
        case insert
        /// The same ride again (same pair, overlapping time): drop it.
        case skip
        /// A longer ride that contains a pending one (A → Hub, then A → B): insert it and drop the pending ones.
        case replace([Int])
    }

    /// `known` are the candidates in the inbox and the recently decided ones (decided ones are never replaced).
    public static func reconcile(_ candidate: DetectedCandidate, known: [KnownCandidate]) -> Reconcile {
        let from = candidate.from.station.id, to = candidate.to.station.id
        var replaceable: [Int] = []
        for (index, other) in known.enumerated() {
            let overlap = other.departure < candidate.arrival && candidate.departure < other.arrival
            guard overlap else { continue }
            if other.fromStationID == from && other.toStationID == to { return .skip }
            // A shorter ride on the way of the new one: a stop of the train that was taken for the destination.
            if other.isPending, other.fromStationID == from || other.toStationID == to,
               other.departure >= candidate.departure.addingTimeInterval(-300), other.arrival <= candidate.arrival.addingTimeInterval(300) {
                replaceable.append(index)
            } else if other.fromStationID == from || other.toStationID == to {
                // A decided ride of the same trip: do not propose its longer or shorter twin again.
                return .skip
            }
        }
        return replaceable.isEmpty ? .insert : .replace(replaceable)
    }
}
