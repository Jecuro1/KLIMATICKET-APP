import Foundation

// MARK: - „Zeitbilanz“ (docs/TIME_BALANCE.md) – what the time side of a trip is computed from

/// Where a recorded arrival delay came from (`TripEntity.delaySourceRaw`; "" = not recorded).
public enum TripDelaySource: String, Codable, CaseIterable, Sendable {
    /// The holder typed it in.
    case manual
    /// Taken from live data while the trip was followed.
    case live

    /// "" and unknown values mean "not recorded".
    public init?(storedValue raw: String) {
        guard let source = TripDelaySource(rawValue: raw) else { return nil }
        self = source
    }
}

/// One saved trip (or one leg of a „Reise mit Etappen“) as the time balance sees it. The app maps its entities to this
/// value; `TripRecord` stays as it is.
public struct TimeTripInput: Hashable, Sendable, Identifiable {
    public var id: UUID
    /// Departure (planner trips: the planned departure of the journey's first ride leg – the date of every leg).
    public var date: Date
    public var fromName: String
    public var toName: String
    public var mode: TransportMode
    /// One direction, km.
    public var distanceKm: Double
    public var isRoundTrip: Bool
    public var journeyID: UUID?
    public var legIndex: Int
    /// Duration of one direction as the holder entered it, minutes (0 = unknown).
    public var durationMinutes: Int
    /// Planned (planner) or detected (Fahrten erkennen) arrival of this ride, one direction.
    public var arrivalAt: Date?
    /// Arrival delay in minutes; counted only when `delaySource` is set.
    public var delayMinutes: Int
    public var delaySource: TripDelaySource?

    public init(id: UUID = UUID(), date: Date, fromName: String = "", toName: String = "", mode: TransportMode, distanceKm: Double,
                isRoundTrip: Bool = false, journeyID: UUID? = nil, legIndex: Int = 0, durationMinutes: Int = 0,
                arrivalAt: Date? = nil, delayMinutes: Int = 0, delaySource: TripDelaySource? = nil) {
        self.id = id
        self.date = date
        self.fromName = fromName
        self.toName = toName
        self.mode = mode
        self.distanceKm = distanceKm
        self.isRoundTrip = isRoundTrip
        self.journeyID = journeyID
        self.legIndex = legIndex
        self.durationMinutes = durationMinutes
        self.arrivalAt = arrivalAt
        self.delayMinutes = delayMinutes
        self.delaySource = delaySource
    }

    /// Rides of this entry: a round trip is two.
    public var legs: Int { isRoundTrip ? 2 : 1 }

    /// The recorded delay (never negative), nil when none was recorded.
    public var recordedDelayMinutes: Int? {
        guard delaySource != nil else { return nil }
        return max(0, delayMinutes)
    }
}
